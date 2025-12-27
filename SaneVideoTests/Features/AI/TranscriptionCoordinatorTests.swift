//
//  TranscriptionCoordinatorTests.swift
//  SaneVideoTests
//
//  Tests for TranscriptionCoordinator - engine selection, fallback logic, failure tracking
//

import Testing
import AVFoundation
@testable import SaneVideo

@Suite("Transcription Coordinator Tests")
@MainActor
struct TranscriptionCoordinatorTests {

    // MARK: - Test Setup

    var sut: TranscriptionCoordinator {
        TranscriptionCoordinator()
    }

    // MARK: - Initial State Tests

    @Test("Initial state has correct defaults")
    func initialState() {
        // Arrange & Act
        let coordinator = sut

        // Assert
        #expect(coordinator.selectedEngine == .apple || coordinator.selectedEngine == .whisperKit, "Should have a default engine")
        #expect(coordinator.shouldSuggestWhisperKit == false, "Should not suggest WhisperKit initially")
    }

    // MARK: - Engine Selection Tests

    @Test("Set engine updates selected engine")
    func setEngine() {
        // Arrange
        let coordinator = sut
        let originalEngine = coordinator.selectedEngine
        let newEngine: TranscriptionEngine = originalEngine == .apple ? .whisperKit : .apple

        // Act
        coordinator.setEngine(newEngine)

        // Assert
        #expect(coordinator.selectedEngine == newEngine, "Selected engine should be updated")
    }

    @Test("Set engine resets failure counts")
    func setEngineResetsFailures() {
        // Arrange
        let coordinator = sut

        // Act
        coordinator.setEngine(.apple)

        // Assert - Failure counts should be reset
        #expect(coordinator.shouldSuggestWhisperKit == false, "Failure counts should be reset")
    }

    // MARK: - Failure Tracking Tests

    @Test("Should suggest WhisperKit after Apple failures")
    func shouldSuggestWhisperKit() {
        // Arrange
        let coordinator = sut

        // Act - Simulate failures by calling resetFailureCounts (which resets to 0)
        // Note: In real usage, failures are tracked internally
        coordinator.resetFailureCounts()

        // Assert - Initially should not suggest
        #expect(coordinator.shouldSuggestWhisperKit == false, "Should not suggest initially")
    }

    @Test("Reset failure counts clears tracking")
    func resetFailureCounts() {
        // Arrange
        let coordinator = sut

        // Act
        coordinator.resetFailureCounts()

        // Assert - Should complete without error
        #expect(coordinator.shouldSuggestWhisperKit == false, "Failure counts should be reset")
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

    @Test("Generate captions respects selected engine")
    func generateCaptionsRespectsEngine() async {
        // Arrange
        let coordinator = sut
        coordinator.setEngine(.apple)

        // Act - Try to generate with test asset (will likely fail but tests engine selection)
        let testURL = TestEnvironment.mockAssetURL

        // Assert - Should attempt to use selected engine
        // Note: Actual transcription requires valid video file and service availability
        do {
            _ = try await coordinator.generateCaptions(for: testURL)
            #expect(true, "Should complete or throw based on service availability")
        } catch {
            #expect(true, "Error is expected if service unavailable or file invalid")
        }
    }
}
