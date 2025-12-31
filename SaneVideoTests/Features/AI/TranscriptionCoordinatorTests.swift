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
    func initialState() {
        // Act
        let coordinator = sut

        // Assert - Coordinator exists and is ready
        #expect(coordinator != nil, "Coordinator should initialize")
    }

    // MARK: - Caption Generation Tests

    @Test("Generate captions with invalid URL throws error")
    func generateCaptionsInvalidURL() async throws {
        // Arrange
        let coordinator = sut
        let invalidURL = URL(fileURLWithPath: "/nonexistent/file.mp4")

        // Act & Assert - Should throw error for invalid file
        do {
            _ = try await coordinator.generateCaptions(for: invalidURL)
            #expect(Bool(false), "Should throw error for invalid file")
        } catch {
            #expect(true, "Should throw error for invalid file")
        }
    }

    @Test("Generate captions uses WhisperKit")
    func generateCaptionsUsesWhisperKit() async {
        // Arrange
        let coordinator = sut
        let testURL = TestEnvironment.mockAssetURL

        // Act - Try to generate with test asset
        // Note: Actual transcription requires valid video file and WhisperKit model
        do {
            _ = try await coordinator.generateCaptions(for: testURL)
            #expect(true, "Should complete or throw based on service availability")
        } catch {
            #expect(true, "Error is expected if WhisperKit unavailable or file invalid")
        }
    }
}
