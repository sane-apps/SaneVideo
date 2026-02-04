//
//  LUFSNormalizationService.swift
//  SaneVideo
//
//  LUFS (Loudness Units relative to Full Scale) normalization service.
//  Analyzes audio loudness and applies gain to meet broadcast standards.
//  Target: -14 LUFS for streaming platforms (YouTube, Spotify, etc.)
//

import Accelerate
import AVFoundation

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
        let integratedLUFS: Float // Overall loudness
        let loudnessRange: Float // Dynamic range (LRA)
        let truePeak: Float // Maximum true peak in dBTP
        let recommendedGain: Float // Gain to apply for normalization
    }

    private struct BiquadCoefficients {
        let b0: Float
        let b1: Float
        let b2: Float
        let a1: Float
        let a2: Float
    }

    // MARK: - Public API

    /// Analyze the loudness of an audio file.
    /// Returns LUFS measurements and recommended gain for normalization.
    /// Uses streaming analysis for files longer than 30 seconds to reduce memory usage.
    func analyzeAudio(at url: URL, targetLUFS: Float = streamingTargetLUFS) async throws -> LUFSAnalysis {
        let file = try AVAudioFile(forReading: url)
        let format = file.processingFormat
        let sampleRate = Float(format.sampleRate)
        let channelCount = Int(format.channelCount)
        let totalFrames = AVAudioFrameCount(file.length)

        // For small files (< 30 seconds), use the simple approach
        let smallFileThreshold = AVAudioFrameCount(sampleRate * 30)

        if totalFrames <= smallFileThreshold {
            return try analyzeSmallFile(file, sampleRate: sampleRate, channelCount: channelCount, targetLUFS: targetLUFS)
        }

        return try analyzeStreamingFile(file, sampleRate: sampleRate, channelCount: channelCount, targetLUFS: targetLUFS)
    }

    /// Analyze a small audio file (< 30 seconds) by loading it entirely into memory.
    private func analyzeSmallFile(
        _ file: AVAudioFile,
        sampleRate: Float,
        channelCount: Int,
        targetLUFS: Float
    ) throws -> LUFSAnalysis {
        // Read all audio into buffer
        let frameCount = AVAudioFrameCount(file.length)
        guard let buffer = AVAudioPCMBuffer(pcmFormat: file.processingFormat, frameCapacity: frameCount) else {
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

    /// Analyze a large audio file using streaming (chunked) analysis to reduce memory usage.
    /// Processes in 3-second chunks, accumulating statistics for integrated loudness.
    private func analyzeStreamingFile(
        _ file: AVAudioFile,
        sampleRate: Float,
        channelCount: Int,
        targetLUFS: Float
    ) throws -> LUFSAnalysis {
        let chunkDuration: Float = 3.0 // 3-second chunks
        let chunkFrames = AVAudioFrameCount(sampleRate * chunkDuration)
        guard let buffer = AVAudioPCMBuffer(pcmFormat: file.processingFormat, frameCapacity: chunkFrames) else {
            throw LUFSError.bufferCreationFailed
        }

        var totalMeanSquareSum: Float = 0
        var totalSampleCount = 0
        var peakTruePeak: Float = -Float.infinity
        var shortTermLoudness: [Float] = []

        while file.framePosition < file.length {
            let framesToRead = min(chunkFrames, AVAudioFrameCount(file.length - file.framePosition))
            buffer.frameLength = 0
            try file.read(into: buffer, frameCount: framesToRead)

            let samples = extractMonoSamples(from: buffer, channelCount: channelCount)
            let kWeighted = applyKWeighting(samples: samples, sampleRate: sampleRate)

            // Accumulate mean square
            let ms = calculateMeanSquare(samples: kWeighted)
            totalMeanSquareSum += ms * Float(kWeighted.count)
            totalSampleCount += kWeighted.count

            // Track true peak (on original samples, not K-weighted)
            let chunkPeak = calculateTruePeak(samples: samples)
            peakTruePeak = max(peakTruePeak, chunkPeak)

            // Short-term loudness for LRA
            let lufs = meanSquareToLUFS(ms)
            if lufs.isFinite, lufs > -70 {
                shortTermLoudness.append(lufs)
            }
        }

        // Integrated LUFS
        let integratedMS = totalSampleCount > 0 ? totalMeanSquareSum / Float(totalSampleCount) : 0
        let integratedLUFS = meanSquareToLUFS(integratedMS)

        // LRA
        let loudnessRange = calculateLoudnessRangeFromValues(shortTermLoudness)

        // Recommended gain
        let recommendedGain = calculateRecommendedGain(
            currentLUFS: integratedLUFS,
            targetLUFS: targetLUFS,
            currentPeak: peakTruePeak
        )

        return LUFSAnalysis(
            integratedLUFS: integratedLUFS,
            loudnessRange: loudnessRange,
            truePeak: peakTruePeak,
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
        calculateRecommendedGain(
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
            for i in 0 ..< frameCount {
                var sum: Float = 0
                for ch in 0 ..< channelCount {
                    sum += floatChannelData[ch][i]
                }
                monoSamples[i] = sum / Float(channelCount)
            }
        }

        return monoSamples
    }

    /// Apply K-weighting filter (ITU-R BS.1770-4 compliant)
    /// Stage 1: High-shelf at 1681.97 Hz with +3.999 dB gain
    /// Stage 2: High-pass at 38.135 Hz
    private func applyKWeighting(samples: [Float], sampleRate: Float) -> [Float] {
        var result = samples

        if abs(sampleRate - 48000.0) < 1.0 {
            // Use BS.1770-4 reference coefficients for 48kHz
            // Stage 1: Pre-filter (high-shelf)
            let preFilter = BiquadCoefficients(
                b0: 1.53512485958697,
                b1: -2.69169618940638,
                b2: 1.19839281085285,
                a1: -1.69065929318241,
                a2: 0.73248077421585
            )
            result = applyBiquad(samples: result, coefficients: preFilter)

            // Stage 2: RLB weighting (high-pass)
            let rlbFilter = BiquadCoefficients(
                b0: 1.0,
                b1: -2.0,
                b2: 1.0,
                a1: -1.99004745483398,
                a2: 0.99007225036621
            )
            result = applyBiquad(samples: result, coefficients: rlbFilter)
        } else {
            // Fallback: use bilinear transform for non-48kHz rates
            // Stage 1: High-shelf at 1681.97 Hz, +3.999 dB gain
            result = applyHighShelf(samples: result, sampleRate: sampleRate, gainDB: 3.999, frequency: 1681.97)
            // Stage 2: High-pass at 38.135 Hz
            result = applyHighPass(samples: result, sampleRate: sampleRate, frequency: 38.135)
        }

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

        let coefficients = BiquadCoefficients(
            b0: b0 / a0,
            b1: b1 / a0,
            b2: b2 / a0,
            a1: a1 / a0,
            a2: a2 / a0
        )
        return applyBiquad(samples: samples, coefficients: coefficients)
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

        let coefficients = BiquadCoefficients(
            b0: b0 / a0,
            b1: b1 / a0,
            b2: b2 / a0,
            a1: a1 / a0,
            a2: a2 / a0
        )
        return applyBiquad(samples: samples, coefficients: coefficients)
    }

    /// Apply a biquad filter
    private func applyBiquad(samples: [Float], coefficients: BiquadCoefficients) -> [Float] {
        var result = [Float](repeating: 0, count: samples.count)
        var x1: Float = 0, x2: Float = 0
        var y1: Float = 0, y2: Float = 0

        for i in 0 ..< samples.count {
            let x0 = samples[i]
            let y0 = coefficients.b0 * x0 +
                coefficients.b1 * x1 +
                coefficients.b2 * x2 -
                coefficients.a1 * y1 -
                coefficients.a2 * y2

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

    /// Calculate true peak using 4x oversampling (ITU-R BS.1770-4 compliant)
    /// Detects inter-sample peaks that would cause clipping on DAC reconstruction
    private func calculateTruePeak(samples: [Float]) -> Float {
        // BS.1770-4 requires minimum 4x oversampling for true peak
        let oversampleFactor = 4

        // Use vDSP to upsample by 4x with sinc interpolation
        let upsampledCount = samples.count * oversampleFactor
        var upsampled = [Float](repeating: 0, count: upsampledCount)

        // Simple polyphase approach: zero-stuff then filter
        // Insert original samples at every 4th position
        for i in 0 ..< samples.count {
            upsampled[i * oversampleFactor] = samples[i]
        }

        // Apply lowpass FIR filter for reconstruction
        // Using a simple windowed sinc (Hann window, 16 taps per phase = 64 total)
        let filterLength = 64
        var filter = [Float](repeating: 0, count: filterLength + 1)
        let halfLength = Float(filterLength) / 2.0

        for i in 0 ... filterLength {
            let x = Float(i) - halfLength
            // Sinc function
            let sinc: Float = (x == 0) ? 1.0 : sinf(.pi * x / Float(oversampleFactor)) / (.pi * x / Float(oversampleFactor))
            // Hann window
            let window = 0.5 * (1.0 - cosf(2.0 * .pi * Float(i) / Float(filterLength)))
            filter[i] = sinc * window
        }

        // Normalize the filter to maintain unity gain
        var filterSum: Float = 0
        vDSP_sve(filter, 1, &filterSum, vDSP_Length(filter.count))
        if filterSum > 0 {
            var normFactor = Float(oversampleFactor) / filterSum
            vDSP_vsmul(filter, 1, &normFactor, &filter, 1, vDSP_Length(filter.count))
        }

        // Convolve using vDSP
        var filtered = [Float](repeating: 0, count: upsampledCount)
        vDSP_conv(upsampled, 1, filter, 1, &filtered, 1,
                  vDSP_Length(upsampledCount - filterLength), vDSP_Length(filterLength + 1))

        // Find absolute maximum
        var maxVal: Float = 0
        vDSP_maxmgv(filtered, 1, &maxVal, vDSP_Length(filtered.count))

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

    /// Calculate loudness range from pre-computed short-term loudness values
    private func calculateLoudnessRangeFromValues(_ values: [Float]) -> Float {
        guard values.count >= 2 else { return 0 }
        var sorted = values.sorted()
        let lowIndex = Int(Float(sorted.count) * 0.10)
        let highIndex = Int(Float(sorted.count) * 0.95)
        return sorted[highIndex] - sorted[lowIndex]
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
            let window = Array(samples[position ..< (position + windowSize)])
            let meanSquare = calculateMeanSquare(samples: window)
            let lufs = meanSquareToLUFS(meanSquare)
            if lufs.isFinite, lufs > -70 { // Gate very quiet sections
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
            "Failed to create audio buffer for LUFS analysis"
        case let .analysisError(message):
            "LUFS analysis error: \(message)"
        }
    }
}
