import XCTest

final class SaneVideoUITests: XCTestCase {
    
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    /*
    // DISABLED: Focus on Editor Testing for now.
    // Recorder testing is blocked by Sandbox/TCC issues.
    func testRecordingWorkflow() throws {
        let app = XCUIApplication()
        app.launchArguments.append("-uitesting")
        app.launch()
        
        // 1. Check for Onboarding
        let continueButton = app.buttons["ContinueButton"]
        if continueButton.exists {
            continueButton.tap()
        }
        
        // 2. Start Recording
        let recordButton = app.buttons["RecordButton"]
        XCTAssertTrue(recordButton.waitForExistence(timeout: 5), "Record button should appear")
        recordButton.tap()
        
        // 3. Stop Recording
        // Specific wait for the "Stop" state if needed, or just tap again after a delay
        sleep(2)
        recordButton.tap()
        
        // 4. Verify Transition to Editor
        // The "RecentClipButton" appears when a clip is recorded
        let recentClipButton = app.buttons["RecentClipButton"]
        XCTAssertTrue(recentClipButton.waitForExistence(timeout: 10), "Recent clip button should appear after recording")
    }
    */
    
    func testEditingWorkflow() throws {
        let app = XCUIApplication()
        // Direct-to-Editor Test Strategy
        app.launchArguments += ["-ui_testing", "YES", "-open_editor", "YES"]
        app.launchEnvironment.removeValue(forKey: "UI_TESTING") // Clear env to be sure
        app.launchEnvironment.removeValue(forKey: "OPEN_EDITOR")
        app.launch()
        
        // Wait for Editor to load (Mock video generation takes a moment)
        let splitButton = app.buttons["SplitClipButton"]
        XCTAssertTrue(splitButton.waitForExistence(timeout: 10), "Editor should load with Split button directly on launch")
        
        // Verify Editor UI elements are present
        XCTAssertTrue(app.buttons["DeleteClipButton"].exists, "Delete button should be visible")
    }
    
    func testExportWorkflow() throws {
        let app = XCUIApplication()
        // Use -uitesting to match MainContentView.isTesting check
        app.launchArguments = ["-uitesting", "-ui_testing", "YES", "-open_editor", "YES"]
        app.launch()
        
        // 1. Wait for "Edit" tab to be selected - proves we are in Editor Mode
        print("🔍 DEBUG: All Windows: \(app.windows.allElementsBoundByIndex.map { "'\($0.title)' (\($0.identifier)) - Visible: \($0.exists), hittable: \($0.isHittable)" })")
        
        let editTab = app.buttons["EditTabButton"]
        if !editTab.waitForExistence(timeout: 20) {
             print("❌ DEBUG: Edit tab button NOT FOUND. Window titles: \(app.windows.allElementsBoundByIndex.map { $0.title })")
             print("❌ DEBUG: Full UI Tree: \n\(app.debugDescription)")
             XCTFail("App should switch to Editor (EditTabButton visible)")
        }
        
        // 2. Wait for Export Button
        XCTAssertTrue(editTab.exists, "EditTabButton should be present")
        
        // 3. Wait for Export Button
        let exportButton = app.buttons["ExportButton"]
        if !exportButton.waitForExistence(timeout: 10) {
             print("❌ DEBUG: Export button not found. UI Tree: \n\(app.debugDescription)")
             XCTFail("Export button should be visible in Editor")
        }
        
        // 4. Wait for button to be enabled (currentProject is non-nil)
        let enabledPredicate = NSPredicate(format: "isEnabled == true")
        let expectation = XCTNSPredicateExpectation(predicate: enabledPredicate, object: exportButton)
        let result = XCTWaiter().wait(for: [expectation], timeout: 10)
        XCTAssertEqual(result, .completed, "Export button should be enabled after project loads")
        
        exportButton.tap()
        
        // Capture screenshot immediately after tap to see what's happening
        let postTapScreenshot = XCUIScreen.main.screenshot()
        let postTapAttachment = XCTAttachment(screenshot: postTapScreenshot)
        postTapAttachment.lifetime = .keepAlways
        postTapAttachment.name = "AfterExportTap"
        add(postTapAttachment)
        
        // 5. Wait for export sheet
        // Try multiple ways to find the sheet. On macOS/SwiftUI, it might not be a standard .sheets element.
        let exportSheet = app.descendants(matching: .any)["Export Sheet"]
        let sheetExists = exportSheet.waitForExistence(timeout: 15)
        
        if !sheetExists {
            print("❌ DEBUG: Export sheet (any descendant with identifier 'Export Sheet') not found.")
            print("🔍 DEBUG: All Windows: \(app.windows.allElementsBoundByIndex.map { "'\($0.title)' (\($0.identifier)) type: \($0.elementType.rawValue)" })")
            
            // Log all buttons to see if Close button is visible somewhere
            let allButtons = app.buttons.allElementsBoundByIndex
            print("🔍 DEBUG: All Visible Buttons Identifiers: \(allButtons.map { $0.identifier })")
            
            print("🔍 DEBUG: Full UI Tree: \n\(app.debugDescription)")
            
            let finalScreenshot = XCUIScreen.main.screenshot()
            let finalAttachment = XCTAttachment(screenshot: finalScreenshot)
            finalAttachment.lifetime = .keepAlways
            finalAttachment.name = "FinalFailureState_DeepSearch"
            add(finalAttachment)
        }
        
        XCTAssertTrue(sheetExists, "Export sheet should appear after tapping Export (Deep search)")
    }
}
