//
//  PricingConfiguration.swift
//  SaneVideo
//
//  Pricing and feature configuration system
//  Supports launch pricing, regular pricing, and feature flags
//

import Foundation

/// Pricing configuration for the app
enum PricingTier: String, Codable, Sendable {
    case launch      // Legacy public-testing offer path
    case regular     // Standard Pro price
    case premium     // Future, if needed

    var displayPrice: String {
        switch self {
        case .launch: return "$14.99"
        case .regular: return "$14.99"
        case .premium: return "$79"
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

/// Feature flags for enabling/disabling features
struct FeatureFlags: Codable, Sendable {
    var allFeaturesIncluded: Bool = true  // All-inclusive model
    var cloudAIEnabled: Bool = true       // Optional cloud AI (user's API keys)
    var onDeviceAIDefault: Bool = true    // Default to Apple Intelligence

    // Future feature gates (if needed)
    var textBasedEditingEnabled: Bool = true
    var magicFixEnabled: Bool = true
    var export4KEnabled: Bool = true
    var screenRecordingEnabled: Bool = true

    static let `default` = FeatureFlags()
}

/// Pricing configuration manager
@MainActor
@Observable
class PricingConfiguration {

    // MARK: - Properties

    /// Current pricing tier
    var currentTier: PricingTier {
        return .regular
    }

    /// Feature flags
    var featureFlags = FeatureFlags.default

    /// Public testing no longer uses discounted launch pricing.
    private let launchPeriodEndDate: Date

    /// Whether we're in the launch pricing period
    var isLaunchPeriod: Bool {
        Date() < launchPeriodEndDate
    }

    /// Current price string for display
    var currentPrice: String {
        currentTier.displayPrice
    }

    /// Regular price (for comparison)
    var regularPrice: String {
        PricingTier.regular.displayPrice
    }

    // MARK: - Initialization

    init() {
        let components = DateComponents(calendar: .current, timeZone: .current, year: 2026, month: 7, day: 26)
        launchPeriodEndDate = components.date ?? Date.distantPast
    }

    // MARK: - Feature Checks

    /// Check if a feature is enabled
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

    /// Get pricing message for UI
    func pricingMessage() -> String {
        if isLaunchPeriod {
            return "Enjoy 14 days of Pro, then keep it for \(currentPrice) once"
        }
        return "\(currentPrice) one-time purchase"
    }

    /// Get value proposition message
    func valueProposition() -> String {
        "Try Pro free for 14 days. Basic stays available after the trial."
    }
}

/// Feature enumeration for feature flag checks
enum Feature: String, Sendable {
    case allFeatures = "all_features"
    case cloudAI = "cloud_ai"
    case onDeviceAI = "on_device_ai"
    case textBasedEditing = "text_based_editing"
    case magicFix = "magic_fix"
    case export4K = "export_4k"
    case screenRecording = "screen_recording"
}
