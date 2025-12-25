//
//  Secrets.swift - Auto-generated if missing
//
import Foundation

enum Secrets {
    static func youTubeClientID() async -> String { await ServiceContainer.shared.apiKeyManager.getYouTubeClientID() ?? "" }
    static func youTubeClientSecret() async -> String { await ServiceContainer.shared.apiKeyManager.getYouTubeClientSecret() ?? "" }
    static func openAIKey() async -> String { await ServiceContainer.shared.apiKeyManager.getOpenAIKey() ?? "" }
    static func geminiKey() async -> String { await ServiceContainer.shared.apiKeyManager.getGeminiKey() ?? "" }
}
