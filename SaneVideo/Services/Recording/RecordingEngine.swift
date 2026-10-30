import AVFoundation
import AppKit
import Combine
import CoreMedia
import Foundation
import OSLog
import ScreenCaptureKit

@MainActor
class RecordingEngine: NSObject {
  // Error handler callback - will be called on Main Queue
  var onError: ((AppError) -> Void)?

  // Callback to notify AppState about system overlay changes
  @MainActor var onPresenterOverlayChanged: ((Bool) -> Void)?

  // Callback to notify when screen recording is stopped externally (e.g. via system menu)
  @MainActor var onScreenRecordingStoppedExternally: (() -> Void)?

  // Callback to notify when user selects content in picker (PiP can now be shown)
  @MainActor var onContentSelected: (() -> Void)?

  // The engine is ending a take itself (capture error, low disk); onStoppedAfterError follows with the file.
  @MainActor var onStoppingAfterError: (() -> Void)?

  // The engine ended a take itself (capture error, low disk): the finished file, if any, and why.
  @MainActor var onStoppedAfterError: ((URL?, AppError) -> Void)?

  // The engine paused a take itself (sleep, capture interruption, audio device change).
  @MainActor var onPausedBySystem: (() -> Void)?

  var audioLevelSubject: PassthroughSubject<Float, Never> {
    audioService.audioLevelSubject
  }

  let cameraService: CameraServiceProtocol
  @RecordingActor var videoWriter: VideoWriterProtocol?
  let screenRecorder: ScreenRecorder
  let audioService: AudioService
  let soundAnalysisService: SoundAnalysisService

  // RecordingActor serializes all recording state.

  @RecordingActor var isRecording = false
  @RecordingActor var isPaused = false
  @RecordingActor var isStopping = false  // Flag to prevent rapid restart during concatenation
  @RecordingActor var currentSource: RecordingSource = .camera
  @RecordingActor var pendingSource: RecordingSource?  // Track transition for graceful handoff
  @RecordingActor var isSwitching = false  // Prevention of overlapping switches
  @RecordingActor var isMicMuted = false
  @RecordingActor var isMicrophoneAudioEnabled = true
  @RecordingActor var outputURL: URL?
  @RecordingActor var didReportWriterFailure = false  // Report a failed writer once per take, not per frame
  let diskSpaceMonitor = DiskSpaceMonitor()

  @RecordingActor let timeCoordinator = RecordingTimeCoordinator()

  // Normalize mic audio to match VideoWriter AAC configuration (48 kHz)
  @RecordingActor private let micAudioResampler = AudioResampler(targetSampleRate: 48_000)

  // PiP Frame Sync: Cached frame for compositing into screen recordings
  @RecordingActor private var cachedPiPFrame: CGRect?
  @RecordingActor private var cachedScreenFrame: CGRect?
  @RecordingActor private var pipFrameSyncCounter: Int = 0
  private let pipFrameSyncInterval: Int = 15  // Sync every 15 frames (~0.5s at 30fps)

  // Track source switch to detect if new source fails silently
  // nonisolated(unsafe) allows safe cancellation from deinit on any thread
  nonisolated(unsafe) var sourceSwitchTimeoutTask: Task<Void, Never>?

  var cancellables = Set<AnyCancellable>()

  // nonisolated(unsafe) so deinit can cancel it; Task.cancel() is thread-safe.
  nonisolated(unsafe) var activeRecordingTask: Task<Void, Never>?
  nonisolated(unsafe) var activeSwitchTask: Task<Void, Never>?

  // Not initialized inline: AVSampleBufferDisplayLayer needs the main thread, and inline initializers run before @MainActor isolation applies.
  var screenPreviewLayer: AVSampleBufferDisplayLayer!

  override init() {
    let container = ServiceContainer.shared
    cameraService = container.cameraService
    audioService = container.audioService
    soundAnalysisService = container.soundAnalysisService
    screenRecorder = ScreenRecorder()

    super.init()
    screenPreviewLayer = AVSampleBufferDisplayLayer()
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
    screenPreviewLayer = AVSampleBufferDisplayLayer()
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
        await MainActor.run {
          self.onPausedBySystem?()
          ServiceContainer.shared.toastManager.show(
            "Recording Paused: the Mac went to sleep. Press Resume to continue.", type: .info)
        }
      }
    }
  }

  // MARK: - Interruption Handlers

  @objc func handleSessionWasInterrupted(notification: Notification) {
    Task { @RecordingActor in
      guard isRecording, !isPaused else { return }
      AppLogger.recording.warning("⚠️ Recording Interrupted. Pausing...")
      pauseRecording()
      await MainActor.run {
        self.onPausedBySystem?()
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
      Task { @MainActor in self.onStoppingAfterError?() }
      let url = await stopRecording()
      let appError = AppError.recordingEngineError("Camera Error: \(error.localizedDescription)")
      await MainActor.run {
        // Hand the finished file to the app so the take is imported and the UI leaves recording.
        if let onStoppedAfterError = self.onStoppedAfterError {
          onStoppedAfterError(url, appError)
        } else {
          ServiceContainer.shared.errorPresenter.present(appError)
        }
      }
    }
  }

  @objc func handleAudioConfigurationChange(notification: Notification) {
    Task { @RecordingActor in
      guard isRecording, !isPaused else { return }
      AppLogger.recording.warning("⚠️ Audio Configuration Changed. Pausing...")
      pauseRecording()
      await MainActor.run {
        self.onPausedBySystem?()
        ServiceContainer.shared.toastManager.show(
          "Recording Paused: Check Audio Device", type: .error)
      }
    }
  }

  // MARK: - Public Interface

  @RecordingActor
  func startRecording(
    initialSource: RecordingSource,
    includeCameraOverlay: Bool = true,
    includeMicrophoneAudio: Bool = true
  ) async {
    guard !isRecording, !isStopping else {
      AppLogger.recording.warning("Cannot start recording: already recording or stopping")
      return
    }

    if TestEnvironment.isTesting {
      AppLogger.recording.info("🛠️ [TEST] Bypassing real recording engine")
      let tempDir = FileManager.default.temporaryDirectory
      let filename = "MockRecording_\(Date().timeIntervalSince1970).mp4"
      self.outputURL = tempDir.appendingPathComponent(filename)

      isRecording = true
      isPaused = false
      isMicrophoneAudioEnabled = includeMicrophoneAudio
      currentSource = initialSource
      timeCoordinator.reset()
      didReportWriterFailure = false
      return
    }

    let stamp = ExportDestination.timestamp()
    let filename = "Recording \(stamp).mp4"
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

    // Capture recording prefs once so all capture paths (camera/screen/writer) agree.
    let (targetFPS, recordingResolution) = await MainActor.run {
      (ServiceContainer.shared.userPreferences.recordingFPS,
       ServiceContainer.shared.userPreferences.recordingResolution)
    }
    let targetSize = recordingResolution.size

    // Ensure ScreenRecorder respects prefs (also used for seamless switches later)
    await MainActor.run {
      self.screenRecorder.targetFrameRate = targetFPS
      self.screenRecorder.targetSize = targetSize
    }

    timeCoordinator.reset()
    didReportWriterFailure = false

    // Set isRecording only after every service starts, so a partial failure never leaves it true.
    let renderingService = RenderingService.shared
    self.videoWriter = VideoWriter(renderingService: renderingService, targetSize: targetSize)
    var cameraWasStarted = false
    var screenWasStarted = false

    do {
      try self.videoWriter?.start(outputURL: url, targetFrameRate: targetFPS)
      self.timeCoordinator.driftTracker = self.videoWriter?.driftTracker
    } catch {
      AppLogger.recording.error("Failed to start video writer: \(error)")
      self.videoWriter = nil
      self.outputURL = nil
      self.timeCoordinator.driftTracker = nil
      await MainActor.run {
        self.onError?(AppError.recordingEngineError("Failed to start recording"))
      }
      return
    }

    await MainActor.run { self.diskSpaceMonitor.start() }

    if initialSource == .camera {
      do {
        try await cameraService.start()
        cameraWasStarted = true
      } catch {
        AppLogger.recording.error("Camera start failed, cleaning up videoWriter")
        await rollbackFailedStart(cameraWasStarted: cameraWasStarted, screenWasStarted: screenWasStarted)
        await MainActor.run {
          self.onError?(.cameraSetupFailed(error))
        }
        return
      }
    } else {
      do {
        if includeCameraOverlay {
          // Only start camera when the user actually wants presenter overlay.
          try await cameraService.start()
          cameraWasStarted = true
        }

        // Re-apply prefs in case they changed since recording started
        await MainActor.run {
          let prefs = ServiceContainer.shared.userPreferences
          self.screenRecorder.targetFrameRate = prefs.recordingFPS
          self.screenRecorder.targetSize = prefs.recordingResolution.size
        }
        try await self.screenRecorder.start()
        screenWasStarted = true
      } catch {
        AppLogger.recording.error("Screen recorder (or camera) start failed, cleaning up videoWriter")
        await rollbackFailedStart(cameraWasStarted: cameraWasStarted, screenWasStarted: screenWasStarted)
        await MainActor.run {
          self.onError?(.screenCaptureUnavailable)
        }
        return
      }
    }

    if includeMicrophoneAudio {
      await MainActor.run { self.audioService.start() }
      let microphoneReady = await waitForMicrophoneCaptureToStart()
      guard microphoneReady else {
        AppLogger.recording.error("Microphone failed to start before recording began")
        await rollbackFailedStart(cameraWasStarted: cameraWasStarted, screenWasStarted: screenWasStarted)
        await MainActor.run {
          self.onError?(
            .recordingEngineError(
              "Microphone failed to start. Recording was cancelled before it could save silent audio."
            )
          )
        }
        return
      }
    } else {
      await MainActor.run { self.audioService.stop() }
    }

    isRecording = true
    isPaused = false
    isMicrophoneAudioEnabled = includeMicrophoneAudio
    currentSource = initialSource


    if initialSource == .screen {
      let clickService = await ServiceContainer.shared.clickTrackingService
      await clickService.startTracking()
    }

    AppLogger.recording.info(
      "Started recording (Source: \(initialSource == .camera ? "camera" : "screen"))")
  }

  @RecordingActor
  func waitForMicrophoneCaptureToStart(
    timeoutNanoseconds: UInt64 = 2_000_000_000,
    pollNanoseconds: UInt64 = 50_000_000,
    allowTestBypass: Bool = true
  ) async -> Bool {
    if allowTestBypass, TestEnvironment.isTesting {
      return true
    }

    if await MainActor.run(body: { self.audioService.isRunning }) {
      return true
    }

    let attempts = max(1, Int(timeoutNanoseconds / max(1, pollNanoseconds)))
    for _ in 0..<attempts {
      if Task.isCancelled {
        return false
      }

      try? await Task.sleep(nanoseconds: pollNanoseconds)

      if await MainActor.run(body: { self.audioService.isRunning }) {
        return true
      }
    }

    return await MainActor.run(body: { self.audioService.isRunning })
  }

  @RecordingActor
  private func rollbackFailedStart(
    cameraWasStarted: Bool,
    screenWasStarted: Bool
  ) async {
    if screenWasStarted {
      await screenRecorder.stop()
    }

    await MainActor.run {
      if cameraWasStarted {
        self.cameraService.stop()
      }
      self.audioService.stop()
      self.diskSpaceMonitor.stop()
    }

    if let writer = videoWriter {
      _ = try? await withTimeout(seconds: 5) {
        await writer.finish()
      }
    }

    if let failedURL = outputURL {
      try? FileManager.default.removeItem(at: failedURL)
    }

    videoWriter = nil
    outputURL = nil
    isMicrophoneAudioEnabled = false
    timeCoordinator.driftTracker = nil
    timeCoordinator.reset()
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

      self.videoWriter = nil
      self.outputURL = nil
      self.isMicrophoneAudioEnabled = false
      self.timeCoordinator.driftTracker = nil
      timeCoordinator.reset()

      return mockURL
    }

    sourceSwitchTimeoutTask?.cancel()
    sourceSwitchTimeoutTask = nil

    // Clear switch state to prevent hanging
    if isSwitching {
      AppLogger.recording.warning("🛑 Stopping recording during active switch. Cancelling switch.")
      pendingSource = nil
      isSwitching = false
      timeCoordinator.startTimeNeedsRecalibration = false
    }

    // Stop services first (but don't cleanup until file is saved)
    await screenRecorder.stop()

    let finalURL: URL?
    if let writer = videoWriter {
      do {
        finalURL = try await withTimeout(seconds: 30) {
          await writer.finish()
        }
      } catch {
        AppLogger.recording.error("⚠️ VideoWriter finish() timed out or failed: \(error.localizedDescription)")
        // If finish() fails, the file may still be usable.
        finalURL = outputURL
        AppLogger.recording.warning("Using outputURL as fallback: \(outputURL?.path ?? "nil")")
      }
    } else {
      finalURL = nil
    }

    // A camera that stops sending frames leaves a sound-only file; say so instead of saving it silently.
    if let url = finalURL,
       let videoTracks = try? await AVURLAsset(url: url).loadTracks(withMediaType: .video),
       videoTracks.isEmpty {
      AppLogger.recording.error("Recording has no video track: the camera or screen sent no frames")
      await MainActor.run {
        ServiceContainer.shared.toastManager.show(
          "This take has sound but no picture: the camera sent no video. Unplug and reconnect the camera, then record again.",
          type: .error
        )
      }
    }

    if let url = finalURL {
      let clickService = await ServiceContainer.shared.clickTrackingService
      _ = try? await clickService.stopTrackingAndSave(to: url)
    } else {
      AppLogger.recording.warning("⚠️ No final URL, skipping click tracking save")
    }

    // Cleanup only after we've attempted to save everything
    videoWriter = nil
    outputURL = nil
    isMicrophoneAudioEnabled = false
    timeCoordinator.driftTracker = nil
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
    activeRecordingTask?.cancel()
    activeSwitchTask?.cancel()
    sourceSwitchTimeoutTask?.cancel()

    NotificationCenter.default.removeObserver(self)
    NSWorkspace.shared.notificationCenter.removeObserver(self)
  }

  // MARK: - Sample Processing

  /// Periodically sync PiP frame from MainActor for compositing
  @RecordingActor private func syncPiPFrameIfNeeded() {
    pipFrameSyncCounter += 1
    guard pipFrameSyncCounter >= pipFrameSyncInterval else { return }
    pipFrameSyncCounter = 0

    Task { @MainActor in
      let pipFrame = ServiceContainer.shared.appState.windowManager.pipWindowFrame
      let screenFrame = self.screenRecorder.recordingFrame

      Task { @RecordingActor in
        self.cachedPiPFrame = pipFrame
        self.cachedScreenFrame = screenFrame
        self.videoWriter?.updatePiPFrame(pipFrame, screenFrame: screenFrame)
      }
    }
  }

  @RecordingActor func processSample(_ sampleBuffer: CMSampleBuffer, source: RecordingSource) {
    autoreleasepool {
      if source == .camera, let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) {
        videoWriter?.updateCameraFrame(pixelBuffer)
      }

      if source == .screen {
        syncPiPFrameIfNeeded()
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

      let shouldDeferPendingCameraFrame =
        isSwitching && currentSource == .screen && pendingSource == .camera && source == .camera

      // During screen -> camera transitions, camera frames can arrive before SCStream.stopCapture()
      // has finished. If we promote on that early frame, we recalibrate onto the camera clock while
      // screen capture is still active, which produces A/V drift. Let performSourceSwitch() finish
      // the stop first, then commit the source flip explicitly.
      if shouldDeferPendingCameraFrame {
        return
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

      guard let writer = videoWriter else { return }

      // The writer leaves .writing mid-take only when it failed (a stop clears isRecording first).
      // Checked before returning, so the take stops with an error instead of dropping every frame.
      if !writer.isWriting {
        if isRecording, !isPaused, !isSwitching, !didReportWriterFailure {
          didReportWriterFailure = true
          let errorDescription = writer.error?.localizedDescription ?? "Unknown writer error"
          AppLogger.recording.error("Video writer stopped writing mid-take: \(errorDescription)")
          Task { @MainActor in
            self.onError?(AppError.recordingEngineError("Recording failed: \(errorDescription)"))
          }
        }
        return
      }

      let samplePresentationTime = CMSampleBufferGetPresentationTimeStamp(sampleBuffer)
      let wasRecalibrating = timeCoordinator.startTimeNeedsRecalibration
      let result = timeCoordinator.processSampleTime(samplePresentationTime)

      if result.isFirstSample {
        videoWriter?.startSession(at: result.presentationTime)
      }

      let didWrite = videoWriter?.writeVideo(
        sampleBuffer: sampleBuffer,
        presentationTime: result.presentationTime,
        source: source
      ) ?? false

      if didWrite {
        if result.usedPendingRecalibration {
          timeCoordinator.commitPendingRecalibrationIfNeeded()
        }
        timeCoordinator.recordWrittenPresentationTime(result.presentationTime)
      } else if wasRecalibrating {
        // Keep the handoff armed until a frame actually lands on disk.
        timeCoordinator.beginSourceSwitchRecalibration()
      }

      if didWrite, !timeCoordinator.startTimeNeedsRecalibration {
        sourceSwitchTimeoutTask?.cancel()
        sourceSwitchTimeoutTask = nil
      }
    }
  }

  @RecordingActor func processAudioSample(_ sampleBuffer: CMSampleBuffer) {
    autoreleasepool {
      guard !isMicMuted else { return }
      guard !isPaused, isRecording, let writer = videoWriter, writer.isWriting else { return }
      let needsInitialSessionStart = timeCoordinator.startTime == .zero

      if needsInitialSessionStart {
        let samplePresentationTime = CMSampleBufferGetPresentationTimeStamp(sampleBuffer)
        let result = timeCoordinator.processSampleTime(samplePresentationTime)
        if result.isFirstSample {
          videoWriter?.startSession(at: result.presentationTime)
        }
      }

      let adjusted = timeCoordinator.adjustMicrophoneBufferTime(sampleBuffer)
      let bufferToWrite: CMSampleBuffer
      if let resampled = micAudioResampler.resampleIfNeeded(adjusted) {
        bufferToWrite = resampled
      } else {
        bufferToWrite = adjusted
      }

      if needsInitialSessionStart {
        AppLogger.recording.info(
          "Recording started (Mic Audio first). First sample time: \(timeCoordinator.startTime.seconds)")
      }

      if timeCoordinator.startTime != .zero,
        bufferToWrite.presentationTimeStamp >= timeCoordinator.startTime {
        let didWrite = videoWriter?.writeMicAudio(sampleBuffer: bufferToWrite) ?? false
        if didWrite {
          timeCoordinator.recordWrittenPresentationTime(bufferToWrite.presentationTimeStamp)
          timeCoordinator.driftTracker?.recordAudioTimestamp(bufferToWrite.presentationTimeStamp)
        }
      }
    }
  }

  @RecordingActor func processSystemAudioSample(_ sampleBuffer: CMSampleBuffer) {
    autoreleasepool {
      let shouldRouteSystemAudio = currentSource == .screen || pendingSource == .screen
      guard shouldRouteSystemAudio else { return }
      guard !isPaused, isRecording, let writer = videoWriter, writer.isWriting else { return }
      let needsInitialSessionStart = timeCoordinator.startTime == .zero

      if needsInitialSessionStart {
        let samplePresentationTime = CMSampleBufferGetPresentationTimeStamp(sampleBuffer)
        let result = timeCoordinator.processSampleTime(samplePresentationTime)
        if result.isFirstSample {
          videoWriter?.startSession(at: result.presentationTime)
        }
      }

      let bufferToWrite = timeCoordinator.adjustBufferTime(sampleBuffer)

      if needsInitialSessionStart {
        AppLogger.recording.info(
          "Recording started (System Audio first). First sample time: \(timeCoordinator.startTime.seconds)")
      }

      if timeCoordinator.startTime != .zero,
        bufferToWrite.presentationTimeStamp >= timeCoordinator.startTime {
        let didWrite = videoWriter?.writeSystemAudio(sampleBuffer: bufferToWrite) ?? false
        if didWrite {
          timeCoordinator.recordWrittenPresentationTime(bufferToWrite.presentationTimeStamp)
        }
        if didWrite, !isMicrophoneAudioEnabled {
          timeCoordinator.driftTracker?.recordAudioTimestamp(bufferToWrite.presentationTimeStamp)
        }
      }
    }
  }
}
