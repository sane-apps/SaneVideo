@preconcurrency import AVFoundation

/// Utility that normalizes incoming CMSampleBuffers to a single sample rate so
/// the VideoWriter always receives audio that matches its AAC configuration.
final class AudioResampler {
    private let targetSampleRate: Double
    private var converter: AVAudioConverter?
    private var cachedInput: FormatDescriptor?
    private var cachedOutput: FormatDescriptor?

    init(targetSampleRate: Double) {
        self.targetSampleRate = targetSampleRate
    }

    /// Returns the original sample buffer when no conversion is required, or
    /// a resampled buffer when ScreenCaptureKit delivers 48 kHz audio.
    func resampleIfNeeded(_ sampleBuffer: CMSampleBuffer) -> CMSampleBuffer? {
        guard let formatDesc = CMSampleBufferGetFormatDescription(sampleBuffer),
              let asbd = CMAudioFormatDescriptionGetStreamBasicDescription(formatDesc)
        else {
            return sampleBuffer
        }

        let currentSampleRate = asbd.pointee.mSampleRate
        guard currentSampleRate != targetSampleRate else { return sampleBuffer }

        guard let inputFormat = AVAudioFormat(streamDescription: asbd) else { return sampleBuffer }
        guard let outputFormat = AVAudioFormat(commonFormat: .pcmFormatFloat32,
                                               sampleRate: targetSampleRate,
                                               channels: inputFormat.channelCount,
                                               interleaved: true) else { return sampleBuffer }

        let inputDescriptor = FormatDescriptor(format: inputFormat)
        let outputDescriptor = FormatDescriptor(format: outputFormat)

        if converter == nil || cachedInput != inputDescriptor || cachedOutput != outputDescriptor {
            converter = AVAudioConverter(from: inputFormat, to: outputFormat)
            cachedInput = inputDescriptor
            cachedOutput = outputDescriptor
        }

        guard let converter else { return sampleBuffer }
        guard let pcmBuffer = AVAudioPCMBuffer(sampleBuffer: sampleBuffer) else { return sampleBuffer }

        let ratio = targetSampleRate / currentSampleRate
        let estimatedCapacity = AVAudioFrameCount((Double(pcmBuffer.frameLength) * ratio).rounded(.up))
        guard let outputBuffer = AVAudioPCMBuffer(pcmFormat: outputFormat, frameCapacity: estimatedCapacity) else {
            return sampleBuffer
        }

        // Use a class box for mutable state to satisfy concurrency requirements
        final class InputState: @unchecked Sendable {
            var isConsumed = false
        }
        let inputState = InputState()
        var conversionError: NSError?
        converter.convert(to: outputBuffer, error: &conversionError) { _, outStatus in
            guard !inputState.isConsumed else {
                outStatus.pointee = .noDataNow
                return nil
            }
            inputState.isConsumed = true
            outStatus.pointee = .haveData
            return pcmBuffer
        }

        if let conversionError {
            AppLogger.recording.error("AudioResampler: conversion failed - \(conversionError.localizedDescription)")
            return sampleBuffer
        }

        outputBuffer.frameLength = outputBuffer.frameLength == 0 ? outputBuffer.frameCapacity : outputBuffer.frameLength
        return CMSampleBuffer.make(from: outputBuffer, reference: sampleBuffer) ?? sampleBuffer
    }
}

private struct FormatDescriptor: Equatable {
    let sampleRate: Double
    let channels: AVAudioChannelCount
    let commonFormat: AVAudioCommonFormat
    let interleaved: Bool

    init(format: AVAudioFormat) {
        sampleRate = format.sampleRate
        channels = format.channelCount
        commonFormat = format.commonFormat
        interleaved = format.isInterleaved
    }
}

private extension AVAudioPCMBuffer {
    convenience init?(sampleBuffer: CMSampleBuffer) {
        guard let formatDesc = CMSampleBufferGetFormatDescription(sampleBuffer),
              let asbd = CMAudioFormatDescriptionGetStreamBasicDescription(formatDesc) else { return nil }

        guard let format = AVAudioFormat(streamDescription: asbd) else { return nil }
        let frameCount = AVAudioFrameCount(CMSampleBufferGetNumSamples(sampleBuffer))

        self.init(pcmFormat: format, frameCapacity: frameCount)
        frameLength = frameCount

        let status = CMSampleBufferCopyPCMDataIntoAudioBufferList(
            sampleBuffer,
            at: 0,
            frameCount: Int32(frameCount),
            into: mutableAudioBufferList
        )

        if status != noErr {
            return nil
        }
    }
}

private extension CMSampleBuffer {
    static func make(from buffer: AVAudioPCMBuffer, reference: CMSampleBuffer) -> CMSampleBuffer? {
        let audioBuffers = UnsafeMutableAudioBufferListPointer(buffer.mutableAudioBufferList)
        let totalLength = audioBuffers.reduce(0) { $0 + Int($1.mDataByteSize) }

        var blockBuffer: CMBlockBuffer?
        guard CMBlockBufferCreateWithMemoryBlock(
            allocator: kCFAllocatorDefault,
            memoryBlock: nil,
            blockLength: totalLength,
            blockAllocator: nil,
            customBlockSource: nil,
            offsetToData: 0,
            dataLength: totalLength,
            flags: 0,
            blockBufferOut: &blockBuffer
        ) == kCMBlockBufferNoErr, let blockBuffer else { return nil }

        var currentOffset = 0
        for audioBuffer in audioBuffers {
            guard let data = audioBuffer.mData else { return nil }
            let length = Int(audioBuffer.mDataByteSize)
            let result = CMBlockBufferReplaceDataBytes(
                with: data,
                blockBuffer: blockBuffer,
                offsetIntoDestination: currentOffset,
                dataLength: length
            )
            guard result == kCMBlockBufferNoErr else { return nil }
            currentOffset += length
        }

        var asbd = buffer.format.streamDescription.pointee
        var formatDesc: CMAudioFormatDescription?
        guard CMAudioFormatDescriptionCreate(
            allocator: kCFAllocatorDefault,
            asbd: &asbd,
            layoutSize: 0,
            layout: nil,
            magicCookieSize: 0,
            magicCookie: nil,
            extensions: nil,
            formatDescriptionOut: &formatDesc
        ) == noErr, let formatDesc else { return nil }

        let sampleCount = CMItemCount(buffer.frameLength)
        let pts = CMSampleBufferGetPresentationTimeStamp(reference)
        let dts = CMSampleBufferGetDecodeTimeStamp(reference)

        var timing = CMSampleTimingInfo(
            duration: CMTime(value: 1, timescale: CMTimeScale(buffer.format.sampleRate)),
            presentationTimeStamp: pts,
            decodeTimeStamp: dts
        )

        var newSample: CMSampleBuffer?
        guard CMSampleBufferCreateReady(
            allocator: kCFAllocatorDefault,
            dataBuffer: blockBuffer,
            formatDescription: formatDesc,
            sampleCount: sampleCount,
            sampleTimingEntryCount: 1,
            sampleTimingArray: &timing,
            sampleSizeEntryCount: 0,
            sampleSizeArray: nil,
            sampleBufferOut: &newSample
        ) == noErr else { return nil }

        return newSample
    }
}
