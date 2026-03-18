//
//  TestProgressReporter.swift
//  SaneVideoTests
//
//  Real-time progress reporting for tests
//  Shows which test is running and prevents "stuck" feeling
//

import Foundation
import XCTest

/// Reports test progress in real-time to help identify stuck tests
@MainActor
final class TestProgressReporter {
    static let shared = TestProgressReporter()
    
    private var startTime: Date?
    private var currentTestName: String?
    private var testCount = 0
    private var updateTimer: Timer?
    
    private init() {}
    
    /// Start monitoring a test
    func startTest(_ testName: String) {
        currentTestName = testName
        startTime = Date()
        testCount += 1

        print("🧪 [\(testCount)] Starting: \(testName) (0.0s)")

        // Start progress updates every 5 seconds
        updateTimer = Timer.scheduledTimer(withTimeInterval: 5.0, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.updateProgress()
            }
        }
    }
    
    /// End monitoring a test
    func endTest(_ testName: String, success: Bool) {
        updateTimer?.invalidate()
        updateTimer = nil
        
        let duration = startTime.map { Date().timeIntervalSince($0) } ?? 0
        let icon = success ? "✅" : "❌"
        print("\(icon) [\(testCount)] Completed: \(testName) (\(String(format: "%.1f", duration))s)")
        
        currentTestName = nil
        startTime = nil
    }
    
    /// Update progress (called by timer)
    private func updateProgress() {
        guard let testName = currentTestName,
              let start = startTime else { return }
        
        let elapsed = Date().timeIntervalSince(start)
        
        // Warn if test is taking too long
        if elapsed > 30 {
            print("⚠️  [\(testCount)] Still running: \(testName) (\(String(format: "%.1f", elapsed))s) - This may be stuck")
        } else {
            print("⏳ [\(testCount)] Running: \(testName) (\(String(format: "%.1f", elapsed))s)")
        }
    }
    
    /// Check if a test appears stuck
    func checkForStuckTest() -> Bool {
        guard let start = startTime else { return false }
        let elapsed = Date().timeIntervalSince(start)
        return elapsed > 60 // Consider stuck after 60 seconds
    }
}

/// XCTestCase extension for automatic progress reporting
extension XCTestCase {
    /// Report test start (call in setUp or test method)
    func reportTestStart() {
        let testName = String(describing: type(of: self)) + "." + name.replacingOccurrences(of: "test", with: "")
        Task { @MainActor in
            TestProgressReporter.shared.startTest(testName)
        }
    }
    
    /// Report test end (call in tearDown or test method)
    func reportTestEnd(success: Bool = true) {
        let testName = String(describing: type(of: self)) + "." + name.replacingOccurrences(of: "test", with: "")
        Task { @MainActor in
            TestProgressReporter.shared.endTest(testName, success: success)
        }
    }
}
