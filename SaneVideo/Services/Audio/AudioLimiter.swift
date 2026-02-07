//
//  AudioLimiter.swift
//  SaneVideo
//
//  Audio limiter using MTAudioProcessingTap to prevent clipping during export.
//  Applied to AVAudioMix to limit peaks when multiple audio tracks are mixed.
//

import AVFoundation
import MediaToolbox

/// Audio limiter that prevents clipping when multiple tracks are mixed.
/// Uses soft-knee limiting for transparent peak control.
enum AudioLimiter {
    // MARK: - Configuration

    /// Limiter threshold in dB (signals above this will be limited)
    private static let thresholdDB: Float = -1.0

    /// Attack time in seconds (how quickly limiter engages)
    private static let attackTime: Float = 0.005

    /// Release time in seconds (how quickly limiter releases)
    private static let releaseTime: Float = 0.100

    /// Soft knee width in dB (gradual transition into limiting)
    private static let kneeWidthDB: Float = 6.0

    // MARK: - Limiter State

    /// State object for the limiter envelope follower
    private final class LimiterState {
        var envelope: Float = 0.0 // Gain reduction in dB (0 = no reduction, negative = reduction)
        var sampleRate: Float = 44100.0
        var attackCoeff: Float = 0.0
        var releaseCoeff: Float = 0.0

        func precomputeCoefficients() {
            attackCoeff = expf(-1.0 / (AudioLimiter.attackTime * sampleRate))
            releaseCoeff = expf(-1.0 / (AudioLimiter.releaseTime * sampleRate))
        }
    }

    // MARK: - Public Interface

    /// Apply a limiting audio processing tap to an AVMutableAudioMix.
    /// This prevents clipping when multiple audio tracks sum above 0 dB.
    ///
    /// - Parameter audioMix: The audio mix to add limiting to
    /// - Returns: Modified audio mix with limiter tap, or original if tap creation fails
    static func applyLimiter(to audioMix: AVMutableAudioMix) -> AVMutableAudioMix {
        guard !audioMix.inputParameters.isEmpty else {
            return audioMix
        }

        var modifiedParams: [AVMutableAudioMixInputParameters] = []

        for params in audioMix.inputParameters {
            // Try to create a mutable copy for adding the tap
            guard let mutableParams = params.mutableCopy() as? AVMutableAudioMixInputParameters else {
                // If we can't create mutable copy, skip this track's limiter
                // The params are already AVMutableAudioMixInputParameters from inputParameters
                if let existingMutable = params as? AVMutableAudioMixInputParameters {
                    modifiedParams.append(existingMutable)
                }
                continue
            }

            // Create processing tap for this track
            if let tap = createLimiterTap() {
                mutableParams.audioTapProcessor = tap
            }

            modifiedParams.append(mutableParams)
        }

        let newAudioMix = AVMutableAudioMix()
        newAudioMix.inputParameters = modifiedParams
        return newAudioMix
    }

    // MARK: - MTAudioProcessingTap

    /// Create an MTAudioProcessingTap that applies peak limiting
    private static func createLimiterTap() -> MTAudioProcessingTap? {
        // Create limiter state
        let limiterState = LimiterState()

        // Callbacks struct
        var callbacks = MTAudioProcessingTapCallbacks(
            version: kMTAudioProcessingTapCallbacksVersion_0,
            clientInfo: UnsafeMutableRawPointer(Unmanaged.passRetained(limiterState).toOpaque()),
            init: { _, clientInfo, tapStorageOut in
                // Initialize tap storage with client info
                tapStorageOut.pointee = clientInfo
            },
            finalize: { tap in
                // Clean up state
                let storage = MTAudioProcessingTapGetStorage(tap)
                Unmanaged<LimiterState>.fromOpaque(storage).release()
            },
            prepare: { tap, _, processingFormat in
                // Store sample rate and precompute coefficients
                let storage = MTAudioProcessingTapGetStorage(tap)
                let state = Unmanaged<LimiterState>.fromOpaque(storage).takeUnretainedValue()
                state.sampleRate = Float(processingFormat.pointee.mSampleRate)
                state.precomputeCoefficients()
            },
            unprepare: { _ in },
            process: limiterProcessCallback
        )

        var tap: MTAudioProcessingTap?
        let status = MTAudioProcessingTapCreate(
            kCFAllocatorDefault,
            &callbacks,
            kMTAudioProcessingTapCreationFlag_PreEffects,
            &tap
        )

        guard status == noErr, let createdTap = tap else {
            AppLogger.audio.warning("Failed to create audio limiter tap: \(status)")
            return nil
        }

        return createdTap
    }

    /// Process callback for the audio processing tap
    /// Uses two-pass stereo linking: find peak across all channels, apply same gain to all
    private static let limiterProcessCallback: MTAudioProcessingTapProcessCallback = { tap, numberFrames, _, bufferListInOut, numberFramesOut, _ in
        // Get source audio
        var sourceFlags = MTAudioProcessingTapFlags()
        let status = MTAudioProcessingTapGetSourceAudio(
            tap,
            numberFrames,
            bufferListInOut,
            &sourceFlags,
            nil,
            numberFramesOut
        )

        guard status == noErr else { return }

        // Get limiter state
        let storage = MTAudioProcessingTapGetStorage(tap)
        let state = Unmanaged<LimiterState>.fromOpaque(storage).takeUnretainedValue()

        let bufferList = UnsafeMutableAudioBufferListPointer(bufferListInOut)

        // Pass 1: Find peak level across all channels for each frame
        let frameCount = bufferList.first.map { Int($0.mDataByteSize) / MemoryLayout<Float>.size } ?? 0
        guard frameCount > 0 else { return }

        // Allocate peak buffer (real-time safe for reasonable frame counts)
        let peakBuffer = UnsafeMutablePointer<Float>.allocate(capacity: frameCount)
        defer { peakBuffer.deallocate() }

        // Initialize with first channel
        if let firstData = bufferList.first?.mData {
            let firstSamples = firstData.assumingMemoryBound(to: Float.self)
            for i in 0 ..< frameCount {
                peakBuffer[i] = abs(firstSamples[i])
            }
        }

        // Max across remaining channels
        for bufIdx in 1 ..< bufferList.count {
            guard let data = bufferList[bufIdx].mData else { continue }
            let samples = data.assumingMemoryBound(to: Float.self)
            let count = Int(bufferList[bufIdx].mDataByteSize) / MemoryLayout<Float>.size
            for i in 0 ..< min(count, frameCount) {
                peakBuffer[i] = max(peakBuffer[i], abs(samples[i]))
            }
        }

        // Compute gain array once from peak envelope
        let gainBuffer = UnsafeMutablePointer<Float>.allocate(capacity: frameCount)
        defer { gainBuffer.deallocate() }
        computeGains(peakSamples: peakBuffer, frameCount: frameCount, gains: gainBuffer, state: state)

        // Pass 2: Apply same gain to all channels
        for buffer in bufferList {
            guard let data = buffer.mData else { continue }
            let samples = data.assumingMemoryBound(to: Float.self)
            let count = Int(buffer.mDataByteSize) / MemoryLayout<Float>.size
            for i in 0 ..< count {
                samples[i] *= gainBuffer[i]
            }
        }
    }

    /// Compute gain reduction array from peak samples using dB-domain soft-knee limiting
    /// Updates the state envelope and fills the gains buffer
    private static func computeGains(
        peakSamples: UnsafePointer<Float>,
        frameCount: Int,
        gains: UnsafeMutablePointer<Float>,
        state: LimiterState
    ) {
        let kneeStart = thresholdDB - kneeWidthDB // -7.0 dB (when threshold = -1.0, knee = 6.0)

        for i in 0 ..< frameCount {
            let inputLevel = peakSamples[i]

            // Convert to dB (floor at -96dB to avoid log(0))
            let inputDB = 20.0 * log10f(max(inputLevel, 1e-5))

            // Calculate target gain reduction in dB
            var gainReductionDB: Float = 0.0

            if inputDB > thresholdDB {
                // Above threshold: hard limit
                gainReductionDB = thresholdDB - inputDB
            } else if inputDB > kneeStart {
                // Knee region: quadratic soft transition (always reduces, never boosts)
                let x = inputDB - kneeStart
                gainReductionDB = -0.5 * (x * x) / kneeWidthDB
            }
            // Below knee: gainReductionDB stays 0 (unity gain)

            // Smooth envelope (attack/release in dB domain)
            if gainReductionDB < state.envelope {
                // Attack: fast response to peaks (more negative = more reduction)
                state.envelope = state.attackCoeff * state.envelope + (1.0 - state.attackCoeff) * gainReductionDB
            } else {
                // Release: slower return to 0 dB
                state.envelope = state.releaseCoeff * state.envelope + (1.0 - state.releaseCoeff) * gainReductionDB
            }

            // Convert dB gain to linear and store
            gains[i] = powf(10.0, state.envelope / 20.0)
        }
    }

    // MARK: - Utility

    /// Check if audio samples would clip (for diagnostics)
    static func detectClipping(in buffer: CMSampleBuffer) -> Bool {
        guard let blockBuffer = CMSampleBufferGetDataBuffer(buffer) else { return false }

        var length = 0
        var dataPointer: UnsafeMutablePointer<Int8>?
        CMBlockBufferGetDataPointer(blockBuffer, atOffset: 0, lengthAtOffsetOut: nil, totalLengthOut: &length, dataPointerOut: &dataPointer)

        guard let data = dataPointer else { return false }

        let floatCount = length / MemoryLayout<Float>.size
        let samples = UnsafePointer<Float>(OpaquePointer(data))

        for i in 0 ..< floatCount where abs(samples[i]) > 1.0 {
            return true
        }

        return false
    }
}
