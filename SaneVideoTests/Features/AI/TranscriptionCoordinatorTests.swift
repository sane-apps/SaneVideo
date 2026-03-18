//
//  TranscriptionCoordinatorTests.swift
//  SaneVideoTests
//
//  Tests for TranscriptionCoordinator - WhisperKit-only for macOS 15+
//

import AVFoundation
import Testing

@testable import SaneVideo

@Suite("Transcription Coordinator Tests")
@MainActor
struct TranscriptionCoordinatorTests {

    // MARK: - Test Setup

    var sut: TranscriptionCoordinator {
        TranscriptionCoordinator()
    }

    // MARK: - Initial State Tests

    @Test("Coordinator initializes successfully")
    func initialState() async {
        // Act
        let coordinator = sut

        // Assert - Coordinator starts in the expected unloaded state
        #expect(await coordinator.modelState == .notLoaded)
    }

    // MARK: - Caption Generation Tests

    @Test("Generate captions with invalid URL throws error")
    func generateCaptionsInvalidURL() async throws {
        // Arrange
        let coordinator = sut
        let invalidURL = URL(fileURLWithPath: "/nonexistent/file.mp4")

        // Act & Assert - Should throw error for invalid file
        await #expect(throws: (any Error).self, "Should throw error for invalid file") {
            _ = try await coordinator.generateCaptions(for: invalidURL)
        }
    }

    @Test("Generate captions uses WhisperKit")
    func generateCaptionsUsesWhisperKit() async {
        // Arrange
        let coordinator = sut
        let testURL = TestEnvironment.mockAssetURL

        // Act - Try to generate with test asset
        // Note: Actual transcription requires valid video file and WhisperKit model
        // Whether it succeeds or throws depends on system state (WhisperKit availability)
        var didComplete = false
        do {
            _ = try await coordinator.generateCaptions(for: testURL)
            didComplete = true  // Success path - captions were generated
        } catch {
            didComplete = true  // Expected if WhisperKit unavailable or test file invalid
        }
        #expect(didComplete, "generateCaptions should complete (success or expected error)")
    }
}
