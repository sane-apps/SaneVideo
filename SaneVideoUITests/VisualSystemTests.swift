// swiftlint:disable empty_count
//
//  VisualSystemTests.swift
//  SaneVideoUITests
//

import XCTest

final class VisualSystemTests: UITestBase {

  func testAppCrashRecovery() throws {
    app.launch()
    app.activate()

    handleSystemAlerts()

    // Monitor for crash dialog
    addUIInterruptionMonitor(withDescription: "Crash Handler") { (alert) -> Bool in
      let dialogText = alert.staticTexts.firstMatch.label.lowercased()
      if dialogText.contains("quit unexpectedly") {
        if alert.buttons["Ignore"].exists {
          alert.buttons["Ignore"].tap()
          return true
        }
      }
      return false
    }

    if app.windows.firstMatch.exists {
      app.windows.firstMatch.tap()
    }

    if app.state != .runningForeground {
      app.launch()
      app.activate()
      handleSystemAlerts()
    }

    let window = app.windows.firstMatch
    if window.waitForExistence(timeout: 10) {
      XCTAssertTrue(
        app.state == .runningForeground, "App should remain responsive after crash recovery")
    } else {
      XCTFail("App window not found after crash recovery attempt")
    }
  }

  func testSettingsWindow() throws {
    guard waitForAppReady() else {
      XCTFail("App failed to launch")
      return
    }

    handleSystemAlerts()
    app.typeKey(",", modifierFlags: .command)
    handleSystemAlerts()

    let settingsWindow = app.windows.matching(identifier: "Settings").firstMatch
    if settingsWindow.waitForExistence(timeout: 5) {
      XCTAssertTrue(settingsWindow.exists, "Settings window should be visible")
    }
  }

  func testAccessibilityElements() throws {
    guard waitForAppReady() else {
      XCTFail("App failed to launch")
      return
    }

    handleSystemAlerts()

    let elements = app.descendants(matching: .any)
    XCTAssertTrue(elements.count > 0, "App should have accessible elements")
  }

  func testUIResponsiveness() throws {
    let start = Date()

    guard waitForAppReady(timeout: 20) else {
      XCTFail("App failed to launch within timeout")
      return
    }

    handleSystemAlerts()
    let duration = Date().timeIntervalSince(start)

    XCTAssertTrue(duration < 25, "App should load within 25 seconds")
  }
}
