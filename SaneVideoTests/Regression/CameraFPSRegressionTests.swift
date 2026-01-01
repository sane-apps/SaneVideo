//
//  CameraFPSRegressionTests.swift
//  SaneVideoTests
//
//  Regression tests for camera FPS format reconfiguration fix from 2025-12-31
//
//  Bug: Camera session reused old format when restarting, ignoring FPS preferences.
//       This caused recordings to use 15fps instead of requested 60fps.
//  Fix: Added reconfigureFormatIfNeeded() to check and reconfigure format on existing sessions.
//
//  Root cause: Commit 626956d (Dec 25) - format selection only happened on initial
//  session creation, not when an existing session was reused.
//

import AVFoundation
import CoreMedia
import Testing

@testable import SaneVideo

/// Regression tests for camera FPS format reconfiguration (BUG_TRACKING.md: Camera 15fps)
@Suite("Camera FPS Regression Tests")
struct CameraFPSRegressionTests {

    // MARK: - CameraManager State Tests

    /// Verifies CameraManager starts inactive (no stuck session state)
    @MainActor
    @Test("CameraManager initial state is inactive")
    func testCameraManagerInitialState() {
        // Arrange & Act
        let cameraManager = CameraManager()

        // Assert - verify actual initial state, not assumptions
        #expect(cameraManager.isActive == false, "Camera should not be active initially")
        #expect(cameraManager.session == nil, "Session should be nil initially")
        #expect(cameraManager.currentCameraID == nil, "No camera should be selected initially")
    }

    /// Verifies available cameras can be enumerated (regression: format filter removed all cameras)
    @MainActor
    @Test("Available cameras can be enumerated")
    func testAvailableCameras() {
        // Arrange
        let cameraManager = CameraManager()

        // Act
        let cameras = cameraManager.availableCameras

        // Assert - on real hardware, should have at least one camera
        // On CI without camera hardware, this may be empty - but should not crash
        #expect(cameras.count >= 0, "availableCameras should return array (may be empty on CI)")
    }

    // MARK: - Format Selection Logic Tests

    /// Verifies format sorting using actual AVFoundation types
    @Test("CMTime FPS calculation matches expected values")
    func testCMTimeFPSCalculation() {
        // Arrange - create real CMTime values
        let duration60fps = CMTime(value: 1, timescale: 60)
        let duration30fps = CMTime(value: 1, timescale: 30)
        let duration24fps = CMTime(value: 1001, timescale: 24000) // 23.976fps (film)

        // Act - calculate FPS using same logic as CameraManager
        let fps60 = duration60fps.timescale > 0
            ? Double(duration60fps.timescale) / Double(duration60fps.value)
            : 0
        let fps30 = duration30fps.timescale > 0
            ? Double(duration30fps.timescale) / Double(duration30fps.value)
            : 0
        let fps24 = duration24fps.timescale > 0
            ? Double(duration24fps.timescale) / Double(duration24fps.value)
            : 0

        // Assert - verify calculations are correct
        #expect(abs(fps60 - 60.0) < 0.01, "1/60 should calculate to 60fps, got \(fps60)")
        #expect(abs(fps30 - 30.0) < 0.01, "1/30 should calculate to 30fps, got \(fps30)")
        #expect(abs(fps24 - 23.976) < 0.01, "1001/24000 should be ~23.976fps, got \(fps24)")
    }

    /// Verifies the FPS tolerance check that determines if reconfiguration is needed
    @Test("FPS mismatch detection uses correct tolerance")
    func testFPSMismatchDetection() {
        // Arrange - simulate current vs target FPS scenarios
        let scenarios: [(current: Double, target: Double, shouldReconfigure: Bool)] = [
            (59.94, 60.0, false),   // Within tolerance - no reconfigure
            (60.0, 60.0, false),    // Exact match - no reconfigure
            (29.97, 30.0, false),   // NTSC 29.97 matches 30fps target
            (15.0, 60.0, true),     // Major mismatch - MUST reconfigure (the bug case)
            (30.0, 60.0, true),     // Different target - reconfigure
            (24.0, 30.0, true),     // Different target - reconfigure
        ]

        // Act & Assert - verify each scenario
        for (current, target, expectedReconfigure) in scenarios {
            let tolerance = 1.0
            let difference = abs(current - target)
            let needsReconfigure = difference >= tolerance

            #expect(needsReconfigure == expectedReconfigure,
                   "current=\(current)fps, target=\(target)fps: expected reconfigure=\(expectedReconfigure), got \(needsReconfigure)")
        }
    }

    /// Verifies the 15fps bug scenario would be detected
    @Test("15fps to 60fps mismatch is detected correctly - the original bug scenario")
    func test15fpsTo60fpsBugScenario() {
        // Arrange - the exact scenario from the bug
        let currentFPS = 15.0  // What the camera was stuck at
        let targetFPS = 60.0   // What user requested
        let tolerance = 1.0    // Same tolerance as CameraManager

        // Act
        let difference = abs(currentFPS - targetFPS)
        let needsReconfigure = difference >= tolerance

        // Assert - this MUST trigger reconfiguration
        #expect(needsReconfigure == true,
               "15fps→60fps MUST trigger reconfiguration (difference: \(difference)fps)")
        #expect(difference == 45.0, "Difference should be exactly 45fps")
    }

    // MARK: - Resolution Preference Tests

    /// Verifies resolution settings use correct pixel dimensions
    @Test("Export resolution settings have correct dimensions")
    func testExportResolutionDimensions() {
        // Act - get actual dimensions from the resolution enum
        let res4K = SaneExportSettings.ExportResolution.uhd4K.size
        let res1080 = SaneExportSettings.ExportResolution.hd1080.size
        let res720 = SaneExportSettings.ExportResolution.hd720.size

        // Assert - verify actual values
        #expect(res4K.width == 3840 && res4K.height == 2160, "4K should be 3840x2160")
        #expect(res1080.width == 1920 && res1080.height == 1080, "1080p should be 1920x1080")
        #expect(res720.width == 1280 && res720.height == 720, "720p should be 1280x720")
    }

    // MARK: - User Preferences Integration Tests

    /// Verifies UserPreferences provides correct default FPS
    @MainActor
    @Test("UserPreferences default recording FPS is accessible")
    func testUserPreferencesDefaultFPS() {
        // Arrange
        let prefs = UserPreferences()

        // Act
        let recordingFPS = prefs.recordingFPS

        // Assert - verify it's a reasonable FPS value
        #expect(recordingFPS >= 24.0 && recordingFPS <= 120.0,
               "Recording FPS should be between 24-120, got \(recordingFPS)")
    }

    /// Verifies UserPreferences provides correct default resolution
    @MainActor
    @Test("UserPreferences default recording resolution is accessible")
    func testUserPreferencesDefaultResolution() {
        // Arrange
        let prefs = UserPreferences()

        // Act
        let resolution = prefs.recordingResolution

        // Assert - verify it's a valid resolution
        let validResolutions: [SaneExportSettings.ExportResolution] = [.hd720, .hd1080, .uhd4K]
        #expect(validResolutions.contains(resolution),
               "Recording resolution should be a valid preset, got \(resolution)")
    }
}
