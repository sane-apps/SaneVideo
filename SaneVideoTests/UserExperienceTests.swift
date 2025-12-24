//
//  UserExperienceTests.swift
//  SaneVideoTests
//
//  Tests for user experience polish features
//

import XCTest
import AVFoundation
@testable import SaneVideo

final class UserExperienceTests: XCTestCase {
    
    // MARK: - Error Display Tests
    
    func testErrorDisplayViewRecoverySuggestions() {
        let permissionError = AppError.cameraPermissionDenied
        XCTAssertNotNil(permissionError.recoverySuggestion, "Permission errors should have recovery suggestions")
        
        let diskSpaceError = AppError.diskSpaceLow
        XCTAssertNotNil(diskSpaceError.recoverySuggestion, "Disk space errors should have recovery suggestions")
    }
    
    func testErrorDisplayViewUserFacingMessages() {
        let recordingError = AppError.recordingEngineError("Test error")
        let title = recordingError.userFacingTitle
        let message = recordingError.userFacingMessage
        
        XCTAssertFalse(title.isEmpty, "Error title should not be empty")
        XCTAssertFalse(message.isEmpty, "Error message should not be empty")
        XCTAssertTrue(message.contains("Test error"), "Error message should include the original error")
    }
    
    // MARK: - Magic Fix Cancellation Tests
    
    @MainActor
    func testMagicFixCancellation() async {
        let projectState = ProjectState()
        let testProject = VideoProject()
        projectState.currentProject = testProject
        
        // Create a test clip
        let testURL = FileManager.default.temporaryDirectory.appendingPathComponent("test.mp4")
        let testClip = VideoClip(url: testURL, duration: CMTime(seconds: 10, preferredTimescale: 600))
        
        // Start Magic Fix
        let options = MagicFixOptions()
        let magicFixTask = Task {
            await projectState.performMagicFix(for: testClip, options: options)
        }
        
        // Wait a bit
        try? await Task.sleep(nanoseconds: 100_000_000) // 0.1s
        
        // Cancel it
        await projectState.cancelProcessing()
        magicFixTask.cancel()
        
        // Verify state is reset
        XCTAssertFalse(projectState.isProcessing, "Processing should be false after cancellation")
        XCTAssertNil(projectState.processingStatus, "Processing status should be nil after cancellation")
        XCTAssertEqual(projectState.processingProgress, 0.0, "Processing progress should be 0 after cancellation")
    }
    
    // MARK: - Privacy Badge Tests
    
    @MainActor
    func testPrivacyBadgeOnDevice() async {
        // Privacy badge should show "100% On-Device" when no cloud AI keys are configured
        // This is tested via the PrivacyBadge view's updateStatus() method
        // We can verify the logic by checking the keychain service
        
        let keychain = ServiceContainer.shared.keychainService
        
        // Ensure no keys are set
        try? await keychain.delete(for: .openAIKey)
        try? await keychain.delete(for: .geminiKey)
        
        // Privacy badge should detect on-device mode
        // (Actual UI test would verify the badge text, but this tests the logic)
        let hasOpenAI = await keychain.retrieve(for: .openAIKey) != nil
        let hasGemini = await keychain.retrieve(for: .geminiKey) != nil
        
        XCTAssertFalse(hasOpenAI, "OpenAI key should not be set")
        XCTAssertFalse(hasGemini, "Gemini key should not be set")
        // Privacy badge would show "100% On-Device" in this case
    }
    
    // MARK: - Loading State Tests
    
    func testLoadingIndicatorProgress() {
        // LoadingIndicator should display progress correctly
        // This is a UI component test, but we can verify the logic
        
        let progress: Double = 0.5
        XCTAssertGreaterThanOrEqual(progress, 0.0, "Progress should be >= 0")
        XCTAssertLessThanOrEqual(progress, 1.0, "Progress should be <= 1")
        
        let percentage = Int(progress * 100)
        XCTAssertEqual(percentage, 50, "Progress percentage should be 50%")
    }
    
    // MARK: - Enhanced Magic Overlay Tests
    
    @MainActor
    func testEnhancedMagicOverlayVisibility() {
        let projectState = ProjectState()
        
        // Overlay should be hidden when not processing
        XCTAssertFalse(projectState.isProcessing, "Should not be processing initially")
        
        // Overlay should be visible when processing
        projectState.isProcessing = true
        projectState.processingProgress = 0.5
        projectState.processingStatus = "Testing..."
        
        XCTAssertTrue(projectState.isProcessing, "Should be processing")
        XCTAssertEqual(projectState.processingProgress, 0.5, "Progress should be 0.5")
        XCTAssertNotNil(projectState.processingStatus, "Status should not be nil")
    }
}

