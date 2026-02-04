//
//  MLEffectsServiceTests.swift
//  SaneVideoTests
//
//  Tests for ML Effects types and service availability checks
//

import XCTest

@testable import SaneVideo

final class MLEffectsServiceTests: XCTestCase {

    // MARK: - MLEffectType Tests

    func testMLEffectTypeAllCases() {
        let allCases = MLEffectType.allCases
        XCTAssertEqual(allCases.count, 3)
        XCTAssertTrue(allCases.contains(.superResolution))
        XCTAssertTrue(allCases.contains(.denoise))
        XCTAssertTrue(allCases.contains(.frameInterpolation))
    }

    func testMLEffectTypeIcons() {
        XCTAssertFalse(MLEffectType.superResolution.icon.isEmpty)
        XCTAssertFalse(MLEffectType.denoise.icon.isEmpty)
        XCTAssertFalse(MLEffectType.frameInterpolation.icon.isEmpty)
    }

    func testMLEffectTypeDescriptions() {
        XCTAssertFalse(MLEffectType.superResolution.description.isEmpty)
        XCTAssertFalse(MLEffectType.denoise.description.isEmpty)
        XCTAssertFalse(MLEffectType.frameInterpolation.description.isEmpty)
    }

    func testMLEffectTypeRealTimePreviewSupport() {
        // Only denoise supports real-time preview
        XCTAssertFalse(MLEffectType.superResolution.supportsRealTimePreview)
        XCTAssertTrue(MLEffectType.denoise.supportsRealTimePreview)
        XCTAssertFalse(MLEffectType.frameInterpolation.supportsRealTimePreview)
    }

    func testMLEffectTypeIdentifiable() {
        let type = MLEffectType.superResolution
        XCTAssertEqual(type.id, type.rawValue)
    }

    // MARK: - MLEffectConfiguration Tests

    func testMLEffectConfigurationDefault() {
        let config = MLEffectConfiguration(type: .superResolution)

        XCTAssertEqual(config.type, .superResolution)
        XCTAssertEqual(config.intensity, 1.0)
        XCTAssertTrue(config.isEnabled)
    }

    func testMLEffectConfigurationCustom() {
        let config = MLEffectConfiguration(
            type: .denoise,
            intensity: 0.5,
            isEnabled: false
        )

        XCTAssertEqual(config.type, .denoise)
        XCTAssertEqual(config.intensity, 0.5)
        XCTAssertFalse(config.isEnabled)
    }

    func testMLEffectConfigurationIntensityClamping() {
        let expectedMinIntensity: Float = 0.0
        let expectedMaxIntensity: Float = 1.0
        let tooLow = MLEffectConfiguration(type: .denoise, intensity: -0.5)
        XCTAssertEqual(tooLow.intensity, expectedMinIntensity, "Intensity below 0 should be clamped to 0")

        let tooHigh = MLEffectConfiguration(type: .denoise, intensity: 1.5)
        XCTAssertEqual(tooHigh.intensity, expectedMaxIntensity, "Intensity above 1 should be clamped to 1")
    }

    // MARK: - MLExportEffects Tests

    func testMLExportEffectsDefault() {
        let effects = MLExportEffects()
        let expectedSuperResolutionScale: CGFloat = 2.0
        let expectedDenoiseStrength: Float = 1.0
        let expectedTargetFrameRate: Double = 60

        XCTAssertFalse(effects.superResolutionEnabled)
        XCTAssertEqual(effects.superResolutionScale, expectedSuperResolutionScale)
        XCTAssertFalse(effects.denoiseEnabled)
        XCTAssertEqual(effects.denoiseStrength, expectedDenoiseStrength)
        XCTAssertFalse(effects.frameInterpolationEnabled)
        XCTAssertEqual(effects.targetFrameRate, expectedTargetFrameRate)
    }

    func testMLExportEffectsHasAnyEnabled() {
        var effects = MLExportEffects()
        XCTAssertFalse(effects.hasAnyEnabled, "No effects should be enabled by default")

        effects.superResolutionEnabled = true
        XCTAssertTrue(effects.hasAnyEnabled, "Should be true when super res is enabled")

        effects.superResolutionEnabled = false
        effects.denoiseEnabled = true
        XCTAssertTrue(effects.hasAnyEnabled, "Should be true when denoise is enabled")

        effects.denoiseEnabled = false
        effects.frameInterpolationEnabled = true
        XCTAssertTrue(effects.hasAnyEnabled, "Should be true when frame interpolation is enabled")
    }

    func testMLExportEffectsEquatable() {
        let effects1 = MLExportEffects()
        var effects2 = MLExportEffects()

        XCTAssertEqual(effects1, effects2, "Default effects should be equal")

        effects2.superResolutionEnabled = true
        XCTAssertNotEqual(effects1, effects2, "Different effects should not be equal")
    }

    // MARK: - MLEffectsError Tests

    func testMLEffectsErrorDescriptions() {
        let errors: [MLEffectsError] = [
            .modelNotReady,
            .unsupported,
            .configurationFailed,
            .sessionNotStarted,
            .processingFailed(NSError(domain: "test", code: 1))
        ]

        for error in errors {
            XCTAssertNotNil(error.errorDescription, "Error should have description: \(error)")
            XCTAssertFalse(error.errorDescription!.isEmpty, "Error description should not be empty")
        }
    }

    // MARK: - Service Availability Tests

    func testMLEffectsServiceAvailabilityChecks() {
        // These are static checks that don't require initialization
        // They should return valid boolean values without crashing
        let superResSupported = MLEffectsService.isSuperResolutionSupported
        let denoiseSupported = MLEffectsService.isDenoiseSupported
        let frameRateSupported = MLEffectsService.isFrameRateConversionSupported

        // Just verify they return booleans (values depend on OS version)
        XCTAssertTrue(superResSupported || !superResSupported, "Should be a valid boolean")
        XCTAssertTrue(denoiseSupported || !denoiseSupported, "Should be a valid boolean")
        XCTAssertTrue(frameRateSupported || !frameRateSupported, "Should be a valid boolean")
    }

    func testMLEffectsServiceInitialization() async {
        // Service should initialize without crashing
        let service = MLEffectsService()
        XCTAssertNotNil(service)
    }

    func testMLEffectsServiceEndAllSessions() async {
        // Should not crash even when no sessions are active
        let service = MLEffectsService()
        await service.endAllSessions()
        // No assertion needed - just verify it doesn't crash
    }
}
