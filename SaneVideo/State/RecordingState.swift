//
//  RecordingState.swift
//  SaneVideo
//

import AVFoundation
import Combine
import SwiftUI

@MainActor
@Observable
class RecordingState {
  // MARK: - Published Properties

  var isRecording = false {
    didSet {
      guard isRecording != oldValue else { return }
      NSLog("🎬 RecordingState: isRecording changed from \(oldValue) to \(isRecording)")
      NotificationCenter.default.post(
        name: NSNotification.Name("RecordingStateChanged"),
        object: nil,
        userInfo: ["isRecording": isRecording]
      )
      onRecordingStateChanged?(isRecording)
    }
  }
  var isPaused = false
  var isPreparing = false  // True during countdown (camera on, not yet recording)
  private var isStopping = false  // CRITICAL FIX: Prevent double-stop calls
  @MainActor private var isPendingStop = false // CRITICAL FIX: Handle stop during initialization
  private var pendingStopCompletion: ((URL?) -> Void)? // CRITICAL FIX: Hold completion for pending stops
  var isMicActive = true
  var isPresenterOverlayActive = false
  var recordingDuration: TimeInterval = 0
  var countdownValue: Int = 0  // 0 = no countdown, 3, 2, 1
  var shouldSkipCountdown: Bool = TestEnvironment.isUITesting

  // MARK: - Internal Properties

  private var recordingTimer: Timer?
  // nonisolated(unsafe) required for deinit access
  @ObservationIgnored nonisolated(unsafe) private var countdownTask: Task<Void, Never>?
  // CRITICAL FIX: Track the starting task to prevent race conditions during rapid start/stop
  @ObservationIgnored nonisolated(unsafe) private var startingTask: Task<Void, Never>?
  private var recordingEngine: RecordingEngine?
  private var cameraService: CameraServiceProtocol
  private var injectedAudioService: AudioService?
  private var injectedScreenRecorder: ScreenRecorder?  // Stored for injection
  private var cancellables = Set<AnyCancellable>()

  // MARK: - Initialization

  init(
    cameraService: CameraServiceProtocol? = nil,
    audioService: AudioService? = nil,
    screenRecorder: ScreenRecorder? = nil
  ) {
    self.cameraService = cameraService ?? ServiceContainer.shared.cameraService
    self.injectedAudioService = audioService
    self.injectedScreenRecorder = screenRecorder
    setupRecordingEngine()

    // VERIFICATION LOG: Confirm this code is running
    AppLogger.recording.info("✅ RecordingState initialized [VERSION_FIXED_V1]")
  }

  // Callbacks for AppState coordination
  var onRequestScreenShareStop: (() -> Void)?
  var onPresenterOverlayChanged: ((Bool) -> Void)?
  var onRecordingStateChanged: ((Bool) -> Void)?
  var onContentSelected: (() -> Void)?

  // CRITICAL FIX: Ensure proper cleanup of timer and tasks
  // Task.cancel() is thread-safe, so we can call it from any thread in deinit
  deinit {
    countdownTask?.cancel()
  }

  private func setupRecordingEngine() {
    recordingEngine = RecordingEngine(
      cameraService: cameraService,
      audioService: injectedAudioService ?? ServiceContainer.shared.audioService,
      screenRecorder: injectedScreenRecorder  // Use injected instance if available
    )

    // Listen for external screen recording stops
    recordingEngine?.onScreenRecordingStoppedExternally = { [weak self] in
      Task { @MainActor in
        self?.onRequestScreenShareStop?()
      }
    }

    // CRITICAL FIX: Wire error handler to stop recording and present errors
    recordingEngine?.onError = { [weak self] (error: AppError) in
      Task { @MainActor in
        AppLogger.recording.error("Engine reported error: \(error.localizedDescription)")

        // CRITICAL: Cleanup timer if recording failed to start
        if let self = self, self.isPreparing || (self.isRecording && self.recordingDuration < 0.5) {
          // Recording just started or was preparing - cleanup timer
          self.recordingTimer?.invalidate()
          self.recordingTimer = nil
          self.isPreparing = false
          self.isRecording = false
        }

        // CRITICAL FIX: Don't stop recording for source switch timeouts
        // The switch will rollback, but recording should continue on the previous source
        let errorMessage = error.localizedDescription
        let isSourceSwitchTimeout = errorMessage.contains("Source switch timed out") ||
                                     errorMessage.contains("switch timed out")

        if !isSourceSwitchTimeout {
          // Stop recording for all other errors
          self?.stopRecording { _ in }
        } else {
          // For source switch timeouts, just show error but keep recording
          AppLogger.recording.warning("Source switch timeout - continuing recording on previous source")
        }

        // Switch directly on the strongly-typed AppError
        switch error {
        case .cameraPermissionPromptShown:
          ServiceContainer.shared.hapticsManager.warning()
          ServiceContainer.shared.soundManager.playError()
          ServiceContainer.shared.toastManager.show("🎥 Camera permission requested.", type: .info)
          return
        case .microphonePermissionPromptShown:
          ServiceContainer.shared.hapticsManager.warning()
          ServiceContainer.shared.soundManager.playError()
          ServiceContainer.shared.toastManager.show(
            "🎤 Microphone permission requested.", type: .info)
          return
        case .cameraPermissionDenied, .cameraPermissionRestricted:
          ServiceContainer.shared.hapticsManager.warning()
          ServiceContainer.shared.soundManager.playError()
          ServiceContainer.shared.toastManager.show(
            "🎥 Camera disabled. Enable in Settings.", type: .error)
          ServiceContainer.shared.permissionManager.openSystemSettings()
          return
        case .microphonePermissionDenied, .microphonePermissionRestricted:
          ServiceContainer.shared.hapticsManager.warning()
          ServiceContainer.shared.soundManager.playError()
          ServiceContainer.shared.toastManager.show(
            "🎤 Microphone disabled. Enable in Settings.", type: .error)
          ServiceContainer.shared.permissionManager.openSystemSettings()
          return
        default:
          break
        }

        ServiceContainer.shared.hapticsManager.warning()
        ServiceContainer.shared.soundManager.playError()
        ServiceContainer.shared.errorPresenter.present(error)
      }
    }

    // Listen for Presenter Overlay changes
    recordingEngine?.onPresenterOverlayChanged = { [weak self] (isActive: Bool) in
      Task { @MainActor [weak self] in
        AppLogger.recording.info("State: Presenter Overlay changed to \(isActive)")
        self?.isPresenterOverlayActive = isActive
        self?.onPresenterOverlayChanged?(isActive)
      }
    }

    // Listen for content selection (user picked something in picker)
    recordingEngine?.onContentSelected = { [weak self] in
      Task { @MainActor [weak self] in
        AppLogger.recording.info("State: Content selected in picker")
        self?.onContentSelected?()
      }
    }
  }

  // MARK: - Recording Control

  func startRecording(isScreenSharing: Bool) {
    NSLog("🎬 RecordingState.startRecording called. isRecording=\(isRecording), isPreparing=\(isPreparing), isScreenSharing=\(isScreenSharing)")
    guard !isRecording, !isPreparing else {
      NSLog("🎬 RecordingState.startRecording BAILED: already recording or preparing")
      return
    }

    // CRITICAL FIX: Verify permissions before starting recording
    // This handles cases where permissions were revoked while app was in background
    let permissionManager = ServiceContainer.shared.permissionManager
    NSLog("🎬 Permission check: camera=\(permissionManager.cameraStatus), mic=\(permissionManager.microphoneStatus), screen=\(permissionManager.screenRecordingStatus)")

    let hasPermissions = permissionManager.verifyPermissionsForRecording(
      requiresCamera: !isScreenSharing, // Camera not needed for screen sharing
      requiresMicrophone: true,
      requiresScreenRecording: isScreenSharing
    )

    if !hasPermissions {
      NSLog("🎬 ❌ Permission check FAILED! Cannot start recording.")
      AppLogger.recording.error("❌ Cannot start recording: Missing required permissions")
      ServiceContainer.shared.toastManager.show("Missing required permissions. Please check Settings.", type: .error)
      // Open appropriate settings based on what's missing
      if isScreenSharing && permissionManager.screenRecordingStatus != .granted {
        permissionManager.openScreenRecordingSettings()
      } else if !isScreenSharing && permissionManager.cameraStatus != .granted {
        permissionManager.openSystemSettings()
      } else if permissionManager.microphoneStatus != .granted {
        permissionManager.openSystemSettings()
      }
      return
    }

    NSLog("🎬 ✅ Permission check PASSED")

    if let engine = recordingEngine {
      do { try engine.diskSpaceMonitor.verifyDiskSpace() } catch {
        NSLog("🎬 ❌ Disk space check FAILED")
        ServiceContainer.shared.errorPresenter.present(error)
        return
      }
    }
    NSLog("🎬 Setting isPreparing=true, calling startCountdown")
    isPreparing = true
    startCountdown(isScreenSharing: isScreenSharing)
  }

  private func startCountdown(isScreenSharing: Bool) {
    NSLog("🎬 RecordingState.startCountdown called. shouldSkipCountdown=\(shouldSkipCountdown)")
    if shouldSkipCountdown {
      countdownValue = 0
      self.actuallyStartRecording(isScreenSharing: isScreenSharing)
      return
    }

    countdownValue = 3
    NSLog("🎬 RecordingState: Countdown starting at 3...")
    countdownTask?.cancel()
    countdownTask = Task { @MainActor in
      while countdownValue > 0 {
        NSLog("🎬 RecordingState: Countdown = \(self.countdownValue)")
        try? await Task.sleep(nanoseconds: 1_000_000_000)
        if Task.isCancelled { return }
        countdownValue -= 1
      }
      if Task.isCancelled { return }
      NSLog("🎬 RecordingState: Countdown complete!")
      self.countdownTask = nil
      self.actuallyStartRecording(isScreenSharing: isScreenSharing)
    }
  }

  private func cancelCountdown() {
    isPreparing = false
    countdownTask?.cancel()
    countdownTask = nil
    countdownValue = 0
  }

  private func actuallyStartRecording(isScreenSharing: Bool) {
    NSLog("🎬 RecordingState.actuallyStartRecording called! isScreenSharing=\(isScreenSharing)")
    // CRITICAL: Only check isRecording - we ARE expected to have isPreparing=true here
    // isPreparing will be set to false below
    guard !isRecording else {
      NSLog("🎬 RecordingState.actuallyStartRecording BAILED: already recording")
      AppLogger.recording.warning("actuallyStartRecording called but already recording")
      return
    }

    isPreparing = false
    isPaused = false
    recordingDuration = 0

    // CRITICAL: Create timer but don't set isRecording until engine confirms start
    recordingTimer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] _ in
      guard let self else { return }
      Task { @MainActor in
        guard !self.isPaused else { return }
        self.recordingDuration += 0.1
      }
    }

    let initialSource: RecordingSource = isScreenSharing ? .screen : .camera
    self.isRecording = true // Set optimistically but handle failure

    // CRITICAL: Start engine and only set isRecording if it succeeds
    startingTask = Task {
      await recordingEngine?.startRecording(initialSource: initialSource)

      // CRITICAL: Check if engine actually started (isRecording will be set by engine)
      // If start failed, cleanup timer
      // CRITICAL: Check if engine actually started (isRecording will be set by engine)
      // If start failed, cleanup timer
      await MainActor.run { [weak self] in
        guard let self = self else { return }

        // Always clear the task when done
        self.startingTask = nil

        // Start success feedback
        ServiceContainer.shared.soundManager.playStartRecording()
        ServiceContainer.shared.hapticsManager.success()

   // CRITICAL FIX: If a stop was requested during start, execute it now
        if self.isPendingStop {
          AppLogger.recording.info("🎬 Initialized stop request detected. Stopping now.")
          self.isPendingStop = false
          self.stopRecording { url in
            Task { @MainActor in
                self.pendingStopCompletion?(url)
                self.pendingStopCompletion = nil
            }
          }
        }
      }
    }
  }

  func stopRecording(completion: @escaping @Sendable (URL?) -> Void) {
    AppLogger.recording.debug(
      "🛑 stopRecording called. isPreparing=\(isPreparing), isRecording=\(isRecording), isStopping=\(isStopping)")

    // CRITICAL FIX: If we are still starting, we must wait or cancel
    if startingTask != nil {
      AppLogger.recording.warning(
        "🎬 User hit stop while recording was still starting. Queueing stop... [VERSION_FIXED_V1]")
      isPendingStop = true

      // CRITICAL: Queue the completion handler to be called when the pending stop executes
      // We overwrite any previous pending completion - last writer wins
      self.pendingStopCompletion = completion
      return
    }

    // CRITICAL FIX: Prevent double-stop calls
    guard !isStopping else {
      AppLogger.recording.debug("🛑 stopRecording ignored (already stopping)")
      completion(nil) // Call completion even if ignored, to unblock caller
      return
    }

    if isPreparing {
      AppLogger.recording.debug("🛑 stopRecording cancelled (isPreparing=true)")
      cancelCountdown()
      completion(nil)
      return
    }
    guard isRecording else {
      AppLogger.recording.debug("🛑 stopRecording ignored (isRecording=false)")
      completion(nil)
      return
    }

    // CRITICAL FIX: Set stopping flag IMMEDIATELY to prevent concurrent calls
    isStopping = true

    // Clear other state flags
    isPreparing = false
    isPaused = false

    // Stop timer immediately (we don't want duration to keep counting)
    recordingTimer?.invalidate()
    recordingTimer = nil
    countdownTask?.cancel()
    countdownTask = nil

    // Play feedback immediately
    ServiceContainer.shared.soundManager.playStopRecording()
    ServiceContainer.shared.hapticsManager.impact()

    // CRITICAL FIX: Stop engine FIRST, then update state in completion
    Task {
      AppLogger.recording.debug("🛑 Calling engine.stopRecording()")
      let url = await recordingEngine?.stopRecording()
      AppLogger.recording.debug("🛑 Engine returned url=\(url?.path ?? "nil")")

      // CRITICAL: Only update state AFTER engine completes
      await MainActor.run {
        self.isRecording = false
        self.isStopping = false
        completion(url)
      }
    }
  }

  func togglePause(isScreenSharing: Bool) {
    guard isRecording else { return }
    isPaused.toggle()
    if isPaused {
      recordingEngine?.pause()
    } else {
      recordingEngine?.resume()
      // CRITICAL FIX: Removed unnecessary switchSource call on resume
      // Resume should just resume, not switch sources
      // The source should already be correct from when recording started
      // If this was needed for some reason, it should only switch if source is wrong
      // For now, removing it as it seems like a bug
    }
  }

  func toggleMic() {
    isMicActive.toggle()
    recordingEngine?.setMuted(!isMicActive)
  }

  func switchSource(_ source: RecordingSource) {
    recordingEngine?.switchSource(source: source)
  }

  var screenPreviewLayer: AVSampleBufferDisplayLayer? { recordingEngine?.screenPreviewLayer }
  var engine: RecordingEngine? { recordingEngine }
}
