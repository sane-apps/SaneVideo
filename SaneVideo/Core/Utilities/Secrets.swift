//
//  Secrets.swift - Auto-generated if missing
//
import Foundation

enum Secrets {
    static func youTubeClientID() async -> String { await ServiceContainer.shared.apiKeyManager.getYouTubeClientID() ?? "" }
    static func youTubeClientSecret() async -> String { await ServiceContainer.shared.apiKeyManager.getYouTubeClientSecret() ?? "" }
}
