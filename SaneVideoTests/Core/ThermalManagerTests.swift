//
//  ThermalManagerTests.swift
//  SaneVideoTests
//

import XCTest
@testable import SaneVideo

@MainActor
final class ThermalManagerTests: XCTestCase {
    func testPerformanceLevelMapping() {
        // Test mapping from ProcessInfo.ThermalState to PerformanceLevel using static methods
        XCTAssertEqual(ThermalManager.performanceLevel(for: .nominal), .high)
        XCTAssertEqual(ThermalManager.performanceLevel(for: .fair), .balanced)
        XCTAssertEqual(ThermalManager.performanceLevel(for: .serious), .throttled)
        XCTAssertEqual(ThermalManager.performanceLevel(for: .critical), .emergency)
    }
    
    func testIsThermalPressureHigh() {
        // Test high pressure thresholds using static methods
        XCTAssertFalse(ThermalManager.isThermalPressureHigh(for: .nominal))
        XCTAssertFalse(ThermalManager.isThermalPressureHigh(for: .fair))
        XCTAssertTrue(ThermalManager.isThermalPressureHigh(for: .serious))
        XCTAssertTrue(ThermalManager.isThermalPressureHigh(for: .critical))
    }
}
