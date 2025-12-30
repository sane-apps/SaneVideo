//
//  KeychainServiceTests.swift
//  SaneVideoTests
//
//  Tests for KeychainService - secure credential storage
//

import Testing
import Foundation
@testable import SaneVideo

@Suite("Keychain Service Tests")
struct KeychainServiceTests {

    // MARK: - KeychainKey Tests

    @Test("KeychainKey has correct raw values")
    func keychainKeyRawValues() {
        // Assert
        #expect(KeychainService.KeychainKey.youtubeClientID.rawValue == "youtube_client_id")
        #expect(KeychainService.KeychainKey.youtubeClientSecret.rawValue == "youtube_client_secret")
        #expect(KeychainService.KeychainKey.youtubeRefreshToken.rawValue == "youtube_refresh_token")
    }

    @Test("KeychainKey displayName is human readable")
    func keychainKeyDisplayNames() {
        // Assert
        #expect(KeychainService.KeychainKey.youtubeClientID.displayName.contains("YouTube"))
        #expect(KeychainService.KeychainKey.youtubeClientSecret.displayName.contains("Secret"))
        #expect(KeychainService.KeychainKey.youtubeRefreshToken.displayName.contains("Token"))
    }

    @Test("KeychainKey allCases contains all keys")
    func keychainKeyAllCases() {
        // Arrange
        let allKeys = KeychainService.KeychainKey.allCases

        // Assert
        #expect(allKeys.count == 3)
        #expect(allKeys.contains(.youtubeClientID))
        #expect(allKeys.contains(.youtubeClientSecret))
        #expect(allKeys.contains(.youtubeRefreshToken))
    }

    // MARK: - KeychainError Tests

    @Test("saveFailed error has description")
    func saveFailedErrorDescription() {
        // Arrange
        let error = KeychainService.KeychainError.saveFailed(-25299) // errSecDuplicateItem

        // Assert
        #expect(error.errorDescription != nil)
        #expect(error.errorDescription?.lowercased().contains("save") == true ||
                error.errorDescription?.lowercased().contains("keychain") == true)
    }

    @Test("deleteFailed error has description")
    func deleteFailedErrorDescription() {
        // Arrange
        let error = KeychainService.KeychainError.deleteFailed(-25300) // errSecItemNotFound

        // Assert
        #expect(error.errorDescription != nil)
        #expect(error.errorDescription?.lowercased().contains("delete") == true ||
                error.errorDescription?.lowercased().contains("keychain") == true)
    }

    @Test("encodingFailed error has description")
    func encodingFailedErrorDescription() {
        // Arrange
        let error = KeychainService.KeychainError.encodingFailed

        // Assert
        #expect(error.errorDescription != nil)
        #expect(error.errorDescription?.lowercased().contains("encod") == true)
    }

    @Test("unexpectedData error has description")
    func unexpectedDataErrorDescription() {
        // Arrange
        let error = KeychainService.KeychainError.unexpectedData

        // Assert
        #expect(error.errorDescription != nil)
        #expect(error.errorDescription?.lowercased().contains("unexpected") == true ||
                error.errorDescription?.lowercased().contains("data") == true)
    }

    // MARK: - Service Initialization Tests

    @Test("KeychainService can be initialized and queried")
    func serviceInitialization() async {
        // Arrange & Act
        let service = KeychainService()

        // Assert - Verify service can be queried (tests initialization)
        // hasValue should return a boolean value, not throw
        let hasValue = await service.hasValue(for: .youtubeClientID)
        // Verify we got a value (not nil, not crashed)
        // We verify it's a boolean by using it in a way that would fail if it weren't
        let hasValueBool: Bool = hasValue  // Type check - would fail if not Bool
        _ = hasValueBool  // Verify we can use the value
        // The test passes if we get here (initialization and query worked)
    }

    // MARK: - hasValue Tests (Non-Destructive)

    @Test("hasValue returns false for non-existent key")
    func hasValueReturnsFalseForMissing() async throws {
        // Arrange
        let service = KeychainService()
        // Ensure key doesn't exist by deleting it first
        try? await service.delete(for: .youtubeRefreshToken)

        // Act - check for a key that shouldn't exist
        let hasToken = await service.hasValue(for: .youtubeRefreshToken)

        // Assert - should return false for non-existent key
        #expect(hasToken == false, "hasValue should return false for non-existent key")
    }

    // MARK: - Save and Retrieve Tests

    @Test("Save and retrieve work correctly")
    func saveAndRetrieve() async throws {
        // Arrange
        let service = KeychainService()
        let testValue = "test_client_id_12345"
        let testKey = KeychainService.KeychainKey.youtubeClientID

        // Clean up any existing value
        try? await service.delete(for: testKey)

        // Act - Save value
        try await service.save(testValue, for: testKey)

        // Assert - Retrieve should return the saved value
        let retrieved = await service.retrieve(for: testKey)
        #expect(retrieved == testValue, "Retrieved value should match saved value")

        // Cleanup
        try? await service.delete(for: testKey)
    }

    // MARK: - Credential Check Tests

    @Test("hasYouTubeCredentials checks both client ID and secret")
    func hasYouTubeCredentialsLogic() async throws {
        // Arrange
        let service = KeychainService()
        // Ensure clean state
        try? await service.delete(for: .youtubeClientID)
        try? await service.delete(for: .youtubeClientSecret)

        // Act - Check credentials when both are missing
        let hasCredsEmpty = await service.hasYouTubeCredentials()
        #expect(hasCredsEmpty == false, "Should return false when both keys are missing")

        // Act - Save only client ID
        try await service.save("test_id", for: .youtubeClientID)
        let hasCredsPartial = await service.hasYouTubeCredentials()
        #expect(hasCredsPartial == false, "Should return false when only client ID exists")

        // Act - Save both
        try await service.save("test_secret", for: .youtubeClientSecret)
        let hasCredsBoth = await service.hasYouTubeCredentials()
        #expect(hasCredsBoth == true, "Should return true when both client ID and secret exist")

        // Cleanup
        try? await service.delete(for: .youtubeClientID)
        try? await service.delete(for: .youtubeClientSecret)
    }

    @Test("isYouTubeAuthenticated checks credentials and refresh token")
    func isYouTubeAuthenticatedLogic() async throws {
        // Arrange
        let service = KeychainService()
        // Ensure clean state
        try? await service.deleteAll()

        // Act - Check authentication when nothing is set
        let isAuthEmpty = await service.isYouTubeAuthenticated()
        #expect(isAuthEmpty == false, "Should return false when no credentials exist")

        // Act - Set only credentials (no refresh token)
        try await service.save("test_id", for: .youtubeClientID)
        try await service.save("test_secret", for: .youtubeClientSecret)
        let isAuthNoToken = await service.isYouTubeAuthenticated()
        #expect(isAuthNoToken == false, "Should return false when credentials exist but no refresh token")

        // Act - Set refresh token
        try await service.save("test_token", for: .youtubeRefreshToken)
        let isAuthComplete = await service.isYouTubeAuthenticated()
        #expect(isAuthComplete == true, "Should return true when credentials and refresh token exist")

        // Cleanup
        try? await service.deleteAll()
    }
}
