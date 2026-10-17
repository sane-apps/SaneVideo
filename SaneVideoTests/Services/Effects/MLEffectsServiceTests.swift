//
//  MLEffectsServiceTests.swift
//  SaneVideoTests
//
//  ML effect configuration rules: intensity clamping and the "any effect on" switch
//  the export path uses to decide whether to run the ML pipeline.
//

@testable import SaneVideo
import Testing

@Suite("ML Effects")
struct MLEffectsServiceTests {
    @Test(
        "Effect intensity is clamped to 0...1",
        arguments: [(Float(-0.5), Float(0.0)), (0.5, 0.5), (1.5, 1.0)]
    )
    func intensityClamping(input: Float, expected: Float) {
        #expect(MLEffectConfiguration(type: .denoise, intensity: input).intensity == expected)
    }

    @Test("hasAnyEnabled is true when any single ML export effect is on")
    func hasAnyEnabled() {
        #expect(!MLExportEffects().hasAnyEnabled)

        var superRes = MLExportEffects()
        superRes.superResolutionEnabled = true
        var denoise = MLExportEffects()
        denoise.denoiseEnabled = true
        var interpolation = MLExportEffects()
        interpolation.frameInterpolationEnabled = true

        #expect(superRes.hasAnyEnabled)
        #expect(denoise.hasAnyEnabled)
        #expect(interpolation.hasAnyEnabled)
    }
}
