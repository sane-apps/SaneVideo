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
            onRecordingStateChanged?(isRecording)
        }
    }

    var isPaused = false
    var isPreparing = false // True during countdown (camera on, not yet recording)
    private(set) var isStopping = false // Prevents double-stop calls
    @MainActor private var isPendingStop = false // Handles a stop that arrives during start
    private var pendingStopCompletion: ((URL?) -> Void)? // Completion for a pending stop
    var isMicActive = true
    var isPresenterOverlayActive = false
    var recordingDuration: TimeInterval = 0
    var countdownValue: Int = 0 // 0 = no countdown, 3, 2, 1
    var shouldSkipCountdown: Bool = TestEnvironment.isUITesting

    // MARK: - Internal Properties

    private var recordingTimer: Timer?
    // nonisolated(unsafe) required for deinit access
    @ObservationIgnored private nonisolated(unsafe) var countdownTask: Task<Void, Never>?
    // Track the starting task to prevent race conditions during rapid start/stop
    @ObservationIgnored private nonisolated(unsafe) var startingTask: Task<Void, Never>?
    private(set) var recordingEngine: RecordingEngine?
    private var cameraService: CameraServiceProtocol
    private let permissionManager: PermissionManagerProtocol
    private var injectedAudioService: AudioService?
    private var injectedScreenRecorder: ScreenRecorder?
    private var cancellables = Set<AnyCancellable>()

    // MARK: - Initialization

    init(
        cameraService: CameraServiceProtocol? = nil,
        audioService: AudioService? = nil,
        screenRecorder: ScreenRecorder? = nil,
        permissionManager: PermissionManagerProtocol? = nil
    ) {
        self.cameraService = cameraService ?? ServiceContainer.shared.cameraService
        self.permissionManager = permissionManager ?? ServiceContainer.shared.permissionManager
        injectedAudioService = audioService
        injectedScreenRecorder = screenRecorder
        setupRecordingEngine()

        AppLogger.recording.info("✅ RecordingState initialized [VERSION_FIXED_V1]")
    }

    // Callbacks for AppState coordination
    var onRequestScreenShareStop: (() -> Void)?
    var onPresenterOverlayChanged: ((Bool) -> Void)?
    var onRecordingStateChanged: ((Bool) -> Void)?
    var onContentSelected: (() -> Void)?
    /// A take ended without the Stop button (capture error, low disk, failed switch): its file, if any.
    var onRecordingEndedUnexpectedly: ((URL?) -> Void)?

    // Task.cancel() is thread-safe, so we can call it from any thread in deinit
    deinit {
        countdownTask?.cancel()
        startingTask?.cancel()
    }

    private func setupRecordingEngine() {
        recordingEngine = RecordingEngine(
            cameraService: cameraService,
            audioService: injectedAudioService ?? ServiceContainer.shared.audioService,
            screenRecorder: injectedScreenRecorder
        )

        recordingEngine?.onScreenRecordingStoppedExternally = { [weak self] in
            Task { @MainActor in
                self?.onRequestScreenShareStop?()
            }
        }

        recordingEngine?.onStoppingAfterError = { [weak self] in
            Task { @MainActor in
                self?.engineIsEndingTake()
            }
        }

        recordingEngine?.onStoppedAfterError = { [weak self] url, error in
            Task { @MainActor in
                self?.handleEngineStoppedTake(url: url, error: error)
            }
        }

        recordingEngine?.onPausedBySystem = { [weak self] in
            Task { @MainActor in
                // Keep the controls and the clock in step with the engine; Resume then resumes it.
                if self?.isRecording == true {
                    self?.isPaused = true
                }
            }
        }

        recordingEngine?.onError = { [weak self] (error: AppError) in
            Task { @MainActor in
                AppLogger.recording.error("Engine reported error: \(error.localizedDescription)")

                // A take that has started is stopped like the Stop button, so its file is imported and the
                // windows come back. A start still in progress gets the quiet stop. Either way isRecording stays
                // set until stopRecording has stopped the engine: clearing it first left the engine recording.
                let handsOverTake = self.map {
                    $0.isRecording && !$0.isPreparing && !$0.isStopping && $0.startingTask == nil
                } ?? false

                // Source switch timeouts roll back to the previous source, so keep recording.
                let errorMessage = error.localizedDescription
                let isSourceSwitchTimeout = errorMessage.contains("Source switch timed out") ||
                    errorMessage.contains("switch timed out")

                if !isSourceSwitchTimeout {
                    if handsOverTake {
                        self?.stopRecording { [weak self] url in
                            Task { @MainActor [weak self] in self?.onRecordingEndedUnexpectedly?(url) }
                        }
                    } else {
                        self?.stopRecording { _ in }
                    }
                } else {
                    AppLogger.recording.warning("Source switch timeout - continuing recording on previous source")
                }

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
                        "🎤 Microphone permission requested.", type: .info
                    )
                    return
                case .cameraPermissionDenied, .cameraPermissionRestricted:
                    ServiceContainer.shared.hapticsManager.warning()
                    ServiceContainer.shared.soundManager.playError()
                    ServiceContainer.shared.toastManager.show(
                        "🎥 Camera disabled. Enable in Settings.", type: .error
                    )
                    self?.permissionManager.openSystemSettings()
                    return
                case .microphonePermissionDenied, .microphonePermissionRestricted:
                    ServiceContainer.shared.hapticsManager.warning()
                    ServiceContainer.shared.soundManager.playError()
                    ServiceContainer.shared.toastManager.show(
                        "🎤 Microphone disabled. Enable in Settings.", type: .error
                    )
                    self?.permissionManager.openMicrophoneSettings()
                    return
                default:
                    break
                }

                ServiceContainer.shared.hapticsManager.warning()
                ServiceContainer.shared.soundManager.playError()
                ServiceContainer.shared.errorPresenter.present(error)
            }
        }

        recordingEngine?.onPresenterOverlayChanged = { [weak self] (isActive: Bool) in
            Task { @MainActor [weak self] in
                AppLogger.recording.info("State: Presenter Overlay changed to \(isActive)")
                self?.isPresenterOverlayActive = isActive
                self?.onPresenterOverlayChanged?(isActive)
            }
        }

        recordingEngine?.onContentSelected = { [weak self] in
            Task { @MainActor [weak self] in
                AppLogger.recording.info("State: Content selected in picker")
                self?.onContentSelected?()
            }
        }
    }

    /// The engine started ending the take itself: Stop and quit wait for it instead of asking again.
    private func engineIsEndingTake() {
        guard isRecording, !isStopping else { return }
        isStopping = true
        recordingTimer?.invalidate()
        recordingTimer = nil
    }

    /// The engine ended the take itself and already finished the file: leave recording and hand it over.
    private func handleEngineStoppedTake(url: URL?, error: AppError) {
        AppLogger.recording.error("Engine stopped the take: \(error.localizedDescription)")
        // Only the engine's own stop gets the file, so hand it over even if a Stop that raced it already
        // reset the controls (that Stop got nothing from the engine).
        if isRecording || url != nil {
            recordingTimer?.invalidate()
            recordingTimer = nil
            countdownTask?.cancel()
            countdownTask = nil
            isPreparing = false
            isPaused = false
            isRecording = false
            isStopping = false
            onRecordingEndedUnexpectedly?(url)
        }
        ServiceContainer.shared.hapticsManager.warning()
        ServiceContainer.shared.soundManager.playError()
        ServiceContainer.shared.errorPresenter.present(error)
    }

    // MARK: - Recording Control

    @ObservationIgnored private var clockLastTick = Date()
    @ObservationIgnored private var clockElapsed: TimeInterval = 0

    private func tickRecordingClock() {
        let now = Date()
        defer { clockLastTick = now }
        guard !isPaused else { return }
        clockElapsed += now.timeIntervalSince(clockLastTick)
        let whole = clockElapsed.rounded(.down)
        if whole != recordingDuration {
            recordingDuration = whole
        }
    }

    func startRecording(isScreenSharing: Bool, includeCameraOverlay: Bool = true) {
        NSLog("🎬 RecordingState.startRecording called. isRecording=\(isRecording), isPreparing=\(isPreparing), isScreenSharing=\(isScreenSharing)")
        guard !isRecording, !isPreparing else {
            NSLog("🎬 RecordingState.startRecording BAILED: already recording or preparing")
            return
        }

        // Re-check live permission state; statuses can be stale .notDetermined after relaunch or a TCC refresh.
        permissionManager.checkCameraPermission()
        permissionManager.checkMicrophonePermission()
        if isScreenSharing {
            permissionManager.checkScreenRecordingPermission()
        }

        if needsInlinePermissionPrompt(
            isScreenSharing: isScreenSharing,
            includeCameraOverlay: includeCameraOverlay
        ) {
            isPreparing = true
            countdownValue = 0

            Task { @MainActor [weak self] in
                guard let self else { return }

                let granted = await self.requestPromptablePermissionsIfNeeded(
                    isScreenSharing: isScreenSharing,
                    includeCameraOverlay: includeCameraOverlay
                )
                guard self.isPreparing else { return }

                if granted {
                    self.beginRecordingIfPermissionsAvailable(
                        isScreenSharing: isScreenSharing,
                        includeCameraOverlay: includeCameraOverlay
                    )
                } else {
                    self.isPreparing = false
                    self.presentMissingPermissionFeedback(
                        isScreenSharing: isScreenSharing,
                        includeCameraOverlay: includeCameraOverlay
                    )
                }
            }
            return
        }

        beginRecordingIfPermissionsAvailable(
            isScreenSharing: isScreenSharing,
            includeCameraOverlay: includeCameraOverlay
        )
    }

    private func needsInlinePermissionPrompt(isScreenSharing: Bool, includeCameraOverlay: Bool) -> Bool {
        let requiresCamera = !isScreenSharing || includeCameraOverlay
        let requiresMicrophone = isMicActive
        return (requiresCamera && permissionManager.cameraStatus == .notDetermined)
            || (requiresMicrophone && permissionManager.microphoneStatus == .notDetermined)
    }

    private func requestPromptablePermissionsIfNeeded(
        isScreenSharing: Bool,
        includeCameraOverlay: Bool
    ) async -> Bool {
        let requiresCamera = !isScreenSharing || includeCameraOverlay
        let requiresMicrophone = isMicActive

        if requiresCamera, permissionManager.cameraStatus == .notDetermined {
            let cameraGranted = await permissionManager.requestCameraPermission()
            if !cameraGranted { return false }
        }

        if requiresMicrophone, permissionManager.microphoneStatus == .notDetermined {
            _ = await permissionManager.requestMicrophonePermission()
        }

        return true
    }

    /// A denied microphone never blocks a recording: record without sound and say so once.
    private func dropMicrophoneIfDenied() {
        guard isMicActive, permissionManager.microphoneStatus != .granted else { return }
        isMicActive = false
        ServiceContainer.shared.toastManager.show(
            "Recording without sound. Turn on Microphone for SaneVideo in System Settings to record your voice.",
            type: .info
        )
    }

    private func presentMissingPermissionFeedback(
        isScreenSharing: Bool,
        includeCameraOverlay: Bool
    ) {
        AppLogger.recording.error("❌ Cannot start recording: Missing required permissions")
        let requiresMicrophone = isMicActive
        let missing = if isScreenSharing && permissionManager.screenRecordingStatus != .granted {
            "Screen Recording"
        } else if (!isScreenSharing || includeCameraOverlay) && permissionManager.cameraStatus != .granted {
            "Camera"
        } else {
            "Microphone"
        }
        ServiceContainer.shared.toastManager.show(
            "SaneVideo needs \(missing) access. Turn it on in System Settings > Privacy & Security.",
            type: .error
        )

        if isScreenSharing && permissionManager.screenRecordingStatus != .granted {
            permissionManager.openScreenRecordingSettings()
        } else if !isScreenSharing || includeCameraOverlay, permissionManager.cameraStatus != .granted {
            permissionManager.openCameraSettings()
        } else if requiresMicrophone, permissionManager.microphoneStatus != .granted {
            permissionManager.openMicrophoneSettings()
        }
    }

    private func beginRecordingIfPermissionsAvailable(
        isScreenSharing: Bool,
        includeCameraOverlay: Bool
    ) {
        // Re-check permissions; they may have been revoked while the app was in the background.
        NSLog("🎬 Permission check: camera=\(permissionManager.cameraStatus), mic=\(permissionManager.microphoneStatus), screen=\(permissionManager.screenRecordingStatus)")

        // An active ScreenCaptureKit stream proves screen permission; CGPreflightScreenCaptureAccess() can return false even when granted.
        let hasActiveScreenStream = recordingEngine?.screenRecorder.activeStream != nil
        let shouldSkipScreenPermissionCheck = isScreenSharing && hasActiveScreenStream
        let requiresCamera = !isScreenSharing || includeCameraOverlay
        dropMicrophoneIfDenied()
        let requiresMicrophone = isMicActive

        if shouldSkipScreenPermissionCheck {
            NSLog("🎬 Screen permission check SKIPPED - active stream proves permission is granted")
        }

        let hasPermissions = permissionManager.verifyPermissionsForRecording(
            requiresCamera: requiresCamera,
            requiresMicrophone: requiresMicrophone,
            requiresScreenRecording: isScreenSharing && !shouldSkipScreenPermissionCheck
        )

        if !hasPermissions {
            NSLog("🎬 ❌ Permission check FAILED! Cannot start recording.")
            // After the inline permission prompt isPreparing is already true; left set, every later Record press bails.
            cancelCountdown()
            presentMissingPermissionFeedback(
                isScreenSharing: isScreenSharing,
                includeCameraOverlay: includeCameraOverlay
            )
            return
        }

        NSLog("🎬 ✅ Permission check PASSED")

        if let engine = recordingEngine {
            do { try engine.diskSpaceMonitor.verifyDiskSpace() } catch {
                NSLog("🎬 ❌ Disk space check FAILED")
                cancelCountdown()
                ServiceContainer.shared.errorPresenter.present(error)
                return
            }
        }
        NSLog("🎬 Setting isPreparing=true, calling startCountdown")
        isPreparing = true
        startCountdown(
            isScreenSharing: isScreenSharing,
            includeCameraOverlay: includeCameraOverlay
        )
    }

    private func startCountdown(isScreenSharing: Bool, includeCameraOverlay: Bool) {
        NSLog("🎬 RecordingState.startCountdown called. shouldSkipCountdown=\(shouldSkipCountdown)")
        if shouldSkipCountdown {
            countdownValue = 0
            actuallyStartRecording(
                isScreenSharing: isScreenSharing,
                includeCameraOverlay: includeCameraOverlay
            )
            return
        }

        countdownValue = 3
        NSLog("🎬 RecordingState: Countdown starting at 3...")
        countdownTask?.cancel()
        countdownTask = Task { @MainActor [weak self] in
            guard let self else { return }

            while self.countdownValue > 0 {
                NSLog("🎬 RecordingState: Countdown = \(self.countdownValue)")
                try? await Task.sleep(nanoseconds: 1_000_000_000)
                if Task.isCancelled { return }
                self.countdownValue -= 1
            }
            if Task.isCancelled { return }
            NSLog("🎬 RecordingState: Countdown complete!")
            self.countdownTask = nil
            self.actuallyStartRecording(
                isScreenSharing: isScreenSharing,
                includeCameraOverlay: includeCameraOverlay
            )
        }
    }

    private func cancelCountdown() {
        isPreparing = false
        countdownTask?.cancel()
        countdownTask = nil
        countdownValue = 0
    }

    private func actuallyStartRecording(isScreenSharing: Bool, includeCameraOverlay: Bool) {
        NSLog("🎬 RecordingState.actuallyStartRecording called! isScreenSharing=\(isScreenSharing)")
        // isPreparing is expected to be true here; only isRecording matters.
        guard !isRecording else {
            NSLog("🎬 RecordingState.actuallyStartRecording BAILED: already recording")
            AppLogger.recording.warning("actuallyStartRecording called but already recording")
            return
        }

        isPreparing = false
        isPaused = false
        recordingDuration = 0

        // Measure real elapsed time (minus pauses) and publish only whole seconds, so the
        // controls redraw once a second and the clock does not drift with timer coalescing.
        clockLastTick = Date()
        clockElapsed = 0
        recordingTimer = Timer.scheduledTimer(withTimeInterval: 0.25, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.tickRecordingClock() }
        }

        let initialSource: RecordingSource = isScreenSharing ? .screen : .camera
        let includeMicrophoneAudio = isMicActive
        isRecording = true // Set optimistically but handle failure

        let recordingEngine = recordingEngine
        startingTask = Task { [weak self, recordingEngine] in
            guard self != nil else { return }

            await recordingEngine?.startRecording(
                initialSource: initialSource,
                includeCameraOverlay: includeCameraOverlay,
                includeMicrophoneAudio: includeMicrophoneAudio
            )

            // The engine sets isRecording; if start failed, clean up the timer.
            await MainActor.run { [weak self] in
                guard let self = self else { return }

                self.startingTask = nil

                ServiceContainer.shared.soundManager.playStartRecording()
                ServiceContainer.shared.hapticsManager.success()

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

        if startingTask != nil {
            AppLogger.recording.warning(
                "🎬 User hit stop while recording was still starting. Queueing stop... [VERSION_FIXED_V1]")
            isPendingStop = true

            // Last writer wins: a newer pending completion replaces the old one.
            pendingStopCompletion = completion
            return
        }

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

        // Set at once to block concurrent calls.
        isStopping = true

        isPreparing = false
        isPaused = false

        recordingTimer?.invalidate()
        recordingTimer = nil
        countdownTask?.cancel()
        countdownTask = nil

        ServiceContainer.shared.soundManager.playStopRecording()
        ServiceContainer.shared.hapticsManager.impact()

        // Stop the engine first, then update state when it finishes.
        Task {
            AppLogger.recording.debug("🛑 Calling engine.stopRecording()")
            let url = await recordingEngine?.stopRecording()
            AppLogger.recording.debug("🛑 Engine returned url=\(url?.path ?? "nil")")

            await MainActor.run {
                self.isRecording = false
                self.isStopping = false
                completion(url)
            }
        }
    }

    func togglePause(isScreenSharing _: Bool) {
        guard isRecording else { return }
        isPaused.toggle()
        if isPaused {
            recordingEngine?.pause()
        } else {
            recordingEngine?.resume()
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
