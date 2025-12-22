//
//  PermissionManager.swift
//  SaneVideo
//
//  Created by SaneVideo Refactor
//

import AVFoundation
import Combine
import CoreGraphics
import ScreenCaptureKit

// Permission status enum (previously in CameraTypes.swift)
enum PermissionStatus {
    case unknown
    case notDetermined
    case granted
    case denied
    case restricted
}

@MainActor
@Observable
class PermissionManager {
    // MARK: - Status

    var cameraStatus: PermissionStatus = .notDetermined {
        didSet { _cameraStatusSubject.send(cameraStatus) }
    }
    var microphoneStatus: PermissionStatus = .notDetermined {
        didSet { _microphoneStatusSubject.send(microphoneStatus) }
    }
    var screenRecordingStatus: PermissionStatus = .notDetermined {
        didSet { _screenRecordingStatusSubject.send(screenRecordingStatus) }
    }

    // MARK: - Combine Bridge
    // These allow legacy services to subscribe to status changes

    @ObservationIgnored private let _cameraStatusSubject = CurrentValueSubject<PermissionStatus, Never>(.notDetermined)
    @ObservationIgnored private let _microphoneStatusSubject = CurrentValueSubject<PermissionStatus, Never>(.notDetermined)
    @ObservationIgnored private let _screenRecordingStatusSubject = CurrentValueSubject<PermissionStatus, Never>(.notDetermined)

    var cameraStatusPublisher: AnyPublisher<PermissionStatus, Never> { _cameraStatusSubject.eraseToAnyPublisher() }
    var microphoneStatusPublisher: AnyPublisher<PermissionStatus, Never> { _microphoneStatusSubject.eraseToAnyPublisher() }
    var screenRecordingStatusPublisher: AnyPublisher<PermissionStatus, Never> { _screenRecordingStatusSubject.eraseToAnyPublisher() }

    // MARK: - Initialization

    init() {
        if TestEnvironment.isUITesting {
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
        if TestEnvironment.isUITesting { return }
        checkCameraPermission()
        checkMicrophonePermission()
        checkScreenRecordingPermission()
    }

    // MARK: - Camera

    func checkCameraPermission() {
        let isTesting = ProcessInfo.processInfo.arguments.contains("-uitesting")
        if isTesting {
            cameraStatus = .granted
            return
        }
        let status = AVCaptureDevice.authorizationStatus(for: .video)
        cameraStatus = mapAVStatus(status)
    }

    func requestCameraPermission() async -> Bool {
        let isTesting = ProcessInfo.processInfo.arguments.contains("-uitesting")
        if isTesting { 
            cameraStatus = .granted
            return true 
        }
        AppLogger.camera.info("Requesting camera permission...")
        let granted = await AVCaptureDevice.requestAccess(for: .video)
        AppLogger.camera.info("Camera permission result: \(granted)")
        checkCameraPermission()
        return granted
    }

    // MARK: - Microphone

    func checkMicrophonePermission() {
        let isTesting = ProcessInfo.processInfo.arguments.contains("-uitesting")
        if isTesting {
            microphoneStatus = .granted
            return
        }
        let status = AVCaptureDevice.authorizationStatus(for: .audio)
        microphoneStatus = mapAVStatus(status)
    }

    func requestMicrophonePermission() async -> Bool {
        let isTesting = ProcessInfo.processInfo.arguments.contains("-uitesting")
        if isTesting {
            microphoneStatus = .granted
            return true
        }
        AppLogger.audio.info("Requesting microphone permission...")
        let granted = await AVCaptureDevice.requestAccess(for: .audio)
        AppLogger.audio.info("Microphone permission result: \(granted)")
        checkMicrophonePermission()
        return granted
    }

    // MARK: - Screen Recording

    func checkScreenRecordingPermission() {
        let isTesting = ProcessInfo.processInfo.arguments.contains("-uitesting")
        if isTesting {
            screenRecordingStatus = .granted
            return
        }
        // CGPreflightScreenCaptureAccess() returns true if permitted
        // But it doesn't distinguish between .notDetermined and .denied easily without trying
        // However, for macOS 10.15+, this is the standard check.
        let granted = CGPreflightScreenCaptureAccess()
        screenRecordingStatus = granted ? .granted : .denied
    }

    func requestScreenRecordingPermission() {
        let isTesting = ProcessInfo.processInfo.arguments.contains("-uitesting")
        if isTesting {
            screenRecordingStatus = .granted
            return
        }
        // This API requests permission. It returns immediately.
        // The user must restart the app if they grant it.
        CGRequestScreenCaptureAccess()
        // We can't await the result, so we just re-check
        checkScreenRecordingPermission()
    }

    // MARK: - Request All Permissions

    /// Request all permissions needed for the app
    /// Returns a dictionary of permission statuses
    func requestAllPermissions() async -> [String: Bool] {
        if TestEnvironment.isUITesting {
            return ["camera": true, "microphone": true, "screenRecording": true]
        }
        AppLogger.general.info("Starting batch permission request...")
        let camera = await requestCameraPermission()
        let microphone = await requestMicrophonePermission()
        
        // Screen recording is requested on-demand
        AppLogger.general.info("Requesting screen recording permission...")
        requestScreenRecordingPermission()

        let results = [
            "camera": camera,
            "microphone": microphone,
            "screenRecording": screenRecordingStatus == .granted
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
        @unknown default: return .unknown
        }
    }

    // MARK: - Settings

    func openSystemSettings() {
        // Direct links to specific privacy panes
        // Note: These URLs are not officially documented but widely used.
        // Fallback to generic settings if needed.
        let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Camera")!
        NSWorkspace.shared.open(url)
    }

    func openScreenRecordingSettings() {
        // Direct link to Screen Recording privacy pane
        let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture")!
        NSWorkspace.shared.open(url)
    }

    // MARK: - Lifecycle

    func setupLifecycleObserver() {
        let isTesting = ProcessInfo.processInfo.arguments.contains("-uitesting")
        if isTesting { return }
        
        NotificationCenter.default.addObserver(forName: NSApplication.didBecomeActiveNotification, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in
                self?.checkAllPermissions()
            }
        }
    }
}
