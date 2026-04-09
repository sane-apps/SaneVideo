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

        let state = await coordinator.modelState
        #expect(state == .notLoaded, "Invalid input should fail before WhisperKit starts loading")
    }
}
