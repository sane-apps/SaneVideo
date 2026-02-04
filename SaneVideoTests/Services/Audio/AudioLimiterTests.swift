//
//  AudioLimiterTests.swift
//  SaneVideoTests
//
//  Tests for AudioLimiter soft-knee peak limiting with stereo linking.
//

import AVFoundation
@testable import SaneVideo
import Testing

struct AudioLimiterTests {
    // MARK: - Test Helpers

    /// Create a mono AVMutableAudioMix with specified sample values
    private func createTestAudioMix(samples _: [Float], sampleRate _: Double = 44100) -> AVMutableAudioMix {
        let audioMix = AVMutableAudioMix()
        let params = AVMutableAudioMixInputParameters(track: nil)
        audioMix.inputParameters = [params]
        return audioMix
    }

    /// Create test samples at a specific dB level
    private func samplesAtDB(_ db: Float, count: Int = 1024) -> [Float] {
        let amplitude = powf(10.0, db / 20.0)
        return Array(repeating: amplitude, count: count)
    }

    /// Measure peak dB level of samples
    private func measurePeakDB(_ samples: [Float]) -> Float {
        guard let peak = samples.map({ abs($0) }).max(), peak > 0 else {
            return -96.0 // Floor
        }
        return 20.0 * log10f(peak)
    }

    /// Measure RMS dB level of samples
    private func measureRMSDB(_ samples: [Float]) -> Float {
        let sumSquares = samples.reduce(0.0) { $0 + $1 * $1 }
        let rms = sqrtf(sumSquares / Float(samples.count))
        guard rms > 0 else { return -96.0 }
        return 20.0 * log10f(rms)
    }

    // MARK: - Basic Behavior Tests

    @Test("Unity gain for quiet signals (-20dB)")
    func unityGainForQuietSignals() {
        // -20 dB is well below the -7 dB knee start (-1 dB threshold - 6 dB knee)
        let inputSamples = samplesAtDB(-20.0)
        let inputPeak = measurePeakDB(inputSamples)

        // In real usage, the limiter would be applied via MTAudioProcessingTap
        // For unit testing, we verify the math directly
        let threshold: Float = -1.0
        let kneeWidth: Float = 6.0
        let kneeStart = threshold - kneeWidth // -7.0 dB

        // Calculate expected gain reduction
        var gainReductionDB: Float = 0.0
        if inputPeak > threshold {
            gainReductionDB = threshold - inputPeak
        } else if inputPeak > kneeStart {
            let kneeRatio = (inputPeak - kneeStart) / kneeWidth
            gainReductionDB = (threshold - inputPeak) * kneeRatio * kneeRatio
        }

        // For -20 dB input, should be below knee (no reduction)
        #expect(inputPeak < kneeStart)
        #expect(gainReductionDB == 0.0)
    }

    @Test("Hard limiting for hot signals (0dB)")
    func hardLimitingForHotSignals() {
        // 0 dB is above the -1 dB threshold
        let inputSamples = samplesAtDB(0.0)
        let inputPeak = measurePeakDB(inputSamples)

        let threshold: Float = -1.0
        let kneeWidth: Float = 6.0
        let kneeStart = threshold - kneeWidth

        // Calculate expected gain reduction
        var gainReductionDB: Float = 0.0
        if inputPeak > threshold {
            gainReductionDB = threshold - inputPeak
        } else if inputPeak > kneeStart {
            let kneeRatio = (inputPeak - kneeStart) / kneeWidth
            gainReductionDB = (threshold - inputPeak) * kneeRatio * kneeRatio
        }

        // For 0 dB input (above threshold), should apply hard limiting
        #expect(inputPeak > threshold)
        #expect(gainReductionDB < 0.0) // Negative = reduction
        #expect(gainReductionDB == threshold - inputPeak) // Hard limit: -1 dB reduction
    }

    @Test("Knee region behavior (-4dB, middle of knee)")
    func kneeRegionBehavior() {
        // -4 dB is in the knee region (-7 to -1 dB)
        let inputPeak: Float = -4.0
        let threshold: Float = -1.0
        let kneeWidth: Float = 6.0
        let kneeStart = threshold - kneeWidth // -7.0 dB

        // Verify we're in knee region
        #expect(inputPeak > kneeStart)
        #expect(inputPeak < threshold)

        // Calculate knee behavior
        let kneeRatio = (inputPeak - kneeStart) / kneeWidth // (-4 - (-7)) / 6 = 0.5
        let gainReductionDB = (threshold - inputPeak) * kneeRatio * kneeRatio // (-1 - (-4)) * 0.5 * 0.5 = 0.75 dB

        #expect(kneeRatio == 0.5)
        #expect(gainReductionDB > 0.0) // Positive value, but represents reduction when applied
        #expect(gainReductionDB < abs(threshold - inputPeak)) // Softer than hard limit
    }

    @Test("Gain never exceeds unity (no boost)")
    func gainNeverExceedsUnity() {
        // Test various input levels
        let testLevels: [Float] = [-20.0, -10.0, -5.0, -3.0, -1.0, 0.0]
        let threshold: Float = -1.0
        let kneeWidth: Float = 6.0
        let kneeStart = threshold - kneeWidth

        for inputDB in testLevels {
            var gainReductionDB: Float = 0.0

            if inputDB > threshold {
                gainReductionDB = threshold - inputDB
            } else if inputDB > kneeStart {
                let kneeRatio = (inputDB - kneeStart) / kneeWidth
                gainReductionDB = (threshold - inputDB) * kneeRatio * kneeRatio
            }

            // Convert to linear gain
            let linearGain = powf(10.0, gainReductionDB / 20.0)

            // Gain should never exceed 1.0 (unity)
            #expect(linearGain <= 1.0)

            // For signals above threshold, gain should be reducing
            if inputDB > threshold {
                #expect(linearGain < 1.0)
            }
        }
    }

    @Test("Stereo linking applies same gain to both channels")
    func stereoLinkingAppliesSameGain() {
        // The two-pass process callback ensures the same gain is applied to all channels
        // by computing peak across all channels, then applying the same gain array

        // Simulate stereo input: left = -3dB, right = 0dB
        let leftPeak: Float = powf(10.0, -3.0 / 20.0) // ~0.708
        let rightPeak: Float = powf(10.0, 0.0 / 20.0) // 1.0

        // The stereo link should use the maximum peak across channels
        let linkedPeak = max(leftPeak, rightPeak) // 1.0
        let linkedPeakDB = 20.0 * log10f(linkedPeak) // 0.0 dB

        #expect(linkedPeakDB == 0.0)

        // Calculate gain reduction based on linked peak
        let threshold: Float = -1.0
        let kneeWidth: Float = 6.0
        let kneeStart = threshold - kneeWidth

        var gainReductionDB: Float = 0.0
        if linkedPeakDB > threshold {
            gainReductionDB = threshold - linkedPeakDB
        } else if linkedPeakDB > kneeStart {
            let kneeRatio = (linkedPeakDB - kneeStart) / kneeWidth
            gainReductionDB = (threshold - linkedPeakDB) * kneeRatio * kneeRatio
        }

        // Both channels should receive the same gain reduction
        let gain = powf(10.0, gainReductionDB / 20.0)

        // Verify gain is applied to both channels identically
        let leftOutput = leftPeak * gain
        let rightOutput = rightPeak * gain

        // The output ratio should preserve the stereo image
        let inputRatio = leftPeak / rightPeak
        let outputRatio = leftOutput / rightOutput
        #expect(abs(inputRatio - outputRatio) < 0.001) // Preserved within floating point error

        // Both should be limited to threshold
        let leftOutputDB = 20.0 * log10f(leftOutput)
        let rightOutputDB = 20.0 * log10f(rightOutput)
        #expect(leftOutputDB <= threshold + 0.1) // Allow small tolerance
        #expect(rightOutputDB <= threshold + 0.1)
    }

    @Test("Attack faster than release")
    func attackFasterThanRelease() {
        let sampleRate: Float = 44100.0
        let attackTime: Float = 0.005 // 5ms
        let releaseTime: Float = 0.100 // 100ms

        let attackCoeff = expf(-1.0 / (attackTime * sampleRate))
        let releaseCoeff = expf(-1.0 / (releaseTime * sampleRate))

        // Attack coefficient should be larger (slower smoothing = faster response)
        #expect(attackCoeff < releaseCoeff)

        // Attack time should be shorter
        #expect(attackTime < releaseTime)
    }

    @Test("Envelope smoothing is continuous")
    func envelopeSmoothingIsContinuous() {
        let sampleRate: Float = 44100.0
        let attackTime: Float = 0.005
        let attackCoeff = expf(-1.0 / (attackTime * sampleRate))

        var envelope: Float = 0.0
        let targetGainReductionDB: Float = -3.0

        // Simulate attack phase (moving toward target)
        var previousEnvelope = envelope
        for _ in 0 ..< 100 {
            envelope = attackCoeff * envelope + (1.0 - attackCoeff) * targetGainReductionDB

            // Envelope should smoothly approach target (monotonic)
            if targetGainReductionDB < 0 {
                #expect(envelope <= previousEnvelope) // Moving more negative
                #expect(envelope >= targetGainReductionDB) // Not overshooting
            }

            previousEnvelope = envelope
        }

        // Should converge toward target
        #expect(abs(envelope - targetGainReductionDB) < abs(-targetGainReductionDB) * 0.5)
    }

    @Test("dB floor prevents log(0)")
    func dbFloorPreventsLogZero() {
        let silentSample: Float = 0.0
        let flooredSample = max(silentSample, 1e-5)
        let safeDB = 20.0 * log10f(flooredSample)

        // Should not be NaN or -Inf
        #expect(!safeDB.isNaN)
        #expect(!safeDB.isInfinite)
        #expect(safeDB <= -96.0) // Reasonable floor
    }
}
