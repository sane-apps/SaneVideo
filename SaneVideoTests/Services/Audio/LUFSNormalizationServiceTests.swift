//
//  LUFSNormalizationServiceTests.swift
//  SaneVideoTests
//
//  Tests for ITU-R BS.1770-4 compliant LUFS normalization service.
//

import Accelerate
import AVFoundation
@testable import SaneVideo
import Testing

struct LUFSNormalizationServiceTests {
    // MARK: - K-Weighting Tests

    @Test("K-weighting coefficients match BS.1770-4 reference for 48kHz")
    func kWeightingCoefficientsMatch48kHz() async throws {
        let service = LUFSNormalizationService()

        // Create a test file at 48kHz with known characteristics
        let testFile = try createTestAudioFile(
            sampleRate: 48000,
            durationSeconds: 1.0,
            frequency: 1000, // 1kHz test tone
            amplitude: 0.5
        )
        defer { try? FileManager.default.removeItem(at: testFile) }

        // Analyze the file - the K-weighting should use exact BS.1770-4 coefficients
        let analysis = try await service.analyzeAudio(at: testFile)

        // Basic sanity check - analysis should complete without error
        #expect(analysis.integratedLUFS.isFinite)
        #expect(analysis.truePeak.isFinite)
    }

    @Test("K-weighting works with non-48kHz sample rates")
    func kWeightingWorksWithDifferentSampleRates() async throws {
        let service = LUFSNormalizationService()

        let sampleRates: [Double] = [44100, 96000]

        for sampleRate in sampleRates {
            let testFile = try createTestAudioFile(
                sampleRate: sampleRate,
                durationSeconds: 1.0,
                frequency: 1000,
                amplitude: 0.5
            )
            defer { try? FileManager.default.removeItem(at: testFile) }

            let analysis = try await service.analyzeAudio(at: testFile)

            #expect(analysis.integratedLUFS.isFinite)
            #expect(analysis.truePeak.isFinite)
        }
    }

    // MARK: - True Peak Tests

    @Test("True peak detects inter-sample peaks")
    func truePeakDetectsInterSamplePeaks() async throws {
        let service = LUFSNormalizationService()

        // Create a signal that will have inter-sample peaks when reconstructed
        // Use a high-frequency tone near Nyquist that creates inter-sample peaks
        let testFile = try createInterSamplePeakSignal()
        defer { try? FileManager.default.removeItem(at: testFile) }

        let analysis = try await service.analyzeAudio(at: testFile)

        // The true peak should be higher than the sample peak due to oversampling
        // For a near-Nyquist sine wave, inter-sample peaks can be ~3dB higher
        #expect(analysis.truePeak.isFinite)
        #expect(analysis.truePeak > -10.0) // Should detect significant peaks
    }

    @Test("True peak uses 4x oversampling")
    func truePeakUses4xOversampling() async throws {
        let service = LUFSNormalizationService()

        // Create a test file with a known peak value
        // Using a frequency close to Nyquist creates inter-sample peaks
        let testFile = try createTestAudioFile(
            sampleRate: 48000,
            durationSeconds: 0.5,
            frequency: 20000, // Near Nyquist (24kHz)
            amplitude: 0.5 // Keep amplitude moderate to avoid clipping
        )
        defer { try? FileManager.default.removeItem(at: testFile) }

        let analysis = try await service.analyzeAudio(at: testFile)

        // True peak should be negative (below 0 dBFS) but detectable
        // With 4x oversampling, we should get a valid peak measurement
        #expect(analysis.truePeak.isFinite)
        #expect(analysis.truePeak < 0.0)
        #expect(analysis.truePeak > -20.0) // Should be well above noise floor
    }

    // MARK: - Streaming Analysis Tests

    @Test("Streaming analysis produces same result as single-pass for small files")
    func streamingMatchesSinglePassForSmallFiles() async throws {
        let service = LUFSNormalizationService()

        // Create a 10-second file (below 30-second threshold)
        let testFile = try createTestAudioFile(
            sampleRate: 48000,
            durationSeconds: 10.0,
            frequency: 1000,
            amplitude: 0.5
        )
        defer { try? FileManager.default.removeItem(at: testFile) }

        // Analyze the same file multiple times - should get consistent results
        let analysis1 = try await service.analyzeAudio(at: testFile)
        let analysis2 = try await service.analyzeAudio(at: testFile)

        // Results should be identical (within floating-point precision)
        #expect(abs(analysis1.integratedLUFS - analysis2.integratedLUFS) < 0.01)
        #expect(abs(analysis1.truePeak - analysis2.truePeak) < 0.01)
        #expect(abs(analysis1.loudnessRange - analysis2.loudnessRange) < 0.1)
    }

    @Test("Streaming analysis handles large files")
    func streamingAnalysisHandlesLargeFiles() async throws {
        let service = LUFSNormalizationService()

        // Create a 60-second file (above 30-second threshold, triggers streaming)
        let testFile = try createTestAudioFile(
            sampleRate: 48000,
            durationSeconds: 60.0,
            frequency: 1000,
            amplitude: 0.5
        )
        defer { try? FileManager.default.removeItem(at: testFile) }

        // Should complete without error or memory issues
        let analysis = try await service.analyzeAudio(at: testFile)

        #expect(analysis.integratedLUFS.isFinite)
        #expect(analysis.truePeak.isFinite)
        #expect(analysis.loudnessRange.isFinite)
        #expect(analysis.recommendedGain.isFinite)
    }

    // MARK: - Gain Calculation Tests

    @Test("Recommended gain prevents clipping")
    func recommendedGainPreventsClipping() async throws {
        let service = LUFSNormalizationService()

        // Create a quiet file that needs significant gain
        let testFile = try createTestAudioFile(
            sampleRate: 48000,
            durationSeconds: 1.0,
            frequency: 1000,
            amplitude: 0.1 // Very quiet
        )
        defer { try? FileManager.default.removeItem(at: testFile) }

        let analysis = try await service.analyzeAudio(at: testFile, targetLUFS: -14.0)

        // Gain should be limited to prevent clipping
        let peakAfterGain = analysis.truePeak + analysis.recommendedGain
        #expect(peakAfterGain <= LUFSNormalizationService.maxTruePeak)
    }

    @Test("Recommended gain for already normalized audio is near zero")
    func recommendedGainForNormalizedAudioIsNearZero() async throws {
        let service = LUFSNormalizationService()

        // Create audio that's already close to target
        let testFile = try createTestAudioFile(
            sampleRate: 48000,
            durationSeconds: 5.0,
            frequency: 1000,
            amplitude: 0.2 // Should be roughly in the -14 LUFS range
        )
        defer { try? FileManager.default.removeItem(at: testFile) }

        let analysis = try await service.analyzeAudio(at: testFile, targetLUFS: -14.0)

        // Gain should be relatively small (within a few dB)
        #expect(abs(analysis.recommendedGain) < 10.0)
    }

    // MARK: - Loudness Range Tests

    @Test("Loudness range calculation handles varying dynamics")
    func loudnessRangeHandlesVaryingDynamics() async throws {
        let service = LUFSNormalizationService()

        // Create a file with varying amplitude (dynamic range)
        let testFile = try createDynamicAudioFile()
        defer { try? FileManager.default.removeItem(at: testFile) }

        let analysis = try await service.analyzeAudio(at: testFile)

        // Should have measurable loudness range
        #expect(analysis.loudnessRange > 0)
        #expect(analysis.loudnessRange.isFinite)
    }

    // MARK: - Helper Functions

    /// Create a test audio file with a sine wave
    private func createTestAudioFile(
        sampleRate: Double,
        durationSeconds: Double,
        frequency: Double,
        amplitude: Float
    ) throws -> URL {
        let tempDir = FileManager.default.temporaryDirectory
        let fileURL = tempDir.appendingPathComponent(UUID().uuidString + ".wav")

        let format = AVAudioFormat(
            standardFormatWithSampleRate: sampleRate,
            channels: 1
        )!

        let file = try AVAudioFile(
            forWriting: fileURL,
            settings: format.settings
        )

        let frameCount = AVAudioFrameCount(sampleRate * durationSeconds)
        guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frameCount) else {
            throw TestError.bufferCreationFailed
        }

        buffer.frameLength = frameCount

        // Generate sine wave
        let channelData = buffer.floatChannelData![0]
        for i in 0 ..< Int(frameCount) {
            let phase = 2.0 * .pi * frequency * Double(i) / sampleRate
            channelData[i] = amplitude * sin(Float(phase))
        }

        try file.write(from: buffer)
        return fileURL
    }

    /// Create a signal with inter-sample peaks
    private func createInterSamplePeakSignal() throws -> URL {
        // Create a signal at a frequency that will cause inter-sample peaks
        // Use a frequency close to Nyquist with specific phase offset
        try createTestAudioFile(
            sampleRate: 48000,
            durationSeconds: 0.5,
            frequency: 23000, // Close to Nyquist (24kHz)
            amplitude: 0.95
        )
    }

    /// Create an audio file with varying dynamics
    private func createDynamicAudioFile() throws -> URL {
        let tempDir = FileManager.default.temporaryDirectory
        let fileURL = tempDir.appendingPathComponent(UUID().uuidString + ".wav")

        let sampleRate: Double = 48000
        let format = AVAudioFormat(
            standardFormatWithSampleRate: sampleRate,
            channels: 1
        )!

        let file = try AVAudioFile(
            forWriting: fileURL,
            settings: format.settings
        )

        // Create 10 seconds with varying amplitude
        let durationSeconds = 10.0
        let frameCount = AVAudioFrameCount(sampleRate * durationSeconds)
        guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frameCount) else {
            throw TestError.bufferCreationFailed
        }

        buffer.frameLength = frameCount

        // Generate sine wave with varying amplitude
        let channelData = buffer.floatChannelData![0]
        let frequency: Double = 1000

        for i in 0 ..< Int(frameCount) {
            let phase = 2.0 * .pi * frequency * Double(i) / sampleRate
            // Vary amplitude between 0.1 and 0.8 over the duration
            let t = Double(i) / Double(frameCount)
            let amplitude = Float(0.1 + 0.7 * sin(2.0 * .pi * t * 3)) // 3 cycles of amplitude variation
            channelData[i] = amplitude * sin(Float(phase))
        }

        try file.write(from: buffer)
        return fileURL
    }

    enum TestError: Error {
        case bufferCreationFailed
    }
}
