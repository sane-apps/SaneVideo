import Foundation

enum PricingTier: String, Codable, Sendable {
    case launch      // Legacy public-testing offer path
    case regular     // Standard Pro price
    case premium     // Future, if needed

    var displayPrice: String {
        switch self {
        case .launch: return "Free"
        case .regular: return "Free"
        case .premium: return "Free"
        }
    }

    var priceValue: Double {
        switch self {
        case .launch: return 14.99
        case .regular: return 14.99
        case .premium: return 79.0
        }
    }
}

struct FeatureFlags: Codable, Sendable {
    var allFeaturesIncluded: Bool = true
    var cloudAIEnabled: Bool = true       // Optional cloud AI (user's API keys)
    var onDeviceAIDefault: Bool = true

    var textBasedEditingEnabled: Bool = true
    var magicFixEnabled: Bool = true
    var export4KEnabled: Bool = true
    var screenRecordingEnabled: Bool = true

    static let `default` = FeatureFlags()
}

@MainActor
@Observable
class PricingConfiguration {

    // MARK: - Properties

    var currentTier: PricingTier {
        return .regular
    }

    var featureFlags = FeatureFlags.default

    /// Launch-period discount path is retired. SaneVideo is free.
    private let launchPeriodEndDate: Date

    var isLaunchPeriod: Bool {
        Date() < launchPeriodEndDate
    }

    var currentPrice: String {
        currentTier.displayPrice
    }

    var regularPrice: String {
        PricingTier.regular.displayPrice
    }

    // MARK: - Initialization

    init() {
        let components = DateComponents(calendar: .current, timeZone: .current, year: 2026, month: 7, day: 26)
        launchPeriodEndDate = components.date ?? Date.distantPast
    }

    // MARK: - Feature Checks

    func isFeatureEnabled(_ feature: Feature) -> Bool {
        switch feature {
        case .allFeatures:
            return featureFlags.allFeaturesIncluded
        case .cloudAI:
            return featureFlags.cloudAIEnabled
        case .onDeviceAI:
            return featureFlags.onDeviceAIDefault
        case .textBasedEditing:
            return featureFlags.textBasedEditingEnabled
        case .magicFix:
            return featureFlags.magicFixEnabled
        case .export4K:
            return featureFlags.export4KEnabled
        case .screenRecording:
            return featureFlags.screenRecordingEnabled
        }
    }

    func pricingMessage() -> String {
        "Free, with 100% Transparent Code. Donate only if you want to support it."
    }

    func valueProposition() -> String {
        "Every recording and edit tool stays unlocked."
    }
}

enum Feature: String, Sendable {
    case allFeatures = "all_features"
    case cloudAI = "cloud_ai"
    case onDeviceAI = "on_device_ai"
    case textBasedEditing = "text_based_editing"
    case magicFix = "magic_fix"
    case export4K = "export_4k"
    case screenRecording = "screen_recording"
}
