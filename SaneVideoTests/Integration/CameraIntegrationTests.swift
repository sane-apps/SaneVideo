//
//  CameraIntegrationTests.swift
//  SaneVideoTests
//
//  Integration tests for camera functionality
//  Tests actual AVCaptureSession behavior when camera hardware is available
//

import AVFoundation
import CoreMedia
import Testing

@testable import SaneVideo

/// Integration tests for camera functionality
/// Note: Some tests require camera hardware and will skip gracefully on CI
@Suite("Camera Integration Tests")
@MainActor
struct CameraIntegrationTests {
    private func hardwareIntegrationEnabled() -> Bool {
        TestEnvironment.allowsHardwareIntegration
    }

    // MARK: - Hardware Detection

    /// Helper to check if camera hardware is available
    private var hasCameraHardware: Bool {
        let discoverySession = AVCaptureDevice.DiscoverySession(
            deviceTypes: [.builtInWideAngleCamera, .external],
            mediaType: .video,
            position: .unspecified
        )
        return !discoverySession.devices.isEmpty
    }

    // MARK: - Permission Tests

    @Test("Camera permission status is queryable")
    func testCameraPermissionQueryable() {
        // Act
        let status = AVCaptureDevice.authorizationStatus(for: .video)

        // Assert - should return a valid status (not crash)
        let validStatuses: [AVAuthorizationStatus] = [.notDetermined, .restricted, .denied, .authorized]
        #expect(validStatuses.contains(status),
               "Camera permission status should be a valid AVAuthorizationStatus")
    }

    // MARK: - CameraManager Lifecycle Tests

    @Test("CameraManager can start and stop without crashing")
    func testCameraManagerLifecycle() async throws {
        guard hardwareIntegrationEnabled() else { return }

        // Skip if no camera hardware (CI environment)
        guard hasCameraHardware else {
            // On CI without camera, just verify the manager can be created
            let manager = CameraManager()
            #expect(manager.isActive == false)
            return
        }

        // Arrange
        let cameraManager = CameraManager()

        // Act - start the session
        try await cameraManager.start()

        // Give it time to start
        try await Task.sleep(nanoseconds: 500_000_000) // 0.5s

        // Assert - verify state transitioned (or stayed false if no permission)
        let stateAfterStart = cameraManager.isActive

        // Stop the session
        cameraManager.stop()

        // Give it time to stop
        try await Task.sleep(nanoseconds: 200_000_000) // 0.2s

        // Assert - should be inactive after stop
        #expect(cameraManager.isActive == false, "Camera should be inactive after stopSession")

        // Start state depends on permissions - camera may or may not become active
        // We just verify it doesn't throw and the state is consistent
    }

    // MARK: - Format Configuration Tests

    @Test("Camera formats can be enumerated from device")
    func testCameraFormatEnumeration() throws {
        guard hardwareIntegrationEnabled() else { return }

        guard hasCameraHardware else {
            // Skip on CI
            return
        }

        // Arrange
        let discoverySession = AVCaptureDevice.DiscoverySession(
            deviceTypes: [.builtInWideAngleCamera, .external],
            mediaType: .video,
            position: .unspecified
        )

        guard let camera = discoverySession.devices.first else {
            Issue.record("No camera found despite hasCameraHardware returning true")
            return
        }

        // Act
        let formats = camera.formats

        // Assert - should have at least one format
        #expect(!formats.isEmpty, "Camera should have at least one supported format")

        // Verify formats have valid properties
        for format in formats {
            let dims = CMVideoFormatDescriptionGetDimensions(format.formatDescription)
            #expect(dims.width > 0, "Format width should be positive")
            #expect(dims.height > 0, "Format height should be positive")

            let fpsRanges = format.videoSupportedFrameRateRanges
            #expect(!fpsRanges.isEmpty, "Format should have at least one FPS range")

            for range in fpsRanges {
                #expect(range.maxFrameRate >= range.minFrameRate,
                       "Max FPS should be >= min FPS")
            }
        }
    }

    @Test("Camera supports expected FPS range for 1080p")
    func testCamera1080pFPSSupport() throws {
        guard hardwareIntegrationEnabled() else { return }

        guard hasCameraHardware else {
            return
        }

        // Arrange
        let discoverySession = AVCaptureDevice.DiscoverySession(
            deviceTypes: [.builtInWideAngleCamera, .external],
            mediaType: .video,
            position: .unspecified
        )

        guard let camera = discoverySession.devices.first else {
            Issue.record("No camera found")
            return
        }

        // Act - find 1080p formats
        let formats1080p = camera.formats.filter { format in
            let dims = CMVideoFormatDescriptionGetDimensions(format.formatDescription)
            return dims.width == 1920 && dims.height == 1080
        }

        // Assert - should have 1080p support
        #expect(!formats1080p.isEmpty, "Camera should support 1080p resolution")

        // Find max FPS for 1080p
        var maxFPS: Double = 0
        for format in formats1080p {
            for range in format.videoSupportedFrameRateRanges {
                maxFPS = max(maxFPS, range.maxFrameRate)
            }
        }

        // Most modern cameras support at least 30fps at 1080p
        #expect(maxFPS >= 30.0, "1080p should support at least 30fps, got \(maxFPS)")
    }

    // MARK: - Session Configuration Tests

    @Test("AVCaptureSession can be configured without error")
    func testSessionConfiguration() async throws {
        guard hardwareIntegrationEnabled() else { return }

        guard hasCameraHardware else {
            return
        }

        // Check permission
        let status = AVCaptureDevice.authorizationStatus(for: .video)
        guard status == .authorized else {
            // Can't test without permission
            return
        }

        // Arrange
        let session = AVCaptureSession()
        let discoverySession = AVCaptureDevice.DiscoverySession(
            deviceTypes: [.builtInWideAngleCamera, .external],
            mediaType: .video,
            position: .unspecified
        )

        guard let camera = discoverySession.devices.first else {
            Issue.record("No camera found")
            return
        }

        // Act - configure session
        session.beginConfiguration()

        do {
            let input = try AVCaptureDeviceInput(device: camera)
            if session.canAddInput(input) {
                session.addInput(input)
            }
        } catch {
            Issue.record("Failed to create device input: \(error)")
            return
        }

        session.commitConfiguration()

        // Assert - session should have the input
        #expect(!session.inputs.isEmpty, "Session should have at least one input")
    }

}
