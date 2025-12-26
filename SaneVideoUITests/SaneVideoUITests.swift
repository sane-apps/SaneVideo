import XCTest
@testable import SaneVideo

final class SaneVideoUITests: XCTestCase {
    
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    func testEditingWorkflow() throws {
        let app = XCUIApplication()
        // Direct-to-Editor Test Strategy
        app.launchArguments += ["-ui_testing", "YES", "-open_editor", "YES"]
        app.launchEnvironment.removeValue(forKey: "UI_TESTING") // Clear env to be sure
        app.launchEnvironment.removeValue(forKey: "OPEN_EDITOR")
        app.launch()
        
        // Wait for Editor to load (Mock video generation takes a moment)
        let splitButton = app.buttons[AccessibilityIdentifiers.splitClipButton]
        XCTAssertTrue(splitButton.waitForExistence(timeout: 10), "Editor should load with Split button directly on launch")
        
        // Verify Editor UI elements are present
        XCTAssertTrue(app.buttons[AccessibilityIdentifiers.deleteClipButton].exists, "Delete button should be visible")
    }
    
    func testExportWorkflow() throws {
        let app = XCUIApplication()
        // Use -uitesting to match MainContentView.isTesting check
        app.launchArguments = ["-uitesting", "-ui_testing", "YES", "-open_editor", "YES"]
        app.launch()
        
        // 1. Wait for mode switcher - proves we are in Editor Mode
        // CRITICAL FIX: EditTabButton no longer exists, use ModeSwitcherButton
        print("🔍 DEBUG: All Windows: \(app.windows.allElementsBoundByIndex.map { "'\($0.title)' (\($0.identifier)) - Visible: \($0.exists), hittable: \($0.isHittable)" })")
        
        let modeSwitcher = app.buttons[AccessibilityIdentifiers.modeSwitcher]
        if !modeSwitcher.waitForExistence(timeout: 20) {
             print("❌ DEBUG: Mode switcher button NOT FOUND. Window titles: \(app.windows.allElementsBoundByIndex.map { $0.title })")
             print("❌ DEBUG: Full UI Tree: \n\(app.debugDescription)")
             XCTFail("App should have mode switcher button visible")
        }
        
        // 2. Verify we're in editing mode (button should say "Record" when in editing mode)
        XCTAssertTrue(modeSwitcher.exists, "ModeSwitcherButton should be present")
        // In editing mode, button label says "Record" (to switch back to recording)
        let buttonLabel = modeSwitcher.label
        XCTAssertTrue(buttonLabel.contains("Record") || buttonLabel.contains("Editor"), "Mode switcher should show current mode")
        
        // 3. Wait for Export Button
        let exportButton = app.buttons[AccessibilityIdentifiers.exportButton]
        if !exportButton.waitForExistence(timeout: 10) {
             print("❌ DEBUG: Export button not found. UI Tree: \n\(app.debugDescription)")
             XCTFail("Export button should be visible in Editor")
        }
        
        // 4. Wait for button to be enabled (currentProject is non-nil)
        let enabledPredicate = NSPredicate(format: "isEnabled == true")
        let expectation = XCTNSPredicateExpectation(predicate: enabledPredicate, object: exportButton)
        let result = XCTWaiter().wait(for: [expectation], timeout: 10)
        XCTAssertEqual(result, XCTWaiter.Result.completed, "Export button should be enabled after project loads")
        
        exportButton.tap()
        
        // Capture screenshot immediately after tap to see what's happening
        let postTapScreenshot = XCUIScreen.main.screenshot()
        let postTapAttachment = XCTAttachment(screenshot: postTapScreenshot)
        postTapAttachment.lifetime = .keepAlways
        postTapAttachment.name = "AfterExportTap"
        add(postTapAttachment)
        
        // 5. Wait for export sheet
        // Try multiple ways to find the sheet. On macOS/SwiftUI, it might not be a standard .sheets element.
        let exportSheet = app.descendants(matching: .any)[AccessibilityIdentifiers.exportSheet]
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
