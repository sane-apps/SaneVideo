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
  @RecordingActor var pendingSource: RecordingSource? = nil  // Track transition for graceful handoff
  @RecordingActor var isSwitching = false  // Prevention of overlapping switches
  @RecordingActor var isMicMuted = false  // Mic muting state
  @RecordingActor var outputURL: URL?
  let diskSpaceMonitor = DiskSpaceMonitor()

  // Components
  @RecordingActor let timeCoordinator = RecordingTimeCoordinator()

  // CRITICAL FIX: Track source switch to detect if new source fails silently
  @RecordingActor var sourceSwitchTimeoutTask: Task<Void, Never>?

  // Subscriptions
  var cancellables = Set<AnyCancellable>()

  // Task Lifecycle Management (for cancellation on deinit)
  @RecordingActor var activeRecordingTask: Task<Void, Never>?
  @RecordingActor var activeSwitchTask: Task<Void, Never>?

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
    if TestEnvironment.isUITesting {
      AppLogger.recording.info("🛠️ [UI TEST] Bypassing real recording engine")
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

    // Use RenderingService shared instance
    let renderingService = RenderingService.shared
    self.videoWriter = VideoWriter(renderingService: renderingService)
    do {
      try self.videoWriter?.start(outputURL: url)
    } catch {
      AppLogger.recording.error("Failed to start video writer: \(error)")
      await MainActor.run {
        self.onError?(AppError.recordingEngineError("Failed to start recording"))
      }
      return
    }
    isRecording = true
    isPaused = false
    currentSource = initialSource
    timeCoordinator.reset()

    await MainActor.run { self.diskSpaceMonitor.start() }

    if initialSource == .camera {
      do {
        try await cameraService.start()
      } catch {
        await MainActor.run { self.onError?(.cameraSetupFailed(error)) }
        return
      }
    } else {
      do {
        try await self.screenRecorder.start()
      } catch {
        await MainActor.run {
          self.onError?(.screenCaptureUnavailable)
        }
        return
      }
    }

    await MainActor.run { self.audioService.start() }

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

    if TestEnvironment.isUITesting {
      AppLogger.recording.info("🛠️ [UI TEST] Generating programmatic mock file")

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

    activeSwitchTask?.cancel()
    activeSwitchTask = nil

    // Finalize components
    await screenRecorder.stop()
    soundAnalysisService.stopRealTimeAnalysis()

    let finalURL = await videoWriter?.finish()

    if let url = finalURL {
      let cursorService = await ServiceContainer.shared.cursorTrackingService
      _ = try? await cursorService.stopTrackingAndSave(to: url)
      
      // Stop click tracking and save
      let clickService = await ServiceContainer.shared.clickTrackingService
      _ = try? await clickService.stopTrackingAndSave(to: url)
    }

    // Cleanup
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

  // MARK: - Monitoring

  deinit {
    // Cancel any active tasks
    activeRecordingTask?.cancel()
    activeSwitchTask?.cancel()
    sourceSwitchTimeoutTask?.cancel()

    NotificationCenter.default.removeObserver(self)
    NSWorkspace.shared.notificationCenter.removeObserver(self)
  }
}
