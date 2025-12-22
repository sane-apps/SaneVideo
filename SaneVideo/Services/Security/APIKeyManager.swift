//
//  APIKeyManager.swift
//  SaneVideo
//
//  Observable manager for API keys - bridges KeychainService to SwiftUI
//

import Combine
import Foundation
import SwiftUI

/// Observable manager for API key configuration status
@MainActor
@Observable
class APIKeyManager {

    // MARK: - Status Properties

    private(set) var hasYouTubeCredentials: Bool = false
    private(set) var isYouTubeAuthenticated: Bool = false
    private(set) var hasOpenAIKey: Bool = false
    private(set) var hasGeminiKey: Bool = false

    init() {
        Task {
            await refreshStatus()
        }
    }

    // MARK: - Status Refresh

    /// Refresh all status indicators from Keychain
    func refreshStatus() async {
        let keychain = ServiceContainer.shared.keychainService

        hasYouTubeCredentials = await keychain.hasYouTubeCredentials()
        isYouTubeAuthenticated = await keychain.isYouTubeAuthenticated()
        hasOpenAIKey = await keychain.hasValue(for: .openAIKey)
        hasGeminiKey = await keychain.hasValue(for: .geminiKey)
    }

    // MARK: - YouTube Credentials

    /// Save YouTube OAuth credentials
    func saveYouTubeCredentials(clientID: String, clientSecret: String) async throws {
        let keychain = ServiceContainer.shared.keychainService

        guard !clientID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              !clientSecret.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        else {
            throw APIKeyError.emptyValue
        }

        try await keychain.save(clientID.trimmingCharacters(in: .whitespacesAndNewlines), for: .youtubeClientID)
        try await keychain.save(clientSecret.trimmingCharacters(in: .whitespacesAndNewlines), for: .youtubeClientSecret)

        await refreshStatus()
    }

    /// Save YouTube refresh token (called after OAuth flow)
    func saveYouTubeRefreshToken(_ token: String) async throws {
        try await ServiceContainer.shared.keychainService.save(token, for: .youtubeRefreshToken)
        await refreshStatus()
    }

    /// Get YouTube Client ID
    func getYouTubeClientID() async -> String? {
        await ServiceContainer.shared.keychainService.retrieve(for: .youtubeClientID)
    }

    /// Get YouTube Client Secret
    func getYouTubeClientSecret() async -> String? {
        await ServiceContainer.shared.keychainService.retrieve(for: .youtubeClientSecret)
    }

    /// Get YouTube Refresh Token
    func getYouTubeRefreshToken() async -> String? {
        await ServiceContainer.shared.keychainService.retrieve(for: .youtubeRefreshToken)
    }

    /// Clear YouTube authentication (keeps credentials, removes tokens)
    func clearYouTubeAuth() async throws {
        try await ServiceContainer.shared.keychainService.delete(for: .youtubeRefreshToken)
        await refreshStatus()
    }

    /// Clear all YouTube data
    func clearYouTubeCredentials() async throws {
        let keychain = ServiceContainer.shared.keychainService
        try await keychain.delete(for: .youtubeClientID)
        try await keychain.delete(for: .youtubeClientSecret)
        try await keychain.delete(for: .youtubeRefreshToken)
        await refreshStatus()
    }

    // MARK: - OpenAI Key

    /// Save OpenAI API key
    func saveOpenAIKey(_ key: String) async throws {
        guard !key.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw APIKeyError.emptyValue
        }

        try await ServiceContainer.shared.keychainService.save(key.trimmingCharacters(in: .whitespacesAndNewlines), for: .openAIKey)
        await refreshStatus()
    }

    /// Get OpenAI API key
    func getOpenAIKey() async -> String? {
        await ServiceContainer.shared.keychainService.retrieve(for: .openAIKey)
    }

    /// Clear OpenAI API key
    func clearOpenAIKey() async throws {
        try await ServiceContainer.shared.keychainService.delete(for: .openAIKey)
        await refreshStatus()
    }

    // MARK: - Gemini Key

    /// Save Gemini API key
    func saveGeminiKey(_ key: String) async throws {
        guard !key.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw APIKeyError.emptyValue
        }

        try await ServiceContainer.shared.keychainService.save(key.trimmingCharacters(in: .whitespacesAndNewlines), for: .geminiKey)
        await refreshStatus()
    }

    /// Get Gemini API key
    func getGeminiKey() async -> String? {
        await ServiceContainer.shared.keychainService.retrieve(for: .geminiKey)
    }

    /// Clear Gemini API key
    func clearGeminiKey() async throws {
        try await ServiceContainer.shared.keychainService.delete(for: .geminiKey)
        await refreshStatus()
    }

    // MARK: - Clear All

    /// Clear all stored API keys
    func clearAllKeys() async throws {
        try await ServiceContainer.shared.keychainService.deleteAll()
        await refreshStatus()
    }
}

// MARK: - Errors

enum APIKeyError: LocalizedError {
    case emptyValue
    case invalidFormat

    var errorDescription: String? {
        switch self {
        case .emptyValue:
            return "API key cannot be empty"
        case .invalidFormat:
            return "Invalid API key format"
        }
    }
}
