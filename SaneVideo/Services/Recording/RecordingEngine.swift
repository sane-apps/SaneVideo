//
//  RecordingEngine.swift
//  SaneVideo
//
//  Created by SaneVideo Refactor
//

import AVFoundation
import AppKit
import Combine
import CoreMedia
import Foundation
import OSLog
import ScreenCaptureKit

@MainActor
class RecordingEngine: NSObject, @unchecked Sendable {
  // Error handler callback - will be called on Main Queue
  var onError: ((AppError) -> Void)?

  // Callback to notify AppState about system overlay changes
  @MainActor var onPresenterOverlayChanged: ((Bool) -> Void)?

  // Callback to notify when screen recording is stopped externally (e.g. via system menu)
  @MainActor var onScreenRecordingStoppedExternally: (() -> Void)?

  // Callback to notify when user selects content in picker (PiP can now be shown)
  @MainActor var onContentSelected: (() -> Void)?

  // Audio Level Publisher (Forwarded from AudioService)
  var audioLevelSubject: PassthroughSubject<Float, Never> {
    audioService.audioLevelSubject
  }

  // Helpers
  // Services
  let cameraService: CameraServiceProtocol
  @RecordingActor var videoWriter: VideoWriter?
  let screenRecorder: ScreenRecorder
  let audioService: AudioService
  let soundAnalysisService: SoundAnalysisService

  // Thread Safety: Global RecordingActor handle all serialization
  // This replaces the old manual processingQueue

  // State (Isolated to RecordingActor)
  @RecordingActor var isRecording = false
  @RecordingActor var isPaused = false
  @RecordingActor var isStopping = false  // Flag to prevent rapid restart during concatenation
  @RecordingActor var currentSource: RecordingSource = .camera
  @RecordingActor var pendingSource: RecordingSource?  // Track transition for graceful handoff
  @RecordingActor var isSwitching = false  // Prevention of overlapping switches
  @RecordingActor var isMicMuted = false  // Mic muting state
  @RecordingActor var outputURL: URL?
  let diskSpaceMonitor = DiskSpaceMonitor()

  // Components
  @RecordingActor let timeCoordinator = RecordingTimeCoordinator()

  // CRITICAL FIX: Track source switch to detect if new source fails silently
  // nonisolated(unsafe) allows safe cancellation from deinit on any thread
  nonisolated(unsafe) var sourceSwitchTimeoutTask: Task<Void, Never>?

  // Subscriptions
  var cancellables = Set<AnyCancellable>()

  // Task Lifecycle Management (for cancellation on deinit)
  // nonisolated(unsafe) allows safe cancellation from deinit on any thread
  // (Task.cancel() is thread-safe)
  nonisolated(unsafe) var activeRecordingTask: Task<Void, Never>?
  nonisolated(unsafe) var activeSwitchTask: Task<Void, Never>?

  // Preview layer for Screen Recording
  let screenPreviewLayer = AVSampleBufferDisplayLayer()

  override init() {
    let container = ServiceContainer.shared
    cameraService = container.cameraService
    audioService = container.audioService
    soundAnalysisService = container.soundAnalysisService
    screenRecorder = ScreenRecorder()

    super.init()
    screenPreviewLayer.videoGravity = .resizeAspectFill

    setupSubscriptions()
    setupDiskMonitor()
    setupSleepObservers()
    setupInterruptionObservers()
  }

  // For testing
  init(
    cameraService: CameraServiceProtocol,
    audioService: AudioService? = nil,
    soundAnalysisService: SoundAnalysisService? = nil,
    screenRecorder: ScreenRecorder? = nil
  ) {
    let container = ServiceContainer.shared
    self.cameraService = cameraService
    self.audioService = audioService ?? container.audioService
    self.soundAnalysisService = soundAnalysisService ?? container.soundAnalysisService
    self.screenRecorder = screenRecorder ?? ScreenRecorder()

    super.init()
    screenPreviewLayer.videoGravity = .resizeAspectFill

    setupSubscriptions()
    setupDiskMonitor()
    setupSleepObservers()
    setupInterruptionObservers()
  }

  // MARK: - Internal Setup (Setup logic in RecordingEngine+Setup.swift)

  @objc func handleSleep() {
    Task { @RecordingActor in
      if isRecording, !isPaused {
        pauseRecording()
      }
    }
  }

  @objc func handleWake() {}

  // MARK: - Interruption Handlers

  @objc func handleSessionWasInterrupted(notification: Notification) {
    Task { @RecordingActor in
      guard isRecording, !isPaused else { return }
      AppLogger.recording.warning("⚠️ Recording Interrupted. Pausing...")
      pauseRecording()
      await MainActor.run {
        ServiceContainer.shared.toastManager.show(
          "Recording Paused: Camera Interrupted", type: .error)
      }
    }
  }

  @objc func handleSessionInterruptionEnded(notification: Notification) {
    AppLogger.recording.info("✅ Recording Interruption Ended. Ready to resume.")
  }

  @objc func handleSessionRuntimeError(notification: Notification) {
    guard let error = notification.userInfo?[AVCaptureSessionErrorKey] as? Error else { return }
    Task { @RecordingActor in
      guard isRecording else { return }
      AppLogger.recording.error("❌ Recording Runtime Error: \(error.localizedDescription)")
      _ = await stopRecording()
      await MainActor.run {
        ServiceContainer.shared.errorPresenter.present(
          AppError.recordingEngineError("Camera Error: \(error.localizedDescription)"))
      }
    }
  }

  @objc func handleAudioConfigurationChange(notification: Notification) {
    Task { @RecordingActor in
      guard isRecording, !isPaused else { return }
      AppLogger.recording.warning("⚠️ Audio Configuration Changed. Pausing...")
      pauseRecording()
      await MainActor.run {
        ServiceContainer.shared.toastManager.show(
          "Recording Paused: Check Audio Device", type: .error)
      }
    }
  }

  // MARK: - Public Interface

  @RecordingActor
  func startRecording(initialSource: RecordingSource) async {
    guard !isRecording, !isStopping else {
      AppLogger.recording.warning("Cannot start recording: already recording or stopping")
      return
    }

    // isTesting is now a class-level property
    if TestEnvironment.isTesting {
      AppLogger.recording.info("🛠️ [TEST] Bypassing real recording engine")
      let tempDir = FileManager.default.temporaryDirectory
      let filename = "MockRecording_\(Date().timeIntervalSince1970).mp4"
      self.outputURL = tempDir.appendingPathComponent(filename)

      isRecording = true
      isPaused = false
      currentSource = initialSource
      timeCoordinator.reset()
      return
    }

    let filename = "Recording_\(Date().timeIntervalSince1970).mp4"
    guard let moviesDir = FileManager.default.urls(for: .moviesDirectory, in: .userDomainMask).first
    else {
      AppLogger.recording.error("Cannot find Movies directory")
      await MainActor.run {
        self.onError?(AppError.recordingEngineError("Cannot find Movies directory"))
      }
      return
    }
    let outputDir = moviesDir.appendingPathComponent("SaneVideo/Recordings")
    let url = outputDir.appendingPathComponent(filename)
    self.outputURL = url

    do {
      try FileManager.default.createDirectory(at: outputDir, withIntermediateDirectories: true)
    } catch {
      AppLogger.recording.error("Failed to create output directory: \(error)")
      await MainActor.run {
        self.onError?(AppError.recordingEngineError("Cannot create recording directory"))
      }
      return
    }

    // CRITICAL: Create videoWriter but don't set isRecording until ALL services start successfully
    // This prevents partial failure states where isRecording=true but no input source
    let renderingService = RenderingService.shared
    self.videoWriter = VideoWriter(renderingService: renderingService)

    do {
      try self.videoWriter?.start(outputURL: url)
    } catch {
      AppLogger.recording.error("Failed to start video writer: \(error)")
      // CRITICAL: Cleanup on failure
      self.videoWriter = nil
      self.outputURL = nil
      await MainActor.run {
        self.onError?(AppError.recordingEngineError("Failed to start recording"))
      }
      return
    }

    // CRITICAL: Start disk space monitor BEFORE setting isRecording
    await MainActor.run { self.diskSpaceMonitor.start() }

    // CRITICAL: Start all services BEFORE setting isRecording=true
    // This ensures we only mark as recording when everything is actually ready
    if initialSource == .camera {
      do {
        try await cameraService.start()
      } catch {
        // CRITICAL: Cleanup on failure - videoWriter was created but camera failed
        AppLogger.recording.error("Camera start failed, cleaning up videoWriter")
        _ = await self.videoWriter?.finish()  // Try to finish gracefully
        self.videoWriter = nil
        self.outputURL = nil
        await MainActor.run {
          self.diskSpaceMonitor.stop()
          self.onError?(.cameraSetupFailed(error))
        }
        return
      }
    } else {
      do {
        // CRITICAL: Ensure camera is active for PiP overlay during screen sharing
        // We do this BEFORE starting the screen recorder to avoid flicker
        try await cameraService.start()

        try await self.screenRecorder.start()
      } catch {
        // CRITICAL: Cleanup on failure - videoWriter was created but screen recorder failed
        AppLogger.recording.error("Screen recorder (or camera) start failed, cleaning up videoWriter")
        _ = await self.videoWriter?.finish()  // Try to finish gracefully
        self.videoWriter = nil
        self.outputURL = nil
        await MainActor.run {
          self.diskSpaceMonitor.stop()
          self.onError?(.screenCaptureUnavailable)
        }
        return
      }
    }

    // CRITICAL: Start audio service
    await MainActor.run { self.audioService.start() }

    // CRITICAL: Only NOW set isRecording=true after ALL services started successfully
    isRecording = true
    isPaused = false
    currentSource = initialSource
    timeCoordinator.reset()

    // Start Real-time Sound Analysis
    let format = AVAudioFormat(standardFormatWithSampleRate: 44100, channels: 1)!
    soundAnalysisService.startRealTimeAnalysis(format: format)
    await MainActor.run {
      self.setupSoundAnalysisMonitoring()
    }

    if initialSource == .screen {
      let cursorService = await ServiceContainer.shared.cursorTrackingService
      await cursorService.startTracking()

      // Start click tracking for auto-zoom feature
      let clickService = await ServiceContainer.shared.clickTrackingService
      await clickService.startTracking()
    }

    AppLogger.recording.info(
      "Started recording (Source: \(initialSource == .camera ? "camera" : "screen"))")
  }
  @RecordingActor
  @discardableResult
  func stopRecording() async -> URL? {
    AppLogger.recording.info(
      "🛑 Engine: stopRecording called. State: isRecording=\(self.isRecording), isStopping=\(self.isStopping)"
    )

    guard isRecording, !isStopping else {
      AppLogger.recording.warning(
        "🛑 Engine: stopRecording ignored (guard failed). isRecording=\(isRecording), isStopping=\(isStopping)"
      )
      return nil
    }

    isRecording = false
    isStopping = true
    isPaused = false

    await MainActor.run {
      diskSpaceMonitor.stop()
    }

    if TestEnvironment.isTesting {
      AppLogger.recording.info("🛠️ [TEST] Generating programmatic mock file")

      // Use Temporary Directory to avoid Sandbox/TCC issues
      let tempDir = FileManager.default.temporaryDirectory
      let mockURL = tempDir.appendingPathComponent(
        "MockRecording_\(Date().timeIntervalSince1970).mp4")

      await generateMockVideo(to: mockURL)

      isStopping = false

      // Clean up state
      self.videoWriter = nil
      self.outputURL = nil
      timeCoordinator.reset()

      return mockURL
    }

    // CRITICAL: Cancel any active switch operations
    sourceSwitchTimeoutTask?.cancel()
    sourceSwitchTimeoutTask = nil

    // CRITICAL: Clear switch state to prevent hanging
    if isSwitching {
      AppLogger.recording.warning("🛑 Stopping recording during active switch. Cancelling switch.")
      pendingSource = nil
      isSwitching = false
      timeCoordinator.startTimeNeedsRecalibration = false
    }

    // CRITICAL: Stop services first (but don't cleanup until file is saved)
    await screenRecorder.stop()
    soundAnalysisService.stopRealTimeAnalysis()

    // CRITICAL: Finish video writer with timeout protection
    let finalURL: URL?
    if let writer = videoWriter {
      do {
        // Add timeout to finish() to prevent hanging (30 seconds should be plenty)
        finalURL = try await withTimeout(seconds: 30) {
          await writer.finish()
        }
      } catch {
        AppLogger.recording.error("⚠️ VideoWriter finish() timed out or failed: \(error.localizedDescription)")
        // CRITICAL: Even if finish() fails, try to get the file
        // The file might still be valid even if finish() didn't complete
        finalURL = outputURL
        AppLogger.recording.warning("Using outputURL as fallback: \(outputURL?.path ?? "nil")")
      }
    } else {
      finalURL = nil
    }

    // CRITICAL: Save cursor/click tracking only if we have a valid file
    if let url = finalURL {
      let cursorService = await ServiceContainer.shared.cursorTrackingService
      _ = try? await cursorService.stopTrackingAndSave(to: url)

      // Stop click tracking and save
      let clickService = await ServiceContainer.shared.clickTrackingService
      _ = try? await clickService.stopTrackingAndSave(to: url)
    } else {
      AppLogger.recording.warning("⚠️ No final URL, skipping cursor/click tracking save")
    }

    // CRITICAL: Cleanup only after we've attempted to save everything
    videoWriter = nil
    outputURL = nil
    timeCoordinator.reset()
    sourceSwitchTimeoutTask?.cancel()
    sourceSwitchTimeoutTask = nil
    isStopping = false

    AppLogger.recording.info("Recording stopped. File: \(finalURL?.lastPathComponent ?? "nil")")
    return finalURL
  }

  @RecordingActor
  func pauseRecording() {
    guard isRecording, !isPaused else { return }
    isPaused = true
    timeCoordinator.pause()
    AppLogger.recording.info("Paused recording")
  }

  @RecordingActor
  func resumeRecording() {
    guard isRecording, isPaused else { return }
    isPaused = false
    timeCoordinator.resume()
    AppLogger.recording.info("Resumed recording")
  }

  func pause() { Task { @RecordingActor in pauseRecording() } }
  func resume() { Task { @RecordingActor in resumeRecording() } }

  @RecordingActor
  func clearCameraFrame() {
    AppLogger.recording.info("📷 RecordingActor: clearing camera frame")
    self.videoWriter?.updateCameraFrame(nil)
  }

  // MARK: - Monitoring

  deinit {
    // Cancel any active tasks
    activeRecordingTask?.cancel()
    activeSwitchTask?.cancel()
    sourceSwitchTimeoutTask?.cancel()

    NotificationCenter.default.removeObserver(self)
    NSWorkspace.shared.notificationCenter.removeObserver(self)
  }

  // MARK: - Sample Processing

  @RecordingActor func processSample(_ sampleBuffer: CMSampleBuffer, source: RecordingSource) {
    autoreleasepool {
      if source == .camera, let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) {
        videoWriter?.updateCameraFrame(pixelBuffer)
      }

      if timeCoordinator.startTimeNeedsRecalibration, source == currentSource {
        if isPaused { AppLogger.recording.debug("Drop: isPaused") }
        if !isRecording { AppLogger.recording.debug("Drop: !isRecording") }
        if videoWriter == nil { AppLogger.recording.error("Drop: videoWriter is nil") }
        if let w = videoWriter, !w.isWriting {
          AppLogger.recording.error(
            "Drop: videoWriter is NOT writing. Error: \(String(describing: w.error))")
        }
      }

      let isTargetSource = (source == currentSource) || (source == pendingSource)
      guard !isPaused, isRecording, isTargetSource else { return }

      if source == pendingSource {
        AppLogger.recording.info(
          "Seamless Handoff: Received first frame from \(source). Switching currentSource.")
        currentSource = source
        pendingSource = nil
        sourceSwitchTimeoutTask?.cancel()
        sourceSwitchTimeoutTask = nil
      }

      guard let writer = videoWriter, writer.isWriting else { return }

      if !writer.isWriting, isRecording, !isPaused, !isSwitching {
        let errorDescription = writer.error?.localizedDescription ?? "Unknown writer error"
        Task { @MainActor in
          self.onError?(AppError.recordingEngineError("Recording failed: \(errorDescription)"))
        }
        return
      }

      let samplePresentationTime = CMSampleBufferGetPresentationTimeStamp(sampleBuffer)
      let result = timeCoordinator.processSampleTime(samplePresentationTime)

      if result.isFirstSample {
        videoWriter?.startSession(at: result.presentationTime)
      }

      if !timeCoordinator.startTimeNeedsRecalibration {
        sourceSwitchTimeoutTask?.cancel()
        sourceSwitchTimeoutTask = nil
      }

      videoWriter?.writeVideo(sampleBuffer: sampleBuffer, presentationTime: result.presentationTime, source: source)
    }
  }

  @RecordingActor func processAudioSample(_ sampleBuffer: CMSampleBuffer) {
    autoreleasepool {
      guard !isMicMuted else { return }
      guard !isPaused, isRecording, let writer = videoWriter, writer.isWriting else { return }
      guard !timeCoordinator.startTimeNeedsRecalibration else { return }

      let bufferToWrite = timeCoordinator.adjustBufferTime(sampleBuffer)

      if timeCoordinator.startTime == .zero {
        let presentationTime = bufferToWrite.presentationTimeStamp
        timeCoordinator.startTime = presentationTime
        timeCoordinator.startTimeNeedsRecalibration = false
        videoWriter?.startSession(at: presentationTime)
        AppLogger.recording.info(
          "Recording started (Mic Audio first). First sample time: \(presentationTime.seconds)")
      }

      if timeCoordinator.startTime != .zero,
        bufferToWrite.presentationTimeStamp >= timeCoordinator.startTime {
        videoWriter?.writeMicAudio(sampleBuffer: bufferToWrite)
        soundAnalysisService.analyze(sampleBuffer: sampleBuffer)
      }
    }
  }

  @RecordingActor func processSystemAudioSample(_ sampleBuffer: CMSampleBuffer) {
    autoreleasepool {
      guard currentSource == .screen else { return }
      guard !isPaused, isRecording, let writer = videoWriter, writer.isWriting else { return }
      guard !timeCoordinator.startTimeNeedsRecalibration else { return }

      let bufferToWrite = timeCoordinator.adjustBufferTime(sampleBuffer)

      if timeCoordinator.startTime == .zero {
        let presentationTime = bufferToWrite.presentationTimeStamp
        timeCoordinator.startTime = presentationTime
        timeCoordinator.startTimeNeedsRecalibration = false
        videoWriter?.startSession(at: presentationTime)
        AppLogger.recording.info(
          "Recording started (System Audio first). First sample time: \(presentationTime.seconds)")
      }

      if timeCoordinator.startTime != .zero,
        bufferToWrite.presentationTimeStamp >= timeCoordinator.startTime {
        videoWriter?.writeSystemAudio(sampleBuffer: bufferToWrite)
      }
    }
  }
}
