//
//  CancellationTests.swift
//  SaneVideoTests
//
//  Tests for cancellation support in long-running operations
//

import XCTest
import AVFoundation
@testable import SaneVideo

final class CancellationTests: XCTestCase {
    
    @MainActor
    func testProjectStateCancellation() async {
        let projectState = ProjectState()
        
        // Create a mock processing task
        let task = Task {
            try? await Task.sleep(nanoseconds: 1_000_000_000) // 1 second
        }
        
        // Store the task
        projectState.setProcessingTask(task)
        
        // Cancel it
        await projectState.cancelProcessing()
        
        // Verify state is reset
        XCTAssertFalse(projectState.isProcessing, "Processing should be false after cancellation")
        XCTAssertNil(projectState.processingStatus, "Status should be nil after cancellation")
        XCTAssertEqual(projectState.processingProgress, 0.0, "Progress should be 0 after cancellation")
        
        // Verify task is cancelled
        XCTAssertTrue(task.isCancelled, "Task should be cancelled")
    }
    
    @MainActor
    func testMagicFixTaskCancellation() async {
        let projectState = ProjectState()
        let testProject = VideoProject()
        projectState.currentProject = testProject
        
        // Test cancellation mechanism
        // Note: Full Magic Fix requires actual video file, so we test cancellation infrastructure
        let task = Task {
            try? await Task.sleep(nanoseconds: 500_000_000) // 0.5s
        }
        
        projectState.setProcessingTask(task)
        
        // Wait a moment
        try? await Task.sleep(nanoseconds: 50_000_000) // 50ms
        
        // Cancel
        await projectState.cancelProcessing()
        task.cancel()
        
        // Wait for cancellation to propagate
        try? await Task.sleep(nanoseconds: 100_000_000) // 100ms
        
        // Verify cancellation
        XCTAssertFalse(projectState.isProcessing, "Should not be processing after cancellation")
        XCTAssertTrue(task.isCancelled, "Task should be cancelled")
    }
    
    func testTaskCancellationPropagation() async {
        // Test that cancellation propagates through async operations
        let task = Task {
            do {
                try await Task.sleep(nanoseconds: 1_000_000_000)
                XCTFail("Task should have been cancelled")
            } catch is CancellationError {
                // Expected
            } catch {
                XCTFail("Unexpected error: \(error)")
            }
        }
        
        // Cancel immediately
        task.cancel()
        
        // Wait a bit
        try? await Task.sleep(nanoseconds: 100_000_000)
        
        XCTAssertTrue(task.isCancelled, "Task should be cancelled")
    }
}

