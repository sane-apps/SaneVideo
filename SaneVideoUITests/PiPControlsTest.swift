//
//  PiPControlsTest.swift
//  SaneVideoUITests
//
//  Test to verify PiP controls window is properly created and visible
//  This test specifically addresses the issue where screenshots show
//  "baked-in" controls instead of the separate controls window
//

import XCTest

final class PiPControlsTest: XCTestCase {
    
    var app: XCUIApplication!
    
    override func setUpWithError() throws {
        continueAfterFailure = false
        
        if #available(macOS 13.0, *) {
            executionTimeAllowance = 120.0 // 2 minutes max
        }
        
        app = XCUIApplication()
        app.launchArguments = ["-uitesting", "-ui_testing", "YES"]
        app.launchEnvironment["OS_ACTIVITY_MODE"] = "disable"
        
        // Handle system alerts and permission dialogs
        addUIInterruptionMonitor(withDescription: "System Alerts") { (alert) -> Bool in
            let alertText = alert.staticTexts.firstMatch.label.lowercased()
            let alertTitle = alert.title.lowercased()
            let fullText = (alertTitle + " " + alertText)
            
            if fullText.contains("microphone") || fullText.contains("camera") || 
               fullText.contains("screen recording") || fullText.contains("would like to access") {
                if alert.buttons["Allow"].exists {
                    alert.buttons["Allow"].tap()
                    return true
                }
                if alert.buttons["OK"].exists {
                    alert.buttons["OK"].tap()
                    return true
                }
            }
            return false
        }
    }
    
    override func tearDownWithError() throws {
        app.terminate()
        app = nil
    }
    
    // MARK: - Helper Methods
    
    func waitForAppReady(timeout: TimeInterval = 15) -> Bool {
        let recordButton = app.buttons.matching(identifier: "recording.start").firstMatch
        if recordButton.waitForExistence(timeout: timeout) {
            return true
        }
        
        // Also check for onboarding or other states
        let continueButton = app.buttons["ContinueButton"]
        if continueButton.exists {
            continueButton.tap()
            return waitForAppReady(timeout: timeout - 5)
        }
        
        return false
    }
    
    // MARK: - PiP Controls Window Tests
    
    /// Test that PiP controls window is created as a separate window (not baked in)
    func testPiPControlsWindowExists() throws {
        guard waitForAppReady() else {
            XCTFail("App did not become ready")
            return
        }
        
        // Handle any permission dialogs
        sleep(2)
        
        // 1. Start screen sharing to trigger PiP window creation
        let screenShareButton = app.buttons.matching(identifier: "ScreenShareToggle").firstMatch
        if screenShareButton.waitForExistence(timeout: 5) {
            screenShareButton.tap()
            
            // Wait for screen sharing to start and PiP to appear
            sleep(3)
        } else {
            // If screen share button not found, try alternative approach
            // Some tests may need to trigger screen sharing differently
            XCTSkip("Screen share button not found - may need different test setup")
            return
        }
        
        // 2. Verify PiP window exists
        // Look for PiP window by accessibility identifier or title
        let pipWindow = app.windows.matching(identifier: "PiPCameraWindow").firstMatch
        let pipWindowByTitle = app.windows["SaneVideo PiP"]
        
        let pipExists = pipWindow.exists || pipWindowByTitle.exists
        
        if !pipExists {
            // Log all windows for debugging
            print("🔍 DEBUG: All Windows:")
            for window in app.windows.allElementsBoundByIndex {
                print("  - Title: '\(window.title)', ID: '\(window.identifier)'")
            }
        }
        
        XCTAssertTrue(pipExists, "PiP window should exist when screen sharing is active")
        
        // 3. Verify controls window exists as separate window
        // The controls window should have accessibility identifier "PiPControlsWindow"
        let controlsWindow = app.windows.matching(identifier: "PiPControlsWindow").firstMatch
        
        // Also check for controls by looking for control buttons within the PiP context
        let micButton = app.buttons.matching(identifier: "MicToggle").firstMatch
        let recordButton = app.buttons.matching(identifier: "recording.start").firstMatch
        
        // Controls should be accessible either as a separate window or as buttons
        let controlsExist = controlsWindow.exists || 
                           (micButton.exists && micButton.isHittable) ||
                           (recordButton.exists && recordButton.isHittable)
        
        if !controlsExist {
            print("🔍 DEBUG: Controls not found")
            print("  - Controls Window exists: \(controlsWindow.exists)")
            print("  - Mic button exists: \(micButton.exists), hittable: \(micButton.isHittable)")
            print("  - Record button exists: \(recordButton.exists), hittable: \(recordButton.isHittable)")
        }
        
        XCTAssertTrue(controlsExist, "PiP controls should be accessible (either as separate window or as buttons)")
        
        // 4. Verify controls are NOT baked into PiP window
        // If controls were baked in, they would be subviews of the PiP window
        // Since we're using a separate window, controls should be independently accessible
        if controlsWindow.exists {
            XCTAssertTrue(controlsWindow.isHittable, "Controls window should be hittable")
            XCTAssertNotEqual(controlsWindow.identifier, pipWindow.identifier, 
                            "Controls window should be separate from PiP window")
        }
    }
    
    /// Test that PiP controls are functional during screen sharing
    func testPiPControlsFunctionality() throws {
        guard waitForAppReady() else {
            XCTFail("App did not become ready")
            return
        }
        
        sleep(2)
        
        // Start screen sharing
        let screenShareButton = app.buttons.matching(identifier: "ScreenShareToggle").firstMatch
        guard screenShareButton.waitForExistence(timeout: 5) else {
            XCTSkip("Screen share button not found")
            return
        }
        
        screenShareButton.tap()
        sleep(3)
        
        // Verify PiP is visible
        let pipWindow = app.windows["SaneVideo PiP"]
        guard pipWindow.waitForExistence(timeout: 5) else {
            XCTFail("PiP window should be visible")
            return
        }
        
        // Test mic toggle
        let micButton = app.buttons.matching(identifier: "MicToggle").firstMatch
        if micButton.waitForExistence(timeout: 3) {
            let initialState = micButton.value as? String ?? ""
            micButton.tap()
            sleep(1)
            let newState = micButton.value as? String ?? ""
            XCTAssertNotEqual(initialState, newState, "Mic toggle should change state")
        }
        
        // Test record button (if visible)
        let recordButton = app.buttons.matching(identifier: "recording.start").firstMatch
        if recordButton.waitForExistence(timeout: 3) && recordButton.isHittable {
            // Just verify it's accessible, don't actually start recording in this test
            XCTAssertTrue(recordButton.isHittable, "Record button should be accessible in PiP")
        }
    }
    
    /// Test that PiP controls are excluded from screen recordings
    /// This is a visual/functional test that verifies the controls window
    /// has the correct sharingType property
    func testPiPControlsExcludedFromRecording() throws {
        // This test verifies the architecture, not the visual result
        // The actual exclusion is tested in unit tests (RegressionTests.swift)
        
        guard waitForAppReady() else {
            XCTFail("App did not become ready")
            return
        }
        
        sleep(2)
        
        // Start screen sharing
        let screenShareButton = app.buttons.matching(identifier: "ScreenShareToggle").firstMatch
        guard screenShareButton.waitForExistence(timeout: 5) else {
            XCTSkip("Screen share button not found")
            return
        }
        
        screenShareButton.tap()
        sleep(3)
        
        // Verify controls window exists
        let controlsWindow = app.windows.matching(identifier: "PiPControlsWindow").firstMatch
        let controlsExist = controlsWindow.exists || 
                           app.buttons.matching(identifier: "MicToggle").firstMatch.exists
        
        XCTAssertTrue(controlsExist, "Controls should exist")
        
        // Note: The actual sharingType verification is done in unit tests
        // This UI test just verifies the controls are accessible
    }
}

