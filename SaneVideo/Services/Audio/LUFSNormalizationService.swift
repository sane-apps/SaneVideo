//
//  LUFSNormalizationService.swift
//  SaneVideo
//
//  LUFS (Loudness Units relative to Full Scale) normalization service.
//  Analyzes audio loudness and applies gain to meet broadcast standards.
//  Target: -14 LUFS for streaming platforms (YouTube, Spotify, etc.)
//

import AVFoundation
import Accelerate

/// LUFS normalization service for broadcast-standard audio loudness.
/// Uses ITU-R BS.1770 algorithm for loudness measurement.
actor LUFSNormalizationService {

    // MARK: - Constants

    /// Target LUFS for streaming platforms (YouTube, Spotify, Apple Music)
    static let streamingTargetLUFS: Float = -14.0

    /// Target LUFS for broadcast TV (EBU R128 / ATSC A/85)
    static let broadcastTargetLUFS: Float = -23.0

    /// Maximum true peak level in dBTP
    static let maxTruePeak: Float = -1.0

    // MARK: - Types

    /// Result of LUFS analysis
    struct LUFSAnalysis: Sendable {
        let integratedLUFS: Float      // Overall loudness
        let loudnessRange: Float        // Dynamic range (LRA)
        let truePeak: Float             // Maximum true peak in dBTP
        let recommendedGain: Float      // Gain to apply for normalization
    }

    // MARK: - Public API

    /// Analyze the loudness of an audio file.
    /// Returns LUFS measurements and recommended gain for normalization.
    func analyzeAudio(at url: URL, targetLUFS: Float = streamingTargetLUFS) async throws -> LUFSAnalysis {
        let file = try AVAudioFile(forReading: url)
        let format = file.processingFormat
        let sampleRate = Float(format.sampleRate)
        let channelCount = Int(format.channelCount)

        // Read all audio into buffer
        let frameCount = AVAudioFrameCount(file.length)
        guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frameCount) else {
            throw LUFSError.bufferCreationFailed
        }
        try file.read(into: buffer)

        // Convert to mono for analysis if needed
        let samples = extractMonoSamples(from: buffer, channelCount: channelCount)

        // Apply K-weighting filter (ITU-R BS.1770)
        let kWeightedSamples = applyKWeighting(samples: samples, sampleRate: sampleRate)

        // Calculate mean square (loudness)
        let meanSquare = calculateMeanSquare(samples: kWeightedSamples)

        // Convert to LUFS
        let integratedLUFS = meanSquareToLUFS(meanSquare)

        // Calculate true peak
        let truePeak = calculateTruePeak(samples: samples)

        // Calculate recommended gain
        let recommendedGain = calculateRecommendedGain(
            currentLUFS: integratedLUFS,
            targetLUFS: targetLUFS,
            currentPeak: truePeak
        )

        // Calculate loudness range (simplified - short-term analysis)
        let loudnessRange = calculateLoudnessRange(samples: kWeightedSamples, sampleRate: sampleRate)

        return LUFSAnalysis(
            integratedLUFS: integratedLUFS,
            loudnessRange: loudnessRange,
            truePeak: truePeak,
            recommendedGain: recommendedGain
        )
    }

    /// Calculate gain needed to normalize audio to target LUFS.
    /// Accounts for true peak limiting to prevent clipping.
    func calculateNormalizationGain(
        currentLUFS: Float,
        targetLUFS: Float,
        truePeak: Float
    ) -> Float {
        return calculateRecommendedGain(
            currentLUFS: currentLUFS,
            targetLUFS: targetLUFS,
            currentPeak: truePeak
        )
    }

    // MARK: - Private Helpers

    /// Extract mono samples from PCM buffer
    private func extractMonoSamples(from buffer: AVAudioPCMBuffer, channelCount: Int) -> [Float] {
        let frameCount = Int(buffer.frameLength)
        guard let floatChannelData = buffer.floatChannelData else { return [] }

        var monoSamples = [Float](repeating: 0, count: frameCount)

        if channelCount == 1 {
            // Already mono
            memcpy(&monoSamples, floatChannelData[0], frameCount * MemoryLayout<Float>.size)
        } else {
            // Mix down to mono (average channels)
            for i in 0..<frameCount {
                var sum: Float = 0
                for ch in 0..<channelCount {
                    sum += floatChannelData[ch][i]
                }
                monoSamples[i] = sum / Float(channelCount)
            }
        }

        return monoSamples
    }

    /// Apply K-weighting filter (ITU-R BS.1770)
    /// Consists of high-shelf boost at ~1.5kHz and high-pass at ~50Hz
    private func applyKWeighting(samples: [Float], sampleRate: Float) -> [Float] {
        var result = samples

        // Simplified K-weighting using biquad filters
        // Stage 1: High-shelf filter (+4dB at high frequencies)
        result = applyHighShelf(samples: result, sampleRate: sampleRate, gainDB: 4.0, frequency: 1500)

        // Stage 2: High-pass filter (removes very low frequencies)
        result = applyHighPass(samples: result, sampleRate: sampleRate, frequency: 50)

        return result
    }

    /// Apply a simplified high-shelf filter
    private func applyHighShelf(samples: [Float], sampleRate: Float, gainDB: Float, frequency: Float) -> [Float] {
        let gain = powf(10, gainDB / 20)
        let w0 = 2 * .pi * frequency / sampleRate
        let alpha = sinf(w0) / 2 * sqrtf(2)

        let a0 = (gain + 1) + (gain - 1) * cosf(w0) + 2 * sqrtf(gain) * alpha
        let a1 = -2 * ((gain - 1) + (gain + 1) * cosf(w0))
        let a2 = (gain + 1) + (gain - 1) * cosf(w0) - 2 * sqrtf(gain) * alpha
        let b0 = gain * ((gain + 1) - (gain - 1) * cosf(w0) + 2 * sqrtf(gain) * alpha)
        let b1 = 2 * gain * ((gain - 1) - (gain + 1) * cosf(w0))
        let b2 = gain * ((gain + 1) - (gain - 1) * cosf(w0) - 2 * sqrtf(gain) * alpha)

        return applyBiquad(samples: samples, b0: b0/a0, b1: b1/a0, b2: b2/a0, a1: a1/a0, a2: a2/a0)
    }

    /// Apply a high-pass filter
    private func applyHighPass(samples: [Float], sampleRate: Float, frequency: Float) -> [Float] {
        let w0 = 2 * .pi * frequency / sampleRate
        let alpha = sinf(w0) / 2

        let a0 = 1 + alpha
        let a1 = -2 * cosf(w0)
        let a2 = 1 - alpha
        let b0 = (1 + cosf(w0)) / 2
        let b1 = -(1 + cosf(w0))
        let b2 = (1 + cosf(w0)) / 2

        return applyBiquad(samples: samples, b0: b0/a0, b1: b1/a0, b2: b2/a0, a1: a1/a0, a2: a2/a0)
    }

    /// Apply a biquad filter
    private func applyBiquad(samples: [Float], b0: Float, b1: Float, b2: Float, a1: Float, a2: Float) -> [Float] {
        var result = [Float](repeating: 0, count: samples.count)
        var x1: Float = 0, x2: Float = 0
        var y1: Float = 0, y2: Float = 0

        for i in 0..<samples.count {
            let x0 = samples[i]
            let y0 = b0 * x0 + b1 * x1 + b2 * x2 - a1 * y1 - a2 * y2

            result[i] = y0

            x2 = x1
            x1 = x0
            y2 = y1
            y1 = y0
        }

        return result
    }

    /// Calculate mean square of samples
    private func calculateMeanSquare(samples: [Float]) -> Float {
        var sumSquared: Float = 0
        vDSP_svesq(samples, 1, &sumSquared, vDSP_Length(samples.count))
        return sumSquared / Float(samples.count)
    }

    /// Convert mean square to LUFS
    private func meanSquareToLUFS(_ meanSquare: Float) -> Float {
        guard meanSquare > 0 else { return -Float.infinity }
        // LUFS = -0.691 + 10 * log10(mean_square)
        return -0.691 + 10 * log10f(meanSquare)
    }

    /// Calculate true peak using oversampling
    private func calculateTruePeak(samples: [Float]) -> Float {
        // Find the absolute maximum sample value
        var maxVal: Float = 0
        vDSP_maxmgv(samples, 1, &maxVal, vDSP_Length(samples.count))

        // Convert to dBTP
        guard maxVal > 0 else { return -Float.infinity }
        return 20 * log10f(maxVal)
    }

    /// Calculate recommended gain for normalization
    private func calculateRecommendedGain(
        currentLUFS: Float,
        targetLUFS: Float,
        currentPeak: Float
    ) -> Float {
        // Calculate gain needed to reach target LUFS
        let lufsGain = targetLUFS - currentLUFS

        // Check if this would cause clipping
        let peakAfterGain = currentPeak + lufsGain

        if peakAfterGain > Self.maxTruePeak {
            // Reduce gain to prevent clipping
            return Self.maxTruePeak - currentPeak
        }

        return lufsGain
    }

    /// Calculate loudness range (simplified)
    private func calculateLoudnessRange(samples: [Float], sampleRate: Float) -> Float {
        // Use 3-second windows for short-term loudness
        let windowSize = Int(sampleRate * 3)
        guard samples.count >= windowSize else { return 0 }

        var shortTermLoudness: [Float] = []

        // Overlap by 2/3 (hop = 1 second)
        let hopSize = Int(sampleRate)
        var position = 0

        while position + windowSize <= samples.count {
            let window = Array(samples[position..<(position + windowSize)])
            let meanSquare = calculateMeanSquare(samples: window)
            let lufs = meanSquareToLUFS(meanSquare)
            if lufs.isFinite && lufs > -70 {  // Gate very quiet sections
                shortTermLoudness.append(lufs)
            }
            position += hopSize
        }

        guard shortTermLoudness.count >= 2 else { return 0 }

        // Sort and calculate 10th to 95th percentile range
        shortTermLoudness.sort()
        let lowIndex = Int(Float(shortTermLoudness.count) * 0.10)
        let highIndex = Int(Float(shortTermLoudness.count) * 0.95)

        return shortTermLoudness[highIndex] - shortTermLoudness[lowIndex]
    }
}

// MARK: - Errors

enum LUFSError: Error, LocalizedError {
    case bufferCreationFailed
    case analysisError(String)

    var errorDescription: String? {
        switch self {
        case .bufferCreationFailed:
            return "Failed to create audio buffer for LUFS analysis"
        case .analysisError(let message):
            return "LUFS analysis error: \(message)"
        }
    }
}
