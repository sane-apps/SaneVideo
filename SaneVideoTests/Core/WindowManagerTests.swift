// Tests for WindowManager - window lifecycle, PiP management, screen sharing

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

    @Test("PiP stays hidden when camera is inactive")
    func updatePiPStateWithoutCamera() {
        let manager = sut
        manager.isScreenSharing = true
        manager.isPiPVisible = true

        manager.updatePiPState(isCameraActive: false, isRecording: false)

        #expect(manager.isScreenSharing == true)
        #expect(manager.isPiPVisible == true, "User preference stays on even when there is no live camera feed")
        #expect(manager.pipWindowFrame == nil, "PiP window should not exist without an active camera")
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

    @Test("Floating controls window reserves recording width")
    func floatingControlsWindow_UsesRecordingPanelSize() {
        let window = FloatingControlsWindow()
        defer { window.close() }

        #expect(window.frame.width == FloatingControlsWindow.preferredPanelSize.width)
        #expect(window.frame.height == FloatingControlsWindow.preferredPanelSize.height)
        #expect(window.minSize == FloatingControlsWindow.preferredPanelSize)
    }

    @Test("Floating controls content fits inside the recording panel")
    func floatingControlsWindow_ContentFitsRecordingPanel() {
        let appState = ServiceContainer.shared.appState
        let originalRecording = appState.recordingState.isRecording
        let originalPaused = appState.recordingState.isPaused

        appState.recordingState.isRecording = true
        appState.recordingState.isPaused = false

        defer {
            appState.recordingState.isRecording = originalRecording
            appState.recordingState.isPaused = originalPaused
        }

        let window = FloatingControlsWindow()
        defer { window.close() }

        window.contentView?.layoutSubtreeIfNeeded()
        let fittedWidth = ceil(window.contentView?.fittingSize.width ?? 0)
        #expect(window.frame.width >= fittedWidth, "Recording-state content should fit inside the floating panel")
    }

    // MARK: - Window Management Tests

    @Test("Force-hiding PiP for a system overlay keeps the user PiP preference")
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
}
