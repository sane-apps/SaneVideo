//
//  SanePerformanceTests.swift
//  SaneVideoUITests
//
//  Created by SaneVideo Refactor
//

import XCTest
@testable import SaneVideo

final class SanePerformanceTests: XCTestCase {

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    /// Measure main window responsiveness and infer launch speed
    func testTimelineScrollPerformance() throws {
        let app = XCUIApplication()
        let start = Date()
        app.launch()
        
        // Wait for timeline to appear
        let timeline = app.scrollViews.matching(identifier: "TimelineScroll").firstMatch
        if timeline.waitForExistence(timeout: 5) {
             timeline.swipeLeft()
             let duration = Date().timeIntervalSince(start)
             print("Startup + Interaction time: \(duration)s")
        } else {
             // Fallback for empty state if scrolling isn't available
             XCTAssertTrue(app.otherElements[AccessibilityIdentifiers.timelineEmptyState].exists)
        }
    }
}
