import AVFoundation
import Combine
import CoreGraphics
import ScreenCaptureKit

enum PermissionStatus {
    case unknown
    case notDetermined
    case granted
    case denied
    case restricted
}

@MainActor
@Observable
class PermissionManager: PermissionManagerProtocol {
    // MARK: - Status

    var cameraStatus: PermissionStatus = .notDetermined {
        didSet {
            _cameraStatusSubject.send(cameraStatus)
            notifyPermissionStatusChanged()
        }
    }

    var microphoneStatus: PermissionStatus = .notDetermined {
        didSet {
            _microphoneStatusSubject.send(microphoneStatus)
            notifyPermissionStatusChanged()
        }
    }

    var screenRecordingStatus: PermissionStatus = .notDetermined {
        didSet {
            _screenRecordingStatusSubject.send(screenRecordingStatus)
            notifyPermissionStatusChanged()
        }
    }

    // Distinguishes .notDetermined from .denied.
    @ObservationIgnored private var screenRecordingWasRequested = false

    // MARK: - Combine Bridge

    // These allow legacy services to subscribe to status changes

    @ObservationIgnored private let _cameraStatusSubject = CurrentValueSubject<
        PermissionStatus, Never
    >(.notDetermined)
    @ObservationIgnored private let _microphoneStatusSubject = CurrentValueSubject<
        PermissionStatus, Never
    >(.notDetermined)
    @ObservationIgnored private let _screenRecordingStatusSubject = CurrentValueSubject<
        PermissionStatus, Never
    >(.notDetermined)

    var cameraStatusPublisher: AnyPublisher<PermissionStatus, Never> {
        _cameraStatusSubject.eraseToAnyPublisher()
    }

    var microphoneStatusPublisher: AnyPublisher<PermissionStatus, Never> {
        _microphoneStatusSubject.eraseToAnyPublisher()
    }

    var screenRecordingStatusPublisher: AnyPublisher<PermissionStatus, Never> {
        _screenRecordingStatusSubject.eraseToAnyPublisher()
    }

    // MARK: - Initialization

    init() {
        if TestEnvironment.isTesting {
            cameraStatus = .granted
            microphoneStatus = .granted
            screenRecordingStatus = .granted
            AppLogger.general.info("🧪 [UI TEST] PermissionManager: Pre-granting all permissions")
            return
        }
        checkAllPermissions()
        setupLifecycleObserver()
    }

    func checkAllPermissions() {
        if TestEnvironment.isTesting { return }
        checkCameraPermission()
        checkMicrophonePermission()
        checkScreenRecordingPermission()
    }

    // MARK: - Camera

    func checkCameraPermission() {
        if TestEnvironment.isTesting {
            cameraStatus = .granted
            return
        }
        let status = AVCaptureDevice.authorizationStatus(for: .video)
        cameraStatus = mapAVStatus(status)
    }

    func requestCameraPermission() async -> Bool {
        if TestEnvironment.isTesting {
            cameraStatus = .granted
            return true
        }
        if TestEnvironment.suppressPermissionPrompts {
            checkCameraPermission()
            return cameraStatus == .granted
        }
        AppLogger.camera.info("Requesting camera permission...")
        let granted = await AVCaptureDevice.requestAccess(for: .video)
        AppLogger.camera.info("Camera permission result: \(granted)")
        checkCameraPermission()
        return granted
    }

    // MARK: - Microphone

    func checkMicrophonePermission() {
        if TestEnvironment.isTesting {
            microphoneStatus = .granted
            return
        }
        let status = AVCaptureDevice.authorizationStatus(for: .audio)
        microphoneStatus = mapAVStatus(status)
    }

    func requestMicrophonePermission() async -> Bool {
        if TestEnvironment.isTesting {
            microphoneStatus = .granted
            return true
        }
        if TestEnvironment.suppressPermissionPrompts {
            checkMicrophonePermission()
            return microphoneStatus == .granted
        }
        AppLogger.audio.info("Requesting microphone permission...")
        let granted = await AVCaptureDevice.requestAccess(for: .audio)
        AppLogger.audio.info("Microphone permission result: \(granted)")
        checkMicrophonePermission()
        return granted
    }

    // MARK: - Screen Recording

    func checkScreenRecordingPermission() {
        if TestEnvironment.isTesting {
            screenRecordingStatus = .granted
            return
        }

        // CGPreflightScreenCaptureAccess() can return false after a grant until the app restarts, so check several signals.

        if CGPreflightScreenCaptureAccess() {
            screenRecordingStatus = .granted
            UserDefaults.standard.set(true, forKey: "screenRecordingEverGranted")
            return
        }

        // Requested before but preflight is false: denied or stale.
        let wasRequested = UserDefaults.standard.bool(forKey: "screenRecordingWasRequested")
        screenRecordingStatus = wasRequested ? .denied : .notDetermined
    }

    func requestScreenRecordingPermission() {
        if TestEnvironment.isTesting {
            screenRecordingStatus = .granted
            return
        }
        if TestEnvironment.suppressPermissionPrompts {
            checkScreenRecordingPermission()
            return
        }

        if screenRecordingStatus == .granted {
            AppLogger.general.info("📺 Screen recording permission already granted, skipping request")
            return
        }

        UserDefaults.standard.set(true, forKey: "screenRecordingWasRequested")

        AppLogger.general.info("📺 Requesting screen recording permission...")
        AppLogger.general.warning("⚠️ Note: If permission is granted, the app must be restarted for it to take effect.")

        // Returns immediately; a grant takes effect only after the app restarts.
        CGRequestScreenCaptureAccess()

        Task { @MainActor in
            ServiceContainer.shared.toastManager.show(
                "Screen recording permission requested. If granted, please restart the app for it to take effect.",
                type: .info
            )
        }

        // The request can't be awaited, so re-check now.
        checkScreenRecordingPermission()
    }

    // MARK: - Request All Permissions

    func requestAllPermissions() async -> [String: Bool] {
        if TestEnvironment.isTesting {
            return ["camera": true, "microphone": true, "screenRecording": true]
        }
        if TestEnvironment.suppressPermissionPrompts {
            checkAllPermissions()
            return [
                "camera": cameraStatus == .granted,
                "microphone": microphoneStatus == .granted,
                "screenRecording": screenRecordingStatus == .granted,
            ]
        }
        AppLogger.general.info("Starting batch permission request...")
        let camera = await requestCameraPermission()
        let microphone = await requestMicrophonePermission()

        AppLogger.general.info("Requesting screen recording permission...")
        requestScreenRecordingPermission()

        let results = [
            "camera": camera,
            "microphone": microphone,
            "screenRecording": screenRecordingStatus == .granted,
        ]
        AppLogger.general.info("Batch permission request completed: \(results)")
        return results
    }

    // MARK: - Helpers

    private func mapAVStatus(_ status: AVAuthorizationStatus) -> PermissionStatus {
        switch status {
        case .authorized: return .granted
        case .denied: return .denied
        case .restricted: return .restricted
        case .notDetermined: return .notDetermined
        @unknown default:
            AppLogger.general.warning("⚠️ Unknown AVAuthorizationStatus: \(status.rawValue)")
            return .unknown
        }
    }

    // MARK: - Settings

    func openSystemSettings() {
        openCameraSettings()
    }

    func openCameraSettings() {
        guard let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Camera") else { return }
        NSWorkspace.shared.open(url)
    }

    func openMicrophoneSettings() {
        guard let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Microphone") else { return }
        NSWorkspace.shared.open(url)
    }

    func openScreenRecordingSettings() {
        guard let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture") else { return }
        NSWorkspace.shared.open(url)
    }

    // MARK: - Lifecycle

    func setupLifecycleObserver() {
        if TestEnvironment.isTesting { return }

        // Re-check on activation to catch permissions revoked in System Settings.
        NotificationCenter.default.addObserver(
            forName: NSApplication.didBecomeActiveNotification, object: nil, queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                AppLogger.general.info("🔄 App became active, re-checking permissions...")
                self?.checkAllPermissions()
            }
        }
    }

    // MARK: - Permission Verification

    /// Re-checks permissions (they may have been revoked) and returns true if all required ones are granted.
    func verifyPermissionsForRecording(requiresCamera: Bool = true, requiresMicrophone: Bool = true, requiresScreenRecording: Bool = false) -> Bool {
        if TestEnvironment.isTesting { return true }

        checkCameraPermission()
        checkMicrophonePermission()
        if requiresScreenRecording {
            checkScreenRecordingPermission()
        }

        if requiresCamera && !Self.allowsRecordingStart(for: cameraStatus, canPromptInline: true) {
            AppLogger.general.warning("⚠️ Camera permission not granted: \(cameraStatus)")
            return false
        }

        if requiresMicrophone && !Self.allowsRecordingStart(for: microphoneStatus, canPromptInline: true) {
            AppLogger.general.warning("⚠️ Microphone permission not granted: \(microphoneStatus)")
            return false
        }

        if requiresScreenRecording && !Self.allowsRecordingStart(for: screenRecordingStatus, canPromptInline: false) {
            AppLogger.general.warning("⚠️ Screen recording permission not granted: \(screenRecordingStatus)")
            return false
        }

        return true
    }

    /// Camera and microphone can prompt inline on first use, so `.notDetermined`
    /// should not block recording startup. Screen recording still blocks because
    /// macOS requires the user to grant it outside the capture start flow.
    static func allowsRecordingStart(
        for status: PermissionStatus,
        canPromptInline: Bool
    ) -> Bool {
        switch status {
        case .granted:
            return true
        case .notDetermined:
            return canPromptInline
        case .denied, .restricted, .unknown:
            return false
        }
    }

    // MARK: - Permission Status Synchronization

    private func notifyPermissionStatusChanged() {
        // Combine subscribers already see the change; this notification is for services that do not use Combine.
        NotificationCenter.default.post(
            name: .permissionStatusChanged,
            object: nil,
            userInfo: [
                "camera": cameraStatus,
                "microphone": microphoneStatus,
                "screenRecording": screenRecordingStatus,
            ]
        )
    }
}

// MARK: - Notification Names

extension Notification.Name {
    static let permissionStatusChanged = Notification.Name("permissionStatusChanged")
}
