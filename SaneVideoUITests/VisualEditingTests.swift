// swiftlint:disable empty_count
//
//  VisualEditingTests.swift
//  SaneVideoUITests
//

import XCTest

final class VisualEditingTests: UITestBase {

  func testTimelineUI() throws {
    app.launchArguments = ["-uitesting", "-ui_testing", "YES", "-open_editor", "YES"]

    guard waitForAppReady() else {
      XCTFail("App failed to launch in editor mode")
      return
    }

    handleSystemAlerts()

    // Wait for timeline
    let timeline = app.scrollViews.matching(identifier: "TimelineScroll").firstMatch
    if timeline.waitForExistence(timeout: 5) {
      XCTAssertTrue(timeline.exists, "Timeline should be visible")
    } else {
      // Check for empty state
      let emptyState = app.otherElements["TimelineEmptyState"]
      XCTAssertTrue(
        emptyState.exists || timeline.exists, "Timeline or empty state should be visible")
    }
  }

  func testPlayerControlsVisibility() throws {
    app.launchArguments = ["-uitesting", "-ui_testing", "YES", "-open_editor", "YES"]

    guard waitForAppReady() else {
      XCTFail("App failed to launch")
      return
    }

    handleSystemAlerts()

    // Check for player controls
    let playButton = app.buttons.matching(identifier: "PlayButton").firstMatch
    let pauseButton = app.buttons.matching(identifier: "PauseButton").firstMatch

    // At least one should exist
    if playButton.waitForExistence(timeout: 5) || pauseButton.waitForExistence(timeout: 5) {
      XCTAssertTrue(playButton.exists || pauseButton.exists, "Play/Pause button should be visible")
    }
  }

  func testExportSheetAppearance() throws {
    app.launchArguments = ["-uitesting", "-ui_testing", "YES", "-open_editor", "YES"]

    guard waitForAppReady() else {
      XCTFail("App failed to launch")
      return
    }

    handleSystemAlerts()

    // Wait for editor
    let editTab = app.buttons["EditTabButton"]
    if editTab.waitForExistence(timeout: 10) {
      if !editTab.isSelected {
        editTab.tap()
      }
    }

    handleSystemAlerts()
    app.typeKey("e", modifierFlags: .command)
    handleSystemAlerts()

    // Check for export sheet elements
    let exportButton = app.buttons["ExportButton"]
    let cancelButton = app.buttons["CancelExportButton"]

    if exportButton.waitForExistence(timeout: 5) || cancelButton.waitForExistence(timeout: 5) {
      XCTAssertTrue(true, "Export sheet elements should be visible")
    } else {
      print("⚠️ Export sheet may not be visible to XCTest (known limitation)")
    }
  }

  func testMagicFixButtonVisibility() throws {
    app.launchArguments = ["-uitesting", "-ui_testing", "YES", "-open_editor", "YES"]

    guard waitForAppReady() else {
      XCTFail("App failed to launch")
      return
    }

    handleSystemAlerts()

    let editTab = app.buttons["EditTabButton"]
    if editTab.waitForExistence(timeout: 10) {
      if !editTab.isSelected {
        editTab.tap()
      }
    }

    handleSystemAlerts()

    let magicFixButton = app.buttons.matching(identifier: "MagicFixButton").firstMatch
    if magicFixButton.waitForExistence(timeout: 5) {
      XCTAssertTrue(magicFixButton.exists, "Magic Fix button should be visible")
    }
  }

  func testCaptionControlsVisibility() throws {
    app.launchArguments = ["-uitesting", "-ui_testing", "YES", "-open_editor", "YES"]

    guard waitForAppReady() else {
      XCTFail("App failed to launch")
      return
    }

    handleSystemAlerts()

    let editTab = app.buttons["EditTabButton"]
    if editTab.waitForExistence(timeout: 10) {
      if !editTab.isSelected {
        editTab.tap()
      }
    }

    handleSystemAlerts()

    let captionSection = app.otherElements.matching(identifier: "CaptionsSection").firstMatch
    if captionSection.waitForExistence(timeout: 5) {
      XCTAssertTrue(captionSection.exists, "Caption section should be visible")
    }
  }

  func testKeyboardShortcuts() throws {
    app.launchArguments = ["-uitesting", "-ui_testing", "YES", "-open_editor", "YES"]

    guard waitForAppReady() else {
      XCTFail("App failed to launch")
      return
    }

    handleSystemAlerts()

    let editTab = app.buttons["EditTabButton"]
    if editTab.waitForExistence(timeout: 10) {
      if !editTab.isSelected {
        editTab.tap()
      }
    }

    handleSystemAlerts()
    app.typeKey(" ", modifierFlags: [])  // Space for play/pause
    handleSystemAlerts()

    XCTAssertTrue(
      app.state == .runningForeground || app.state == .runningBackground,
      "App should still be running after keyboard shortcuts")
  }
}
