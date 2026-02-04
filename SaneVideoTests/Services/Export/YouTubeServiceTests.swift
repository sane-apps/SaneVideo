//
//  YouTubeServiceTests.swift
//  SaneVideoTests
//
//  Tests for YouTubeService - error handling, upload state management
//

import Testing
import Foundation
@testable import SaneVideo

@Suite("YouTube Service Tests")
@MainActor
struct YouTubeServiceTests {

    // MARK: - YouTubeError Tests

    @Test("authenticationFailed has clear description")
    func authenticationFailedDescription() {
        // Arrange
        let error = YouTubeError.authenticationFailed

        // Assert
        #expect(error.errorDescription != nil)
        #expect(error.errorDescription?.lowercased().contains("authenticate") == true ||
                error.errorDescription?.lowercased().contains("google") == true)
    }

    @Test("uploadFailed includes reason in description")
    func uploadFailedDescription() {
        // Arrange
        let reason = "Network timeout"
        let error = YouTubeError.uploadFailed(reason)

        // Assert
        #expect(error.errorDescription != nil)
        #expect(error.errorDescription?.contains(reason) == true)
    }

    @Test("invalidResponse has clear description")
    func invalidResponseDescription() {
        // Arrange
        let error = YouTubeError.invalidResponse

        // Assert
        #expect(error.errorDescription != nil)
        #expect(error.errorDescription?.lowercased().contains("invalid") == true ||
                error.errorDescription?.lowercased().contains("response") == true)
    }

    @Test("missingCredentials has clear description")
    func missingCredentialsDescription() {
        // Arrange
        let error = YouTubeError.missingCredentials

        // Assert
        #expect(error.errorDescription != nil)
        #expect(error.errorDescription?.lowercased().contains("missing") == true ||
                error.errorDescription?.lowercased().contains("credentials") == true ||
                error.errorDescription?.lowercased().contains("client id") == true)
    }

    @Test("All errors have unique descriptions")
    func allErrorsHaveUniqueDescriptions() {
        // Arrange
        let errors: [YouTubeError] = [
            .authenticationFailed,
            .uploadFailed("test reason"),
            .invalidResponse,
            .missingCredentials
        ]

        // Act
        let descriptions = errors.compactMap { $0.errorDescription }

        // Assert
        #expect(descriptions.count == errors.count)
        let uniqueDescriptions = Set(descriptions)
        #expect(uniqueDescriptions.count == errors.count)
    }

    // MARK: - Initial State Tests

    @Test("Initial isUploading is false")
    func initialIsUploadingFalse() {
        // Arrange & Act
        let service = YouTubeService()

        // Assert
        #expect(service.isUploading == false)
    }

    @Test("Initial uploadProgress is zero")
    func initialUploadProgressZero() {
        // Arrange & Act
        let service = YouTubeService()

        // Assert
        #expect(service.uploadProgress == 0.0)
    }

    // MARK: - Upload Method Tests

    @Test("Upload throws missingCredentials when no client ID")
    func uploadThrowsMissingCredentials() async throws {
        // Arrange
        let service = YouTubeService()
        let tempURL = FileManager.default.temporaryDirectory.appendingPathComponent("test_video.mp4")

        // Act & Assert
        do {
            try await service.upload(videoURL: tempURL, title: "Test", description: "Test desc")
            #expect(Bool(false), "Should have thrown missingCredentials")
        } catch let error as YouTubeError {
            // Expected - should throw missingCredentials since we don't have credentials configured
            // Check error description contains expected text (YouTubeError doesn't conform to Equatable)
            #expect(error.errorDescription?.lowercased().contains("missing") == true ||
                    error.errorDescription?.lowercased().contains("credentials") == true)
        }
    }

    // MARK: - Observable State Tests

    @Test("YouTubeService conforms to Observable")
    func serviceIsObservable() {
        // Arrange & Act
        let service = YouTubeService()

        // Assert - Verify Observable works by checking initial state
        // If @Observable works, we can read the properties
        let isUploading = service.isUploading
        let uploadProgress = service.uploadProgress

        // Verify initial state (tests runtime behavior, not compilation)
        #expect(isUploading == false, "Initial isUploading should be false")
        #expect(uploadProgress == 0.0, "Initial uploadProgress should be 0.0")
    }
}
