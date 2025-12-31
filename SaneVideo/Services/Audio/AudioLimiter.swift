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
        var envelope: Float = 1.0
        var sampleRate: Float = 44100.0
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
                // Store sample rate for envelope calculations
                let storage = MTAudioProcessingTapGetStorage(tap)
                let state = Unmanaged<LimiterState>.fromOpaque(storage).takeUnretainedValue()
                state.sampleRate = Float(processingFormat.pointee.mSampleRate)
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
    private static let limiterProcessCallback: MTAudioProcessingTapProcessCallback = {
        tap, numberFrames, _, bufferListInOut, numberFramesOut, _ in

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

        // Process each buffer in the list
        let bufferList = UnsafeMutableAudioBufferListPointer(bufferListInOut)
        for buffer in bufferList {
            guard let data = buffer.mData else { continue }

            let frameCount = Int(buffer.mDataByteSize) / MemoryLayout<Float>.size
            let samples = data.assumingMemoryBound(to: Float.self)

            // Apply soft-knee limiting
            applyLimiting(
                samples: samples,
                frameCount: frameCount,
                state: state
            )
        }
    }

    /// Apply soft-knee peak limiting to audio samples
    private static func applyLimiting(
        samples: UnsafeMutablePointer<Float>,
        frameCount: Int,
        state: LimiterState
    ) {
        let threshold = powf(10.0, thresholdDB / 20.0)
        let attackCoeff = expf(-1.0 / (attackTime * state.sampleRate))
        let releaseCoeff = expf(-1.0 / (releaseTime * state.sampleRate))
        let kneeWidth = powf(10.0, kneeWidthDB / 20.0) - 1.0

        for i in 0..<frameCount {
            let inputSample = samples[i]
            let inputLevel = abs(inputSample)

            // Calculate target gain based on input level
            var targetGain: Float = 1.0

            if inputLevel > threshold {
                // Above threshold: apply limiting
                targetGain = threshold / inputLevel
            } else if inputLevel > threshold - kneeWidth {
                // In knee region: soft transition
                let kneeRatio = (inputLevel - (threshold - kneeWidth)) / kneeWidth
                let limitedGain = threshold / inputLevel
                targetGain = 1.0 + (limitedGain - 1.0) * kneeRatio * kneeRatio
            }

            // Smooth envelope following (attack/release)
            if targetGain < state.envelope {
                // Attack: fast response to peaks
                state.envelope = attackCoeff * state.envelope + (1.0 - attackCoeff) * targetGain
            } else {
                // Release: slower return to unity
                state.envelope = releaseCoeff * state.envelope + (1.0 - releaseCoeff) * targetGain
            }

            // Apply gain
            samples[i] = inputSample * state.envelope
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

        for i in 0..<floatCount {
            if abs(samples[i]) > 1.0 {
                return true
            }
        }

        return false
    }
}
