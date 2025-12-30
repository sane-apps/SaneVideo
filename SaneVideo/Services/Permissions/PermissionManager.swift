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
class PermissionManager: PermissionManagerProtocol {
  // MARK: - Status

  var cameraStatus: PermissionStatus = .notDetermined {
    didSet {
      _cameraStatusSubject.send(cameraStatus)
      notifyPermissionStatusChanged() // CRITICAL FIX: Notify on status change
    }
  }
  var microphoneStatus: PermissionStatus = .notDetermined {
    didSet {
      _microphoneStatusSubject.send(microphoneStatus)
      notifyPermissionStatusChanged() // CRITICAL FIX: Notify on status change
    }
  }
  var screenRecordingStatus: PermissionStatus = .notDetermined {
    didSet {
      _screenRecordingStatusSubject.send(screenRecordingStatus)
      notifyPermissionStatusChanged() // CRITICAL FIX: Notify on status change
    }
  }
  
  // CRITICAL FIX: Track if screen recording permission was ever requested
  // This helps distinguish .notDetermined from .denied
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
    // CGPreflightScreenCaptureAccess() returns true if permitted
    // But it doesn't distinguish between .notDetermined and .denied easily without trying
    // However, for macOS 10.15+, this is the standard check.
    let granted = CGPreflightScreenCaptureAccess()
    
    // CRITICAL FIX: Use tracking to distinguish .notDetermined from .denied
    if granted {
      screenRecordingStatus = .granted
    } else {
      // If we've requested before, it's denied. Otherwise, it's not determined.
      screenRecordingStatus = screenRecordingWasRequested ? .denied : .notDetermined
    }
  }

  func requestScreenRecordingPermission() {
    if TestEnvironment.isTesting {
      screenRecordingStatus = .granted
      return
    }
    // CRITICAL FIX: Mark that we've requested permission
    screenRecordingWasRequested = true
    
    // CRITICAL FIX: Document restart requirement for user
    AppLogger.general.info("📺 Requesting screen recording permission...")
    AppLogger.general.warning("⚠️ Note: If permission is granted, the app must be restarted for it to take effect.")
    
    // This API requests permission. It returns immediately.
    // The user must restart the app if they grant it.
    CGRequestScreenCaptureAccess()
    
    // CRITICAL FIX: Show user-friendly message about restart requirement
    Task { @MainActor in
      ServiceContainer.shared.toastManager.show(
        "Screen recording permission requested. If granted, please restart the app for it to take effect.",
        type: .info
      )
    }
    
    // We can't await the result, so we just re-check
    checkScreenRecordingPermission()
  }

  // MARK: - Request All Permissions

  /// Request all permissions needed for the app
  /// Returns a dictionary of permission statuses
  func requestAllPermissions() async -> [String: Bool] {
    if TestEnvironment.isTesting {
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
    // CRITICAL FIX: Exhaustive switch to handle all cases
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
    // Direct links to specific privacy panes
    // Note: These URLs are not officially documented but widely used.
    // Fallback to generic settings if needed.
    guard let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Camera") else { return }
    NSWorkspace.shared.open(url)
  }

  func openScreenRecordingSettings() {
    // Direct link to Screen Recording privacy pane
    guard let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture") else { return }
    NSWorkspace.shared.open(url)
  }

  // MARK: - Lifecycle

  func setupLifecycleObserver() {
    if TestEnvironment.isTesting { return }

    // CRITICAL FIX: Re-check permissions when app becomes active
    // This handles cases where user revokes permissions in System Settings
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
  
  /// CRITICAL FIX: Verify permissions before critical operations
  /// Returns true if all required permissions are granted, false otherwise
  /// Also updates permission status if they've been revoked
  func verifyPermissionsForRecording(requiresCamera: Bool = true, requiresMicrophone: Bool = true, requiresScreenRecording: Bool = false) -> Bool {
    if TestEnvironment.isTesting { return true }
    
    // Re-check permissions before use (they might have been revoked)
    checkCameraPermission()
    checkMicrophonePermission()
    if requiresScreenRecording {
      checkScreenRecordingPermission()
    }
    
    // Check if all required permissions are granted
    if requiresCamera && cameraStatus != .granted {
      AppLogger.general.warning("⚠️ Camera permission not granted: \(cameraStatus)")
      return false
    }
    
    if requiresMicrophone && microphoneStatus != .granted {
      AppLogger.general.warning("⚠️ Microphone permission not granted: \(microphoneStatus)")
      return false
    }
    
    if requiresScreenRecording && screenRecordingStatus != .granted {
      AppLogger.general.warning("⚠️ Screen recording permission not granted: \(screenRecordingStatus)")
      return false
    }
    
    return true
  }
  
  // MARK: - Permission Status Synchronization
  
  /// CRITICAL FIX: Notify all services when permission status changes
  /// This ensures all services stay in sync with permission state
  private func notifyPermissionStatusChanged() {
    // Permission status changes are already published via Combine publishers
    // Services that subscribe to these publishers will be notified automatically
    // Post notification for services that might not be using Combine
    NotificationCenter.default.post(
      name: .permissionStatusChanged,
      object: nil,
      userInfo: [
        "camera": cameraStatus,
        "microphone": microphoneStatus,
        "screenRecording": screenRecordingStatus
      ]
    )
  }
}

// MARK: - Notification Names

extension Notification.Name {
  static let permissionStatusChanged = Notification.Name("permissionStatusChanged")
}
