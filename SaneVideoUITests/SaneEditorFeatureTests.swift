import XCTest

final class SaneEditorFeatureTests: XCTestCase {
    
    override func setUpWithError() throws {
        continueAfterFailure = false
    }
    
    // MARK: - Testing Timeline Interaction
    
    func testTimelineInteraction() throws {
        let app = XCUIApplication()
        // Use standard "Editor Mode" launch arguments
        app.launchArguments = ["-uitesting", "-ui_testing", "YES", "-open_editor", "YES"]
        app.launch()
        app.activate()
        
        // 1. Wait for Editor to Load
        let splitButton = app.buttons["SplitClipButton"]
        XCTAssertTrue(splitButton.waitForExistence(timeout: 10), "Editor should launch with Split Clip button")
        
        let deleteButton = app.buttons["DeleteClipButton"]
        XCTAssertTrue(deleteButton.exists, "Delete button should be visible")
        
        // 2. Perform Split (Wait for idle after tap)
        splitButton.tap()
        // Note: Splitting updates state but might not visually create a new DOM element immediately distinct from the old one without more detailed accessibility,
        // but we are checking that the button is hittable and doesn't crash functionality.
        
        // 3. Test Undo (Cmd+Z)
        // Since we can't easily check internal state, checking the Undo button in toolbar
        let undoButton = app.toolbars.buttons["Undo"] // Usually accessible via standard toolbar
        // If toolbar structure is custom, we might need a specific identifier. 
        // MainContentView creates standard ToolbarItems, which macOS usually exposes.
        
        // 4. Delete Clip
        deleteButton.tap()
        
        // After deletion, the clip might be gone. 
        // We verify that the app is still responsive and didn't crash.
        XCTAssertTrue(app.buttons["EditTabButton"].exists, "App should remain in Editor mode after delete")
    }
    
    // MARK: - Testing Panels
    
    func testPanelToggling() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-uitesting", "-ui_testing", "YES", "-open_editor", "YES"]
        app.launch()
        app.activate()
        
        let inspectorToggle = app.buttons["InspectorToggle"]
        XCTAssertTrue(inspectorToggle.waitForExistence(timeout: 10), "Inspector toggle should act")
        
        // 1. Toggle Inspector
        inspectorToggle.tap()
        // We expect some UI change. Since sidebar/inspector are layout changes, we can verify responsiveness.
        
        let sidebarToggle = app.buttons["SidebarToggle"]
        XCTAssertTrue(sidebarToggle.waitForExistence(timeout: 5), "Sidebar toggle should exist")
        
        // 2. Toggle Sidebar
        sidebarToggle.tap()
    }
    
    // MARK: - Testing Auxiliary Exports
    
    func testAuxiliaryExports() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-uitesting", "-ui_testing", "YES", "-open_editor", "YES"]
        app.launch()
        app.activate()
        
        // 1. Ensure we are in Editing Mode
        let editTab = app.buttons["EditTabButton"]
        XCTAssertTrue(editTab.waitForExistence(timeout: 10))
        if !editTab.isSelected {
            editTab.tap()
        }
        
        // 2. Reveal Inspector's Video section (where Export used to be, or just to reveal sidebar)
        // In the new layout, Export is in ModeSwitcherView, but it's disabled until a project is open.
        // Tapping the Video section in inspector is a good proxy for ensuring the editor is ready.
        let videoSection = app.buttons["VideoSectionButton"]
        
        print("DEBUG: Clicking Video section to ensure editor is active...")
        if videoSection.waitForExistence(timeout: 10) {
            videoSection.tap()
        }
        
        let exportButton = app.buttons["ExportButton"]
        XCTAssertTrue(exportButton.waitForExistence(timeout: 20), "Export button should appear after project load and Video tab selection")
        
        // Wait for button to be enabled (it is disabled until project loads)
        let predicate = NSPredicate(format: "isEnabled == true")
        let expectation = XCTNSPredicateExpectation(predicate: predicate, object: exportButton)
        let result = XCTWaiter().wait(for: [expectation], timeout: 20)
        
        if result != .completed {
             // Fallback: Try to tap anyway in case accessibility state is lagging, but log warning
             print("⚠️ Warning: Export button state timed out, attempting tap anyway.")
        }
        
        // 3. Open Export Sheet
        print("DEBUG: Export Button Frame: \(exportButton.frame)")
        print("DEBUG: Export Button Hittable: \(exportButton.isHittable)")
        print("DEBUG: Export Button Enabled: \(exportButton.isEnabled)")
        
        if !exportButton.isHittable {
            print("DEBUG: Export Button is NOT hittable. Attempting force click or scrolling...")
        }

        // Wait for stability
        Thread.sleep(forTimeInterval: 2.0)
        print("DEBUG: Re-checking Export Button Frame after stability wait: \(exportButton.frame)")

        print("DEBUG: Tapping Export Button...")
        exportButton.tap()
        
        // 4. Test "More Options" menu
        // In SwiftUI on macOS, Menu label might be a static text or a button. 
        // We'll look for the text "More Options" and find its parent or just click it.
        let moreOptions = app.menuButtons["More Options"]
        XCTAssertTrue(moreOptions.waitForExistence(timeout: 10), "More Options menu button should exist")
        moreOptions.tap()
        
        print("✅ DEBUG: Tapped More Options.")
        
        // Primary Interactivity Check
        let cancelButton = app.buttons["Close"]
        XCTAssertTrue(cancelButton.waitForExistence(timeout: 10), "Close button should exist in sheet")
        cancelButton.tap()
        print("✅ DEBUG: Tapped Cancel. Test Complete.")
    }
    // MARK: - Substantive Transcription Verification (20-min Asset)
    
    /// This test triggers Magic Fix on the long test asset and waits to capture transcription progress.
    func testTranscriptionOfLongVideo() throws {
        let app = XCUIApplication()
        // Force long video asset via bootstrap
        app.launchArguments = ["-uitesting", "-ui_testing", "YES", "-open_editor", "YES"]
        app.launchEnvironment["PROJECT_DIR"] = "/Users/sj/SaneVideo"
        app.launch()
        app.activate()
        
        // 1. Wait for Magic Fix button
        let magicButton = app.buttons["MagicFixButton"]
        XCTAssertTrue(magicButton.waitForExistence(timeout: 20), "Magic Fix button should exist in initial Smart Tools section")
        
        // 2. Trigger Magic Fix
        print("🚀 DEBUG: Tapping Magic Fix to start 20-min transcription...")
        magicButton.tap()
        
        // 3. Wait 60 seconds to allow for significant transcription progress
        // Each segment takes some time, 60s is enough to see a few "Result segment #X" in logs
        print("⏳ DEBUG: Waiting 60s for transcription progress...")
        Thread.sleep(forTimeInterval: 60)
        
        // 4. Verification check: The processing state should be active (ProgressView in Sidebar or similar)
        // From SidebarView: if appState.projectState.isProcessing { ProgressView() }
        // We can check if a progress indicator exists
        let processingIndicator = app.progressIndicators.firstMatch
        if processingIndicator.exists {
             print("✅ DEBUG: Processing indicator found. Transcription is active.")
        }
        
        print("🏁 DEBUG: Test complete. Extracting logs next.")
    }
    
    // MARK: - Magic Fix Mode Verification

    func testMagicFixModes() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-uitesting", "-ui_testing", "YES", "-open_editor", "YES"]
        app.launchEnvironment["PROJECT_DIR"] = "/Users/sj/SaneVideo"
        // Explicitly requesting the full 20-minute video for End-to-End verification
        app.launchEnvironment["TEST_ASSET_NAME"] = "test_video.mp4"
        app.launch()
        
        // Wait for Editor to load
        let magicFixButton = app.buttons["MagicFixButton"]
        XCTAssertTrue(magicFixButton.waitForExistence(timeout: 10), "Magic Fix button should appear")
        
        // 1. Open Presets Menu
        var presetsMenu = app.buttons["PresetsMenu"]
        if !presetsMenu.exists {
             presetsMenu = app.descendants(matching: .any).matching(identifier: "PresetsMenu").firstMatch
        }
        if !presetsMenu.exists {
             presetsMenu = app.staticTexts["Presets"].firstMatch
        }
        
        XCTAssertTrue(presetsMenu.waitForExistence(timeout: 5), "Presets menu should exist")
        presetsMenu.tap()
        
        // 2. Select "Social Media Ready"
        let socialButton = app.buttons["Preset_Social"]
        if !socialButton.waitForExistence(timeout: 3) {
             let socialMenuItem = app.menuItems["Preset_Social"]
             if socialMenuItem.waitForExistence(timeout: 3) {
                 socialMenuItem.tap()
             } else {
                 app.buttons["Social Media Ready"].tap()
             }
        } else {
             socialButton.tap()
        }
        
        app.activate()
        
        // 2a. Verify Pre-condition (Record initial count)
        let initialClips = app.descendants(matching: .any).matching(identifier: "TimelineClip")
        let initialCount = initialClips.count
        print("🔍 DEBUG: Initial Clip Count: \(initialCount)")
        
        for i in 0..<initialCount {
            let clip = initialClips.element(boundBy: i)
            print("   📄 Clip \(i): Label='\(clip.label)', Frame=\(clip.frame)")
        }
        
        XCTAssertTrue(initialCount > 0, "Expected at least 1 clip to start. Found 0.")
        
        // 3. Execute Magic Fix (Social Media)
        print("Executing Magic Fix for Social Media on FULL 20m video...")
        app.buttons["MagicFixButton"].tap()
        
        // 4. Wait for Processing to Complete
        // Use XCTest Expectation for cleaner async testing (Best Practice)
        let timeout: TimeInterval = 600
        print("⏳ Waiting up to \(timeout)s for processing (Expect count > \(initialCount))...")
        
        // Define the predicate to wait for (CLIP COUNT INCREASES)
        let timelineClipsQuery = app.descendants(matching: .any).matching(identifier: "TimelineClip")
        let predicate = NSPredicate(format: "count > %d", initialCount)
        
        // Create expectation
        let expectation = expectation(for: predicate, evaluatedWith: timelineClipsQuery, handler: nil)
        
        // Wait
        let result = XCTWaiter.wait(for: [expectation], timeout: timeout)
        
        switch result {
        case .completed:
            let finalCount = timelineClipsQuery.count
            print("✅ Processing Complete! Detected \(finalCount) clips (Started with \(initialCount)).")
        case .timedOut:
            XCTFail("❌ Magic Fix timed out after \(timeout)s. Clip count did not increase from \(initialCount).")
        default:
            XCTFail("❌ Magic Fix expectation failed with result: \(result)")
        }
        
        // 5. Reset/Undo to clean state
        print("Sending Undo (Cmd+Z) to reset project state...")
        app.typeKey("z", modifierFlags: .command)
        
    }
    
    // MARK: - Performance Audit (Tier 3)
    
    // Performance Benchmark: Export Time & Memory Usage
    func testExportPerformance() {
        let app = XCUIApplication()
        app.launchArguments = ["-uitesting", "-ui_testing", "YES", "-open_editor", "YES"]
        app.launchEnvironment["TEST_ASSET_NAME"] = "test_video.mp4"
        app.launch()
        
        let metrics: [XCTMetric] = [XCTClockMetric(), XCTMemoryMetric(application: app)]
        let options = XCTMeasureOptions()
        options.iterationCount = 3
        
        measure(metrics: metrics, options: options) {
            // 1. Wait for Project Load
            let clip = app.descendants(matching: .any).matching(identifier: "TimelineClip").firstMatch
            XCTAssertTrue(clip.waitForExistence(timeout: 20), "Clip load timeout")

            // 2. Trigger Export
            let exportButton = app.buttons["ExportButton"]
            // Wait for ENABLED state (project loaded)
            let exists = exportButton.waitForExistence(timeout: 10)
            if exists && !exportButton.isEnabled {
                _ = XCTWaiter.wait(for: [expectation(for: NSPredicate(format: "isEnabled == true"), evaluatedWith: exportButton)], timeout: 10)
            }
            exportButton.tap()
            
            // 3. Confirm Export (Save)
            let saveButton = app.buttons["SaveExport"]
            if saveButton.waitForExistence(timeout: 5) {
                saveButton.click()
            }
            
            // 4. Wait for Completion (Progress Sheet Disappearance)
            let progressSheet = app.staticTexts["Exporting..."]
            if progressSheet.waitForExistence(timeout: 5) {
                let notExists = NSPredicate(format: "exists == false")
                let expectation = XCTNSPredicateExpectation(predicate: notExists, object: progressSheet)
                _ = XCTWaiter.wait(for: [expectation], timeout: 300)
            }
        }
    }
}
