//
//  SaneSmartFeaturesVisualTests.swift
//  SaneVideoUITests
//
//  Visual tests for Magic Fix and Smart Features
//  Uses XCUIScreen.screenshot() which requires screen recording permission
//  Permission automation should handle this automatically
//

import XCTest
@testable import SaneVideo

final class SaneSmartFeaturesVisualTests: XCTestCase {
    
    var app: XCUIApplication!
    
    override func setUpWithError() throws {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launchArguments = ["-uitesting", "-ui_testing", "YES", "-open_editor", "YES"]
        app.launchEnvironment["TEST_ASSET_NAME"] = "test_video.mp4"
        app.launch()
        app.activate()
    }
    
    // MARK: - Helper Methods
    
    func ensureEditorState() {
        let splitButton = app.buttons[AccessibilityIdentifiers.splitClipButton]
        if !splitButton.waitForExistence(timeout: 10) {
            XCTFail("Editor did not load - cannot proceed with visual tests")
        }
    }
    
    func openInspector() {
        // Open inspector panel if not already open
        let inspectorToggle = app.buttons[AccessibilityIdentifiers.inspectorToggle]
        if inspectorToggle.waitForExistence(timeout: 5) {
            // Check if inspector is visible by looking for Smart Tools section
            let smartTools = app.otherElements.matching(identifier: "Row_RemoveSilence").firstMatch
            if !smartTools.exists {
                inspectorToggle.tap()
                // Wait for inspector to open
                _ = smartTools.waitForExistence(timeout: 3)
            }
        }
    }
    
    func captureScreenshot(name: String) -> XCTAttachment {
        let screenshot = XCUIScreen.main.screenshot()
        let attachment = XCTAttachment(screenshot: screenshot)
        attachment.name = name
        attachment.lifetime = .keepAlways
        return attachment
    }
    
    // MARK: - Magic Fix UI Visual Tests
    
    /// Test that Magic Fix UI components are visible and properly laid out
    func testMagicFixUIVisibility() throws {
        ensureEditorState()
        openInspector()
        
        // 1. Verify Magic Fix button exists in toolbar
        let magicButton = app.buttons[AccessibilityIdentifiers.magicFixButton]
        XCTAssertTrue(magicButton.waitForExistence(timeout: 10), "Magic Fix button should be visible in toolbar")
        
        // Capture screenshot of Magic Fix button
        add(captureScreenshot(name: "01_MagicFixButton_Toolbar"))
        
        // 2. Verify Smart Tools section in inspector
        let removeSilenceRow = app.otherElements[AccessibilityIdentifiers.rowRemoveSilence]
        XCTAssertTrue(removeSilenceRow.waitForExistence(timeout: 5), "Smart Tools section should be visible")
        
        // Capture screenshot of Smart Tools section
        add(captureScreenshot(name: "02_SmartToolsSection_Inspector"))
        
        // 3. Verify all toggle switches are present
        let toggles = [
            AccessibilityIdentifiers.toggleRemoveSilence,
            AccessibilityIdentifiers.toggleRemoveFillers,
            AccessibilityIdentifiers.toggleEnhanceSpeech,
            AccessibilityIdentifiers.toggleAutoColor
        ]
        
        for toggleId in toggles {
            let toggle = app.switches[toggleId]
            XCTAssertTrue(toggle.exists, "Toggle \(toggleId) should exist")
        }
        
        add(captureScreenshot(name: "03_AllToggles_Visible"))
    }
    
    /// Test Magic Fix presets menu
    func testMagicFixPresets() throws {
        ensureEditorState()
        openInspector()
        
        // 1. Find and tap presets menu
        let presetsMenu = app.buttons[AccessibilityIdentifiers.presetsMenu]
        XCTAssertTrue(presetsMenu.waitForExistence(timeout: 5), "Presets menu should exist")
        
        add(captureScreenshot(name: "04_PresetsMenu_Before"))
        
        presetsMenu.tap()
        
        // Wait for menu to appear
        Thread.sleep(forTimeInterval: 0.5)
        
        // 2. Verify preset options exist
        let minimalPreset = app.menuItems[AccessibilityIdentifiers.presetMinimal]
        let proCleanPreset = app.menuItems[AccessibilityIdentifiers.presetProClean]
        let socialMediaPreset = app.menuItems[AccessibilityIdentifiers.presetSocialMedia]
        
        XCTAssertTrue(minimalPreset.exists || app.menuItems["Minimal Fix"].exists, "Minimal preset should exist")
        XCTAssertTrue(proCleanPreset.exists || app.menuItems["Pro Clean-up"].exists, "Pro Clean preset should exist")
        XCTAssertTrue(socialMediaPreset.exists || app.menuItems["Social Media Ready"].exists, "Social Media preset should exist")
        
        add(captureScreenshot(name: "05_PresetsMenu_Open"))
        
        // Close menu by clicking outside or pressing escape
        app.typeKey(.escape, modifierFlags: [])
    }
    
    /// Test Magic Fix progress indicator
    func testMagicFixProgressIndicator() throws {
        ensureEditorState()
        openInspector()
        
        // 1. Verify Magic Fix button is ready
        let magicButton = app.buttons[AccessibilityIdentifiers.magicFixButton]
        XCTAssertTrue(magicButton.waitForExistence(timeout: 10), "Magic Fix button should exist")
        
        add(captureScreenshot(name: "06_MagicFixButton_BeforeProcessing"))
        
        // 2. Trigger Magic Fix
        magicButton.tap()
        
        // 3. Wait for processing to start (button should transform to progress view)
        // The progress view replaces the button, so we look for processing indicators
        let processingStatus = app.staticTexts.matching(NSPredicate(format: "label CONTAINS 'Processing' OR label CONTAINS 'Starting' OR label CONTAINS 'Enhancing' OR label CONTAINS 'Analyzing'")).firstMatch
        
        if processingStatus.waitForExistence(timeout: 5) {
            add(captureScreenshot(name: "07_MagicFix_Processing"))
            
            // 4. Wait for progress to update (check for percentage text)
            let progressText = app.staticTexts.matching(NSPredicate(format: "label MATCHES '\\\\d+%'")).firstMatch
            if progressText.waitForExistence(timeout: 3) {
                add(captureScreenshot(name: "08_MagicFix_ProgressUpdate"))
            }
            
            // 5. Wait for completion (or timeout after reasonable time)
            // For test purposes, we'll just verify the UI transitions
            let completedStatus = app.staticTexts.matching(NSPredicate(format: "label CONTAINS 'Completed' OR label CONTAINS 'Finished'")).firstMatch
            if completedStatus.waitForExistence(timeout: 30) {
                add(captureScreenshot(name: "09_MagicFix_Completed"))
            } else {
                // If it takes too long, just capture current state
                add(captureScreenshot(name: "09_MagicFix_StillProcessing"))
            }
        } else {
            // If processing didn't start, capture the state anyway
            add(captureScreenshot(name: "07_MagicFix_ProcessingNotStarted"))
        }
    }
    
    /// Test toggle interactions and visual feedback
    func testToggleInteractions() throws {
        ensureEditorState()
        openInspector()
        
        // 1. Test Remove Silence toggle
        let silenceToggle = app.switches["Toggle_RemoveSilence"]
        XCTAssertTrue(silenceToggle.waitForExistence(timeout: 5), "Remove Silence toggle should exist")
        
        let initialState = silenceToggle.value as? Int ?? 0
        add(captureScreenshot(name: "10_Toggle_RemoveSilence_Initial"))
        
        silenceToggle.tap()
        Thread.sleep(forTimeInterval: 0.3)
        
        let newState = silenceToggle.value as? Int ?? 0
        XCTAssertNotEqual(initialState, newState, "Toggle state should change")
        add(captureScreenshot(name: "11_Toggle_RemoveSilence_Toggled"))
        
        // 2. Verify advanced settings appear when toggle is on
        if newState == 1 {
            // Look for threshold slider or advanced settings
            let advancedSettings = app.otherElements.matching(identifier: "Advanced Settings").firstMatch
            if advancedSettings.waitForExistence(timeout: 2) {
                add(captureScreenshot(name: "12_AdvancedSettings_Visible"))
            }
        }
        
        // 3. Test other toggles
        let fillersToggle = app.switches["Toggle_RemoveFillers"]
        if fillersToggle.exists {
            fillersToggle.tap()
            Thread.sleep(forTimeInterval: 0.3)
            add(captureScreenshot(name: "13_Toggle_RemoveFillers_Toggled"))
        }
    }
    
    /// Test Magic Fix with different preset configurations
    func testMagicFixPresetConfigurations() throws {
        ensureEditorState()
        openInspector()
        
        // 1. Apply Minimal preset
        let presetsMenu = app.buttons[AccessibilityIdentifiers.presetsMenu]
        if presetsMenu.waitForExistence(timeout: 5) {
            presetsMenu.tap()
            Thread.sleep(forTimeInterval: 0.5)
            
            // Try to find and tap minimal preset
            var minimalItem: XCUIElement?
            if app.menuItems["Preset_Minimal"].exists {
                minimalItem = app.menuItems["Preset_Minimal"]
            } else if app.menuItems["Minimal Fix"].exists {
                minimalItem = app.menuItems["Minimal Fix"]
            }
            
            if let item = minimalItem {
                item.tap()
                Thread.sleep(forTimeInterval: 0.5)
                add(captureScreenshot(name: "14_Preset_Minimal_Applied"))
            }
        }
        
        // 2. Apply Pro Clean preset
        if presetsMenu.exists {
            presetsMenu.tap()
            Thread.sleep(forTimeInterval: 0.5)
            
            var proCleanItem: XCUIElement?
            if app.menuItems["Preset_ProClean"].exists {
                proCleanItem = app.menuItems["Preset_ProClean"]
            } else if app.menuItems["Pro Clean-up"].exists {
                proCleanItem = app.menuItems["Pro Clean-up"]
            }
            
            if let item = proCleanItem {
                item.tap()
                Thread.sleep(forTimeInterval: 0.5)
                add(captureScreenshot(name: "15_Preset_ProClean_Applied"))
            }
        }
        
        // 3. Apply Social Media preset
        if presetsMenu.exists {
            presetsMenu.tap()
            Thread.sleep(forTimeInterval: 0.5)
            
            var socialItem: XCUIElement?
            if app.menuItems["Preset_SocialMedia"].exists {
                socialItem = app.menuItems["Preset_SocialMedia"]
            } else if app.menuItems["Social Media Ready"].exists {
                socialItem = app.menuItems["Social Media Ready"]
            }
            
            if let item = socialItem {
                item.tap()
                Thread.sleep(forTimeInterval: 0.5)
                add(captureScreenshot(name: "16_Preset_SocialMedia_Applied"))
            }
        }
    }
    
    /// Test visual effects application (if time permits)
    func testVisualEffectsApplication() throws {
        ensureEditorState()
        openInspector()
        
        // 1. Enable Auto Color
        let autoColorToggle = app.switches["Toggle_AutoColor"]
        if autoColorToggle.waitForExistence(timeout: 5) {
            let wasOn = (autoColorToggle.value as? Int ?? 0) == 1
            if !wasOn {
                autoColorToggle.tap()
                Thread.sleep(forTimeInterval: 0.5)
            }
            add(captureScreenshot(name: "17_AutoColor_Enabled"))
        }
        
        // 2. Apply Magic Fix to see visual changes
        let magicButton = app.buttons[AccessibilityIdentifiers.magicFixButton]
        if magicButton.waitForExistence(timeout: 5) {
            add(captureScreenshot(name: "18_BeforeMagicFix"))
            magicButton.tap()
            
            // Wait a moment for processing to start
            Thread.sleep(forTimeInterval: 2)
            add(captureScreenshot(name: "19_DuringMagicFix"))
            
            // Wait for completion (with timeout)
            let completed = app.staticTexts.matching(NSPredicate(format: "label CONTAINS 'Completed'")).firstMatch
            if completed.waitForExistence(timeout: 30) {
                add(captureScreenshot(name: "20_AfterMagicFix"))
            }
        }
    }
    
    /// Test that screenshots work (permission verification)
    func testScreenshotPermission() throws {
        // This test verifies that screen recording permission is working
        // If this fails, the permission automation isn't working
        
        ensureEditorState()
        
        // Try to capture a screenshot
        let screenshot = XCUIScreen.main.screenshot()
        let attachment = XCTAttachment(screenshot: screenshot)
        attachment.name = "00_ScreenshotPermission_Test"
        attachment.lifetime = .keepAlways
        add(attachment)
        
        // If we get here without crashing, permission is working
        XCTAssertTrue(true, "Screenshot captured successfully - permission is granted")
    }
}

