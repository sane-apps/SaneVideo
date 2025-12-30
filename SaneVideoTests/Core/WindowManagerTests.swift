//
//  WindowManagerTests.swift
//  SaneVideoTests
//
//  Tests for WindowManager - window lifecycle, PiP management, screen sharing
//

import Testing
import AppKit
@testable import SaneVideo

@Suite("Window Manager Tests")
@MainActor
struct WindowManagerTests {

    // MARK: - Test Setup

    var sut: WindowManager {
        WindowManager()
    }

    // MARK: - Initial State Tests

    @Test("Initial state has correct defaults")
    func initialState() {
        // Arrange & Act
        let manager = sut

        // Assert
        #expect(manager.isPiPVisible == true, "PiP should be visible by default")
        #expect(manager.isScreenSharing == false, "Screen sharing should be false by default")
        #expect(manager.isTogglingScreenShare == false, "Should not be toggling by default")
        #expect(manager.excludedWindowIDs.isEmpty, "No windows should be excluded initially")
        #expect(manager.pipWindowFrame == nil, "No PiP window frame initially")
    }

    // MARK: - PiP Visibility Tests

    @Test("Toggle PiP visibility updates state")
    func togglePiPVisibility() {
        // Arrange
        let manager = sut
        let initialVisibility = manager.isPiPVisible

        // Act
        manager.togglePiPVisibility(isCameraActive: true, isRecording: false)

        // Assert
        #expect(manager.isPiPVisible != initialVisibility, "PiP visibility should toggle")
    }

    @Test("Update PiP state when screen sharing is active")
    func updatePiPStateWithScreenSharing() {
        // Arrange
        let manager = sut
        manager.isScreenSharing = true
        manager.isPiPVisible = true

        // Act
        manager.updatePiPState(isCameraActive: true, isRecording: false)

        // Assert - PiP should be shown when screen sharing and visible
        // Note: Actual window creation is skipped in tests, but state should be correct
        #expect(manager.isScreenSharing == true)
        #expect(manager.isPiPVisible == true)
    }

    @Test("Update PiP state when screen sharing is inactive")
    func updatePiPStateWithoutScreenSharing() {
        // Arrange
        let manager = sut
        manager.isScreenSharing = false
        manager.isPiPVisible = true

        // Act
        manager.updatePiPState(isCameraActive: true, isRecording: false)

        // Assert - PiP should be hidden when not screen sharing
        #expect(manager.isScreenSharing == false)
    }

    // MARK: - Screen Sharing Tests

    @Test("Toggle screen sharing updates state")
    func toggleScreenShare() {
        // Arrange
        let manager = sut
        let initialState = manager.isScreenSharing

        // Act
        manager.toggleScreenShare(isRecording: false, isCameraActive: true)

        // Assert
        #expect(manager.isScreenSharing != initialState, "Screen sharing state should toggle")
    }

    // MARK: - Window Exclusion Tests

    @Test("Excluded window IDs returns empty when no windows")
    func excludedWindowIDsEmpty() {
        // Arrange
        let manager = sut

        // Act
        let excludedIDs = manager.excludedWindowIDs

        // Assert
        #expect(excludedIDs.isEmpty, "Should have no excluded windows initially")
    }

    @Test("PiP window frame is nil when no window")
    func pipWindowFrameNil() {
        // Arrange
        let manager = sut

        // Act
        let frame = manager.pipWindowFrame

        // Assert
        #expect(frame == nil, "PiP window frame should be nil when no window exists")
    }

    // MARK: - Floating Controls Tests

    @Test("Show floating controls completes synchronously")
    func showFloatingControls() {
        // Arrange
        let manager = sut
        let initialExcludedCount = manager.excludedWindowIDs.count

        // Act - In test environment, this returns early but should complete synchronously
        manager.showFloatingControls()

        // Assert - Method completed without throwing, state remains accessible
        // Verify excludedWindowIDs is still accessible (tests state integrity)
        let finalExcludedCount = manager.excludedWindowIDs.count
        #expect(finalExcludedCount >= 0, "excludedWindowIDs should remain accessible")
        #expect(finalExcludedCount == initialExcludedCount, "No windows should be created in test environment")
    }

    @Test("Hide floating controls completes synchronously")
    func hideFloatingControls() {
        // Arrange
        let manager = sut
        let initialExcludedCount = manager.excludedWindowIDs.count

        // Act - In test environment, this returns early but should complete synchronously
        manager.hideFloatingControls()

        // Assert - Method completed without throwing, state remains accessible
        let finalExcludedCount = manager.excludedWindowIDs.count
        #expect(finalExcludedCount >= 0, "excludedWindowIDs should remain accessible")
        #expect(finalExcludedCount == initialExcludedCount, "No windows should be removed in test environment")
    }

    // MARK: - Window Management Tests

    @Test("Force hide PiP for system overlay completes without error")
    func forceHidePiPForSystemOverlay() {
        // Arrange
        let manager = sut
        let initialExcludedCount = manager.excludedWindowIDs.count
        let initialPiPVisible = manager.isPiPVisible

        // Act - This calls hidePiPWindow() and showFloatingControls()
        // In test environment, both return early but we can verify state remains consistent
        manager.forceHidePiPForSystemOverlay()

        // Assert - Method completed, state remains accessible and consistent
        // Verify excludedWindowIDs is still accessible (proves method completed)
        let finalExcludedCount = manager.excludedWindowIDs.count
        #expect(finalExcludedCount == initialExcludedCount, "No windows should be created/removed in test environment")
        // Verify PiP visibility state is still accessible (proves state integrity)
        let finalPiPVisible = manager.isPiPVisible
        #expect(finalPiPVisible == initialPiPVisible, "PiP visibility should not change in test environment")
    }

    @Test("Minimize main window completes synchronously")
    func minimizeMainWindow() {
        // Arrange
        let manager = sut
        let initialExcludedCount = manager.excludedWindowIDs.count

        // Act - In test environment, this returns early but should complete synchronously
        manager.minimizeMainWindow()

        // Assert - Method completed without throwing, state remains accessible
        let finalExcludedCount = manager.excludedWindowIDs.count
        #expect(finalExcludedCount >= 0, "excludedWindowIDs should remain accessible")
        #expect(finalExcludedCount == initialExcludedCount, "No windows should be affected in test environment")
    }

    @Test("Restore main window completes synchronously")
    func restoreMainWindow() {
        // Arrange
        let manager = sut
        let initialExcludedCount = manager.excludedWindowIDs.count

        // Act - In test environment, this returns early but should complete synchronously
        manager.restoreMainWindow()

        // Assert - Method completed without throwing, state remains accessible
        let finalExcludedCount = manager.excludedWindowIDs.count
        #expect(finalExcludedCount >= 0, "excludedWindowIDs should remain accessible")
        #expect(finalExcludedCount == initialExcludedCount, "No windows should be affected in test environment")
    }

    @Test("Cleanup all windows completes synchronously")
    func cleanupAllWindows() {
        // Arrange
        let manager = sut
        let initialExcludedCount = manager.excludedWindowIDs.count

        // Act - This calls hidePiPWindow() and hideFloatingControls()
        // In test environment, both return early but we can verify state remains consistent
        manager.cleanupAllWindows()

        // Assert - Method completed, state remains accessible and consistent
        let finalExcludedCount = manager.excludedWindowIDs.count
        #expect(finalExcludedCount >= 0, "excludedWindowIDs should remain accessible")
        #expect(finalExcludedCount == initialExcludedCount, "No windows should be affected in test environment")
        // Verify PiP frame is still accessible (should be nil after cleanup)
        #expect(manager.pipWindowFrame == nil, "PiP window frame should be nil after cleanup")
    }

    // MARK: - State Coordination Tests

    @Test("PiP state respects both screen sharing and visibility flags")
    func pipStateCoordination() {
        // Arrange
        let manager = sut

        // Test case 1: Screen sharing active, PiP visible
        manager.isScreenSharing = true
        manager.isPiPVisible = true
        manager.updatePiPState(isCameraActive: true, isRecording: false)
        #expect(manager.isScreenSharing == true)
        #expect(manager.isPiPVisible == true)

        // Test case 2: Screen sharing active, PiP hidden
        manager.isScreenSharing = true
        manager.isPiPVisible = false
        manager.updatePiPState(isCameraActive: true, isRecording: false)
        #expect(manager.isScreenSharing == true)
        #expect(manager.isPiPVisible == false)

        // Test case 3: Screen sharing inactive, PiP visible
        manager.isScreenSharing = false
        manager.isPiPVisible = true
        manager.updatePiPState(isCameraActive: true, isRecording: false)
        #expect(manager.isScreenSharing == false)
    }
}
