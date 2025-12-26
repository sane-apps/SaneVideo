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
    case launch      // $29 (first 90 days)
    case regular     // $49 (standard)
    case premium     // $79 (future, if needed)

    var displayPrice: String {
        switch self {
        case .launch: return "$29"
        case .regular: return "$49"
        case .premium: return "$79"
        }
    }

    var priceValue: Double {
        switch self {
        case .launch: return 29.0
        case .regular: return 49.0
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
        if isLaunchPeriod {
            return .launch
        }
        return .regular
    }

    /// Feature flags
    var featureFlags = FeatureFlags.default

    /// Launch period end date (90 days from app launch)
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
        // Calculate launch period end (90 days from first launch)
        // Store in UserDefaults to persist across app launches
        let defaults = UserDefaults.standard
        if let storedDate = defaults.object(forKey: "LaunchPeriodEndDate") as? Date {
            launchPeriodEndDate = storedDate
        } else {
            // First launch - set end date to 90 days from now
            let endDate = Calendar.current.date(byAdding: .day, value: 90, to: Date()) ?? Date()
            defaults.set(endDate, forKey: "LaunchPeriodEndDate")
            launchPeriodEndDate = endDate
        }
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
            return "Launch Special: \(currentPrice) (Regular: \(regularPrice))"
        }
        return "\(currentPrice) one-time purchase"
    }

    /// Get value proposition message
    func valueProposition() -> String {
        "Everything included. One price. Forever."
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
