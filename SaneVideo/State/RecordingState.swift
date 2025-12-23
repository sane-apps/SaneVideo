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
      NotificationCenter.default.post(
        name: NSNotification.Name("RecordingStateChanged"),
        object: nil,
        userInfo: ["isRecording": isRecording]
      )
    }
  }
  var isPaused = false
  var isPreparing = false  // True during countdown (camera on, not yet recording)
  var isMicActive = true
  var isPresenterOverlayActive = false
  var recordingDuration: TimeInterval = 0
  var countdownValue: Int = 0  // 0 = no countdown, 3, 2, 1
  var shouldSkipCountdown: Bool = TestEnvironment.isUITesting

  // MARK: - Internal Properties

  private var recordingTimer: Timer?
  private var countdownTask: Task<Void, Never>?  // Store countdown timer so it can be cancelled
  private var recordingEngine: RecordingEngine?
  private var cameraService: CameraServiceProtocol
  private var injectedAudioService: AudioService?
  private var cancellables = Set<AnyCancellable>()

  // MARK: - Initialization

  init(cameraService: CameraServiceProtocol? = nil, audioService: AudioService? = nil) {
    self.cameraService = cameraService ?? ServiceContainer.shared.cameraService
    self.injectedAudioService = audioService
    setupRecordingEngine()
  }

  // Callbacks for AppState coordination
  var onRequestScreenShareStop: (() -> Void)?
  var onPresenterOverlayChanged: ((Bool) -> Void)?

  // CRITICAL FIX: Ensure proper cleanup of timer and tasks
  nonisolated deinit {
    // Note: Can't access actor-isolated properties in nonisolated deinit
  }

  private func setupRecordingEngine() {
    recordingEngine = RecordingEngine(
      cameraService: cameraService,
      audioService: injectedAudioService ?? ServiceContainer.shared.audioService
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

        // Stop recording cleanup
        self?.stopRecording { _ in }

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
  }

  // MARK: - Recording Control

  func startRecording(isScreenSharing: Bool) {
    guard !isRecording, !isPreparing else { return }
    if let engine = recordingEngine {
      do { try engine.diskSpaceMonitor.verifyDiskSpace() } catch {
        ServiceContainer.shared.errorPresenter.present(error)
        return
      }
    }
    isPreparing = true
    startCountdown(isScreenSharing: isScreenSharing)
  }

  private func startCountdown(isScreenSharing: Bool) {
    if shouldSkipCountdown {
      countdownValue = 0
      self.actuallyStartRecording(isScreenSharing: isScreenSharing)
      return
    }

    countdownValue = 3
    countdownTask?.cancel()
    countdownTask = Task { @MainActor in
      while countdownValue > 0 {
        try? await Task.sleep(nanoseconds: 1_000_000_000)
        if Task.isCancelled { return }
        countdownValue -= 1
      }
      if Task.isCancelled { return }
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
    isPreparing = false
    isRecording = true
    isPaused = false
    recordingDuration = 0

    recordingTimer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] _ in
      guard let self else { return }
      Task { @MainActor in
        guard !self.isPaused else { return }
        self.recordingDuration += 0.1
      }
    }

    let initialSource: RecordingSource = isScreenSharing ? .screen : .camera
    Task { await recordingEngine?.startRecording(initialSource: initialSource) }

    ServiceContainer.shared.soundManager.playStartRecording()
    ServiceContainer.shared.hapticsManager.success()
  }

  func stopRecording(completion: @escaping @Sendable (URL?) -> Void) {
    print("🕵️‍♀️ RecordingState: stopRecording called!")
    for symbol in Thread.callStackSymbols.prefix(10) { print("  \(symbol)") }

    print(
      "🛑 [DEBUG] State: stopRecording called. isPreparing=\(isPreparing), isRecording=\(isRecording)"
    )

    if isPreparing {
      print("🛑 [DEBUG] State: stopRecording cancelled (isPreparing=true)")
      cancelCountdown()
      completion(nil)
      return
    }
    guard isRecording else {
      print("🛑 [DEBUG] State: stopRecording ignored (isRecording=false)")
      completion(nil)
      return
    }
    isRecording = false
    isPreparing = false
    isPaused = false
    recordingTimer?.invalidate()
    recordingTimer = nil
    countdownTask?.cancel()
    countdownTask = nil

    ServiceContainer.shared.soundManager.playStopRecording()
    ServiceContainer.shared.hapticsManager.impact()

    Task {
      print("🛑 [DEBUG] State: calling engine.stopRecording()")
      let url = await recordingEngine?.stopRecording()
      print("🛑 [DEBUG] State: engine returned url=\(url?.path ?? "nil")")
      await MainActor.run { completion(url) }
    }
  }

  func togglePause(isScreenSharing: Bool) {
    guard isRecording else { return }
    isPaused.toggle()
    if isPaused {
      recordingEngine?.pause()
    } else {
      recordingEngine?.resume()
      let source: RecordingSource = isScreenSharing ? .screen : .camera
      recordingEngine?.switchSource(source: source)
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
