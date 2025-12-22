import XCTest

class SaneAccessibilityTests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = true
    }

    func testAccessibilityLabels() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-open_editor"] // Ensure populated UI
        app.launch()

        // Wait for UI to stabilize
        _ = app.windows.firstMatch.waitForExistence(timeout: 5)
        
        // Scan for buttons
        let buttons = app.buttons.allElementsBoundByIndex
        var issues = [String]()
        
        print("Starting Accessibility Audit on \(buttons.count) buttons...")
        
        for button in buttons {
            // Filter out system window controls and invalid frames
            let id = button.identifier
            if id.hasPrefix("_XCUI:") || button.frame.isEmpty || button.frame.size.width < 10 || button.frame.size.height < 10 {
                continue
            }
            
            if button.label.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                let frame = button.frame
                issues.append("Button missing label at \(frame) (ID: \(id.isEmpty ? "None" : id))")
            }
        }
        
        if !issues.isEmpty {
            let message = "Found \(issues.count) buttons without accessibility labels:\n" + issues.joined(separator: "\n")
            print(message)
            XCTFail(message)
        } else {
            print("Accessibility Audit Passed: All \(buttons.count) buttons have labels.")
        }
    }
}
