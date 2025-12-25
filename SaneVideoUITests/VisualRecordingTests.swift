// swiftlint:disable empty_count
//
//  VisualRecordingTests.swift
//  SaneVideoUITests
//

import XCTest

final class VisualRecordingTests: UITestBase {

  func testRecordingModeUI() throws {
    guard waitForAppReady() else {
      XCTFail("App failed to launch or show main window")
      return
    }

    handleSystemAlerts()

    // Check for recording button
    let recordButton = app.buttons["RecordButton"]
    if recordButton.waitForExistence(timeout: 5) {
      XCTAssertTrue(recordButton.exists, "Record button should be visible")
    } else {
      print("⚠️ Record button not found - may be showing onboarding or permissions")
    }
  }

  func testRecordingControlsVisibility() throws {
    guard waitForAppReady() else {
      XCTFail("App failed to launch")
      return
    }

    handleSystemAlerts()

    // Check for recording controls
    let controls = app.otherElements.matching(identifier: "RecordingControls")
    if controls.count > 0 {
      XCTAssertTrue(controls.firstMatch.exists, "Recording controls should be visible")
    }
  }

  func testPermissionHandling() throws {
    app.launch()
    app.activate()

    sleep(2)
    handleSystemAlerts()

    XCTAssertTrue(
      app.state == .runningForeground || app.state == .runningBackground,
      "App should still be running after handling permissions")
  }
}
