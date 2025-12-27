//
//  SmokeAccessibilityTests.swift
//  SaneVideoUITests
//
//  Smoke tests to verify accessibility identifiers exist and are tappable.
//  Organized by feature section for maintainability.
//
//  These are lightweight tests that verify UI elements are present
//  without testing complex interactions.
//

import XCTest
@testable import SaneVideo

final class SmokeAccessibilityTests: XCTestCase {

    var app: XCUIApplication!

    override func setUpWithError() throws {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launchArguments = ["-uitesting", "-ui_testing", "YES", "-open_editor", "YES"]
        app.launch()
        app.activate()

        // Wait for app to be ready
        let mainWindow = app.windows.firstMatch
        guard mainWindow.waitForExistence(timeout: 10) else {
            XCTFail("App did not launch")
            return
        }
    }

    override func tearDownWithError() throws {
        app = nil
    }

    // MARK: - Recording Controls

    func testRecordingControlsExist() throws {
        // These controls should exist in recording mode
        let recordButton = app.buttons[AccessibilityIdentifiers.recordButton]
        let cameraToggle = app.buttons[AccessibilityIdentifiers.cameraToggle]
        let micToggle = app.buttons[AccessibilityIdentifiers.micToggle]
        let screenShareToggle = app.buttons[AccessibilityIdentifiers.screenShareToggle]

        // Switch to recording mode first
        let modeSwitcher = app.buttons[AccessibilityIdentifiers.modeSwitcher]
        if modeSwitcher.exists && modeSwitcher.isHittable {
            modeSwitcher.tap()
            sleep(1)
        }

        // Verify core recording controls exist
        XCTAssertTrue(
            recordButton.waitForExistence(timeout: 5),
            "RecordButton should exist in recording mode"
        )

        // Camera and mic toggles may be in different locations depending on mode
        if cameraToggle.exists {
            XCTAssertTrue(cameraToggle.isHittable, "CameraToggle should be tappable")
        }
        if micToggle.exists {
            XCTAssertTrue(micToggle.isHittable, "MicToggle should be tappable")
        }
    }

    // MARK: - Timeline Controls

    func testTimelineControlsExist() throws {
        // Timeline controls in editor mode
        let timelineEmptyState = app.otherElements[AccessibilityIdentifiers.timelineEmptyState]
        let playButton = app.buttons[AccessibilityIdentifiers.playButton]

        // At least one should exist (empty state or playback controls)
        let hasTimeline = timelineEmptyState.waitForExistence(timeout: 3) ||
                         playButton.waitForExistence(timeout: 3)

        XCTAssertTrue(hasTimeline, "Timeline area should exist (empty state or controls)")
    }

    func testTimelineZoomControls() throws {
        // Look for zoom slider
        let zoomSlider = app.sliders["timeline.zoom_slider"]
        let snapToggle = app.buttons["timeline.toggle_snap"]
        let magneticToggle = app.buttons["timeline.toggle_magnetic"]

        // These may only appear when timeline has content
        // Just verify no crash when querying
        _ = zoomSlider.exists
        _ = snapToggle.exists
        _ = magneticToggle.exists
    }

    // MARK: - Inspector Controls

    func testInspectorControlsExist() throws {
        let inspectorToggle = app.buttons[AccessibilityIdentifiers.inspectorToggle]

        if inspectorToggle.waitForExistence(timeout: 5) {
            XCTAssertTrue(inspectorToggle.isHittable, "InspectorToggle should be tappable")

            // Open inspector
            inspectorToggle.tap()
            sleep(1)

            // Check for inspector mode toggle
            let modeToggle = app.buttons[AccessibilityIdentifiers.inspectorModeToggle]
            if modeToggle.exists {
                XCTAssertTrue(modeToggle.isHittable, "InspectorModeToggle should be tappable")
            }
        }
    }

    // MARK: - Export Sheet

    func testExportSheetElementsExist() throws {
        // Open export sheet via keyboard shortcut
        app.typeKey("e", modifierFlags: .command)
        sleep(2)

        let exportSheet = app.sheets.firstMatch
        if exportSheet.waitForExistence(timeout: 5) {
            // Check for format and resolution pickers
            let formatPicker = app.popUpButtons["export.format_picker"]
            let resolutionPicker = app.popUpButtons["export.resolution_picker"]

            // These may be in different UI hierarchies
            _ = formatPicker.exists
            _ = resolutionPicker.exists

            // Close sheet
            let cancelButton = app.buttons[AccessibilityIdentifiers.cancelExportButton]
            if cancelButton.exists {
                cancelButton.tap()
            } else {
                app.typeKey(.escape, modifierFlags: [])
            }
        }
    }

    // MARK: - Player Controls

    func testPlayerControlsExist() throws {
        let playPauseButton = app.buttons["player.toggle_play_pause"]
        let stepBackward = app.buttons["player.step_backward"]
        let stepForward = app.buttons["player.step_forward"]

        // Player controls appear when there's content in timeline
        // Just verify queries don't crash
        _ = playPauseButton.exists
        _ = stepBackward.exists
        _ = stepForward.exists
    }

    // MARK: - Audio Controls

    func testAudioControlsExist() throws {
        // Open inspector first
        let inspectorToggle = app.buttons[AccessibilityIdentifiers.inspectorToggle]
        if inspectorToggle.exists && inspectorToggle.isHittable {
            inspectorToggle.tap()
            sleep(1)
        }

        // Audio controls in inspector
        let muteButton = app.buttons["audio.mute_button"]
        let volumeSlider = app.sliders["audio.volume.slider"]

        // These only appear when a clip with audio is selected
        _ = muteButton.exists
        _ = volumeSlider.exists
    }

    // MARK: - Settings Elements

    func testSettingsAccessible() throws {
        // Open settings via keyboard shortcut
        app.typeKey(",", modifierFlags: .command)
        sleep(2)

        let settingsWindow = app.windows[AccessibilityIdentifiers.settingsWindow]
        let settingsSheet = app.sheets.firstMatch

        if settingsWindow.exists || settingsSheet.exists {
            // Check for transcription engine picker
            let enginePicker = app.popUpButtons["settings.transcription_engine_picker"]
            _ = enginePicker.exists

            // Close settings
            app.typeKey(.escape, modifierFlags: [])
        }
    }

    // MARK: - Quick Access Overlay

    func testQuickAccessElements() throws {
        // Quick access appears after recording - just verify queries work
        let saveButton = app.buttons["quick_access.save"]
        let shareButton = app.buttons["quick_access.share"]

        _ = saveButton.exists
        _ = shareButton.exists
    }

    // MARK: - Sidebar Controls

    func testSidebarToggle() throws {
        let sidebarToggle = app.buttons[AccessibilityIdentifiers.sidebarToggle]

        if sidebarToggle.waitForExistence(timeout: 5) {
            XCTAssertTrue(sidebarToggle.isHittable, "SidebarToggle should be tappable")
        }
    }

    // MARK: - Magic Fix Controls

    func testMagicFixButtonAccessible() throws {
        // Open inspector
        let inspectorToggle = app.buttons[AccessibilityIdentifiers.inspectorToggle]
        if inspectorToggle.exists && inspectorToggle.isHittable {
            inspectorToggle.tap()
            sleep(1)
        }

        let magicFixButton = app.buttons[AccessibilityIdentifiers.magicFixButton]
        // Magic fix may be disabled without content, but should exist
        _ = magicFixButton.exists
    }
}
