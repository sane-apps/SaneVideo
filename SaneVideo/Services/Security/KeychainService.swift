//
//  KeychainService.swift
//  SaneVideo
//
//  Secure storage for API keys using macOS Keychain
//

import Foundation
import Security

/// Thread-safe Keychain service for storing sensitive API credentials
actor KeychainService {

    private let serviceName = "com.sanevideo.apikeys"

    /// Keys for stored credentials
    enum KeychainKey: String, CaseIterable {
        case youtubeClientID = "youtube_client_id"
        case youtubeClientSecret = "youtube_client_secret"
        case youtubeRefreshToken = "youtube_refresh_token"
        case openAIKey = "openai_api_key"
        case geminiKey = "gemini_api_key"

        var displayName: String {
            switch self {
            case .youtubeClientID: return "YouTube Client ID"
            case .youtubeClientSecret: return "YouTube Client Secret"
            case .youtubeRefreshToken: return "YouTube Refresh Token"
            case .openAIKey: return "OpenAI API Key"
            case .geminiKey: return "Gemini API Key"
            }
        }
    }

    enum KeychainError: LocalizedError {
        case saveFailed(OSStatus)
        case deleteFailed(OSStatus)
        case encodingFailed
        case unexpectedData

        var errorDescription: String? {
            switch self {
            case let .saveFailed(status):
                return "Failed to save to Keychain: \(SecCopyErrorMessageString(status, nil) ?? "Unknown error" as CFString)"
            case let .deleteFailed(status):
                return "Failed to delete from Keychain: \(SecCopyErrorMessageString(status, nil) ?? "Unknown error" as CFString)"
            case .encodingFailed:
                return "Failed to encode data for Keychain"
            case .unexpectedData:
                return "Unexpected data format in Keychain"
            }
        }
    }

    init() {}

    // MARK: - Public API

    /// Save a value to Keychain
    func save(_ value: String, for key: KeychainKey) throws {
        guard let data = value.data(using: .utf8) else {
            throw KeychainError.encodingFailed
        }

        // Delete existing item first (update flow)
        try? delete(for: key)

        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: serviceName,
            kSecAttrAccount as String: key.rawValue,
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleWhenUnlocked
        ]

        let status = SecItemAdd(query as CFDictionary, nil)

        guard status == errSecSuccess else {
            throw KeychainError.saveFailed(status)
        }

        let keyName = key.displayName
        Task { @MainActor in
            AppLogger.general.info("Keychain: Saved \(keyName)")
        }
    }

    /// Retrieve a value from Keychain
    func retrieve(for key: KeychainKey) -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: serviceName,
            kSecAttrAccount as String: key.rawValue,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]

        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)

        guard status == errSecSuccess,
              let data = result as? Data,
              let string = String(data: data, encoding: .utf8)
        else {
            return nil
        }

        return string
    }

    /// Delete a value from Keychain
    func delete(for key: KeychainKey) throws {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: serviceName,
            kSecAttrAccount as String: key.rawValue
        ]

        let status = SecItemDelete(query as CFDictionary)

        // errSecItemNotFound is acceptable (nothing to delete)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw KeychainError.deleteFailed(status)
        }

        let keyName = key.displayName
        Task { @MainActor in
            AppLogger.general.info("Keychain: Deleted \(keyName)")
        }
    }

    /// Check if a value exists in Keychain
    func hasValue(for key: KeychainKey) -> Bool {
        return retrieve(for: key) != nil
    }

    /// Delete all stored keys
    func deleteAll() throws {
        for key in KeychainKey.allCases {
            try delete(for: key)
        }
        Task { @MainActor in
            AppLogger.general.info("Keychain: Cleared all API keys")
        }
    }

    // MARK: - Convenience Methods

    /// Check if YouTube credentials are configured
    func hasYouTubeCredentials() -> Bool {
        return hasValue(for: .youtubeClientID) && hasValue(for: .youtubeClientSecret)
    }

    /// Check if YouTube is fully authenticated (has refresh token)
    func isYouTubeAuthenticated() -> Bool {
        return hasYouTubeCredentials() && hasValue(for: .youtubeRefreshToken)
    }
}
