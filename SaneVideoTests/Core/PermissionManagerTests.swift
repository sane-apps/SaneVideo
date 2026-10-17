// Tests for PermissionManager - permission checking, requesting, status tracking

import AVFoundation
@testable import SaneVideo
import Testing

@Suite("Permission Manager Tests")
@MainActor
struct PermissionManagerTests {
    @Test("Promptable permissions allow first-use camera and mic requests")
    func promptablePermissionsAllowInlineRequest() {
        #expect(PermissionManager.allowsRecordingStart(for: .granted, canPromptInline: true))
        #expect(PermissionManager.allowsRecordingStart(for: .notDetermined, canPromptInline: true))
        #expect(!PermissionManager.allowsRecordingStart(for: .notDetermined, canPromptInline: false))
        #expect(!PermissionManager.allowsRecordingStart(for: .denied, canPromptInline: true))
        #expect(!PermissionManager.allowsRecordingStart(for: .restricted, canPromptInline: true))
        #expect(!PermissionManager.allowsRecordingStart(for: .unknown, canPromptInline: true))
    }

    @Test("Recording without camera does not show a camera loading spinner")
    func recordingWithoutCameraDoesNotWantPreview() {
        #expect(!RecordingCameraPreviewPolicy.wantsCameraPreview(
            isScreenSharing: false,
            cameraEnabled: false
        ))
        #expect(RecordingCameraPreviewPolicy.wantsCameraPreview(
            isScreenSharing: false,
            cameraEnabled: true
        ))
        #expect(!RecordingCameraPreviewPolicy.wantsCameraPreview(
            isScreenSharing: true,
            cameraEnabled: true
        ))
    }

    @Test("Camera preview does not auto-start just because permission is already granted")
    func cameraPreviewDoesNotAutoStartWhenPermissionAlreadyGranted() {
        #expect(!CameraPreviewStartupPolicy.shouldAutoStartOnAppear(
            isScreenSharing: false,
            cameraStatus: .granted,
            cameraEnabled: false,
            cameraSurfaceVisible: false
        ))
    }

    @Test("Camera preview does not auto-start during screen capture")
    func cameraPreviewDoesNotAutoStartDuringScreenCapture() {
        #expect(!CameraPreviewStartupPolicy.shouldAutoStartOnAppear(
            isScreenSharing: true,
            cameraStatus: .granted,
            cameraEnabled: false,
            cameraSurfaceVisible: false
        ))
    }

    @Test("Camera preview does not auto-start without confirmed permission")
    func cameraPreviewDoesNotAutoStartWithoutPermission() {
        #expect(!CameraPreviewStartupPolicy.shouldAutoStartOnAppear(
            isScreenSharing: false,
            cameraStatus: .notDetermined,
            cameraEnabled: false,
            cameraSurfaceVisible: false
        ))
        #expect(!CameraPreviewStartupPolicy.shouldAutoStartOnAppear(
            isScreenSharing: false,
            cameraStatus: .granted,
            cameraEnabled: true,
            cameraSurfaceVisible: false
        ))
        #expect(!CameraPreviewStartupPolicy.shouldAutoStartOnAppear(
            isScreenSharing: false,
            cameraStatus: .granted,
            cameraEnabled: false,
            cameraSurfaceVisible: true
        ))
    }

    @Test("Recording preview restore is disabled during automated tests")
    func recordingPreviewRestoreStaysOffDuringTests() {
        #expect(!LaunchRecordingPreviewPolicy.shouldScheduleRestore(
            appMode: .recording,
            isTesting: true
        ))
        #expect(LaunchRecordingPreviewPolicy.shouldScheduleRestore(
            appMode: .recording,
            isTesting: false
        ))
    }
}
