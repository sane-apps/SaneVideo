// swiftlint:disable empty_count
//
//  UITestBase.swift
//  SaneVideoUITests
//
//  Shared base class for UI tests
//

import XCTest

class UITestBase: XCTestCase {

  var app: XCUIApplication!

  override func setUpWithError() throws {
    continueAfterFailure = false

    // Set test timeout as requested by user - 5 minutes max per test
    executionTimeAllowance = 300.0

    app = XCUIApplication()
    app.launchArguments = ["-uitesting", "-ui_testing", "YES"]

    // Reduce noise, enable test logging
    app.launchEnvironment["OS_ACTIVITY_MODE"] = "disable"
    app.launchEnvironment["XCTestLogLevel"] = "1"

    // Global monitor for system alerts (macOS Tahoe/Sequoia)
    addUIInterruptionMonitor(withDescription: "System Alert") { (alert) -> Bool in
      let alertTitle = alert.title.lowercased()
      let alertText = alert.staticTexts.firstMatch.label.lowercased()
      let fullText = (alertTitle + " " + alertText)

      AppLogger.ui.info("Interruption Monitor caught: \(fullText)")

      // Generic handler for 'Allow', 'OK', 'Ignore'
      for buttonName in ["Allow", "OK", "Ignore", "Allow While Using App"] {
        let button = alert.buttons[buttonName]
        if button.exists {
          button.tap()
          return true
        }
      }
      return false
    }
  }

  override func tearDownWithError() throws {
    app?.terminate()
    app = nil
  }

  /// Handle any system alerts or permission dialogs that appear
  @discardableResult
  func handleSystemAlerts() -> Bool {
    // Give system a moment to present
    sleep(1)

    // Trigger interruption processing by interacting with the main window if it exists.
    // If it doesn't exist, we'll wait for app.launch() to handle initial attachment.
    if app.windows.firstMatch.exists {
      app.windows.firstMatch.tap()
    }
    return true
  }

  /// Wait for app to be ready, handling any permission dialogs.
  /// Increased timeout for reliability in slow test environments.
  func waitForAppReady(timeout: TimeInterval = 30) -> Bool {
    let startTime = Date()

    app.launch()
    app.activate()

    // Handle initial permission dialogs
    let alertTimeout: TimeInterval = 10
    let alertStart = Date()
    while Date().timeIntervalSince(alertStart) < alertTimeout {
      app.activate()
      handleSystemAlerts()
      if app.state == .runningForeground { break }
      sleep(1)
    }

    // Wait for main window or ANY identifying element
    // Check for window existence, but also check for app state
    let window =
      app.windows["MainWindow"].exists ? app.windows["MainWindow"] : app.windows.firstMatch
    let exists = window.waitForExistence(timeout: timeout)

    if !exists {
      let totalTime = Date().timeIntervalSince(startTime)
      NSLog(
        "⚠️ UITestBase: App window not found after \(totalTime)s. App state: \(app.state.rawValue)")

      // Diagnostic: List all windows found
      NSLog("📝 UITestBase Diagnostic: Window Count = \(app.windows.count)")
      for i in 0..<app.windows.count {
        let w = app.windows.element(boundBy: i)
        NSLog("📝 Window[\(i)]: '\(w.label)' (\(w.identifier)) - Visible: \(w.isHittable)")
      }
    }

    return exists
  }
}

// Minimal Logger mock for UI Tests (if needed by copied logic)
struct AppLogger {
  struct UI {
    func info(_ msg: String) { NSLog("📝 [UITEST] \(msg)") }
  }
  static let ui = UI()
}
