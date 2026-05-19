//
//  PermissionManagerTests.swift
//  SaneVideoTests
//
//  Tests for PermissionManager - permission checking, requesting, status tracking
//

import AVFoundation
@testable import SaneVideo
import Testing

@Suite("Permission Manager Tests")
@MainActor
struct PermissionManagerTests {
    // MARK: - Test Setup

    var sut: PermissionManager {
        PermissionManager()
    }

    // MARK: - Initial State Tests

    @Test("Initial state in test environment grants all permissions")
    func initialState() {
        // Arrange & Act
        let manager = sut

        // Assert - In test environment, all permissions should be granted
        #expect(manager.cameraStatus == .granted, "Camera should be granted in test environment")
        #expect(manager.microphoneStatus == .granted, "Microphone should be granted in test environment")
        #expect(manager.screenRecordingStatus == .granted, "Screen recording should be granted in test environment")
    }

    // MARK: - Permission Checking Tests

    @Test("Check camera permission updates status")
    func checkCameraPermission() {
        // Arrange
        let manager = sut

        // Act
        manager.checkCameraPermission()

        // Assert - In test environment, should be granted
        #expect(manager.cameraStatus == .granted, "Camera permission should be granted in test environment")
    }

    @Test("Check microphone permission updates status")
    func checkMicrophonePermission() {
        // Arrange
        let manager = sut

        // Act
        manager.checkMicrophonePermission()

        // Assert - In test environment, should be granted
        #expect(manager.microphoneStatus == .granted, "Microphone permission should be granted in test environment")
    }

    @Test("Check screen recording permission updates status")
    func checkScreenRecordingPermission() {
        // Arrange
        let manager = sut

        // Act
        manager.checkScreenRecordingPermission()

        // Assert - In test environment, should be granted
        #expect(manager.screenRecordingStatus == .granted, "Screen recording permission should be granted in test environment")
    }

    @Test("Check all permissions updates all statuses")
    func checkAllPermissions() {
        // Arrange
        let manager = sut

        // Act
        manager.checkAllPermissions()

        // Assert - All should be granted in test environment
        #expect(manager.cameraStatus == .granted)
        #expect(manager.microphoneStatus == .granted)
        #expect(manager.screenRecordingStatus == .granted)
    }

    // MARK: - Permission Request Tests

    @Test("Request camera permission returns granted in test")
    func requestCameraPermission() async {
        // Arrange
        let manager = sut

        // Act
        let granted = await manager.requestCameraPermission()

        // Assert - In test environment, should return true
        #expect(granted == true, "Should be granted in test environment")
        #expect(manager.cameraStatus == .granted)
    }

    @Test("Request microphone permission returns granted in test")
    func requestMicrophonePermission() async {
        // Arrange
        let manager = sut

        // Act
        let granted = await manager.requestMicrophonePermission()

        // Assert - In test environment, should return true
        #expect(granted == true, "Should be granted in test environment")
        #expect(manager.microphoneStatus == .granted)
    }

    @Test("Request screen recording permission updates status")
    func requestScreenRecordingPermission() {
        // Arrange
        let manager = sut

        // Act
        manager.requestScreenRecordingPermission()

        // Assert - In test environment, should be granted
        #expect(manager.screenRecordingStatus == .granted, "Should be granted in test environment")
    }

    @Test("Request all permissions returns all granted")
    func requestAllPermissions() async {
        // Arrange
        let manager = sut

        // Act
        let results = await manager.requestAllPermissions()

        // Assert - All should be granted in test environment
        #expect(results["camera"] == true)
        #expect(results["microphone"] == true)
        #expect(results["screenRecording"] == true)
    }

    // MARK: - Permission Verification Tests

    @Test("Verify permissions for recording with all required")
    func verifyPermissionsForRecording() {
        // Arrange
        let manager = sut

        // Act
        let verified = manager.verifyPermissionsForRecording(
            requiresCamera: true,
            requiresMicrophone: true,
            requiresScreenRecording: false
        )

        // Assert - In test environment, should return true
        #expect(verified == true, "Should verify in test environment")
    }

    @Test("Verify permissions for recording with screen recording required")
    func verifyPermissionsWithScreenRecording() {
        // Arrange
        let manager = sut

        // Act
        let verified = manager.verifyPermissionsForRecording(
            requiresCamera: true,
            requiresMicrophone: true,
            requiresScreenRecording: true
        )

        // Assert - In test environment, should return true
        #expect(verified == true, "Should verify in test environment")
    }

    @Test("Promptable permissions allow first-use camera and mic requests")
    func promptablePermissionsAllowInlineRequest() {
        #expect(PermissionManager.allowsRecordingStart(for: .granted, canPromptInline: true))
        #expect(PermissionManager.allowsRecordingStart(for: .notDetermined, canPromptInline: true))
        #expect(!PermissionManager.allowsRecordingStart(for: .notDetermined, canPromptInline: false))
        #expect(!PermissionManager.allowsRecordingStart(for: .denied, canPromptInline: true))
        #expect(!PermissionManager.allowsRecordingStart(for: .restricted, canPromptInline: true))
        #expect(!PermissionManager.allowsRecordingStart(for: .unknown, canPromptInline: true))
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

    // MARK: - Publisher Tests

    @Test("Camera status publisher exists")
    func cameraStatusPublisher() {
        // Arrange
        let manager = sut

        // Act
        let publisher = manager.cameraStatusPublisher

        // Assert - Publisher should exist
        #expect(publisher != nil, "Publisher should exist")
    }

    @Test("Microphone status publisher exists")
    func microphoneStatusPublisher() {
        // Arrange
        let manager = sut

        // Act
        let publisher = manager.microphoneStatusPublisher

        // Assert - Publisher should exist
        #expect(publisher != nil, "Publisher should exist")
    }

    @Test("Screen recording status publisher exists")
    func screenRecordingStatusPublisher() {
        // Arrange
        let manager = sut

        // Act
        let publisher = manager.screenRecordingStatusPublisher

        // Assert - Publisher should exist
        #expect(publisher != nil, "Publisher should exist")
    }
}
