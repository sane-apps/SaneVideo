import AVFoundation
import CoreMedia
import CoreVideo
import Foundation

/// Small synthetic media files and buffers for tests. Everything goes in a fresh temp folder.
enum TestMedia {
    struct MediaError: Error, CustomStringConvertible {
        let description: String
    }

    /// A new, empty folder under the temp directory. The caller removes it.
    static func makeTempDirectory(_ name: String = "SaneVideoTests") throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("\(name)-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    /// Writes a mono 16-bit WAV made of tone and silence segments, in order.
    /// Tone is a 440 Hz sine at half scale (about -9 dB RMS); silence is digital zero.
    static func writeToneAndSilence(
        _ segments: [(isTone: Bool, seconds: Double)],
        to url: URL,
        sampleRate: Double = 44100
    ) throws {
        let settings: [String: Any] = [
            AVFormatIDKey: kAudioFormatLinearPCM,
            AVSampleRateKey: sampleRate,
            AVNumberOfChannelsKey: 1,
            AVLinearPCMBitDepthKey: 16,
            AVLinearPCMIsFloatKey: false,
            AVLinearPCMIsBigEndianKey: false
        ]
        let file = try AVAudioFile(forWriting: url, settings: settings, commonFormat: .pcmFormatFloat32, interleaved: false)
        let format = file.processingFormat
        var sampleIndex = 0
        for segment in segments {
            let frames = AVAudioFrameCount(segment.seconds * sampleRate)
            guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frames),
                  let channel = buffer.floatChannelData?[0]
            else {
                throw MediaError(description: "Could not allocate an audio buffer")
            }
            buffer.frameLength = frames
            for frame in 0 ..< Int(frames) {
                channel[frame] = segment.isTone
                    ? 0.5 * Float(sin(2 * Double.pi * 440 * Double(sampleIndex + frame) / sampleRate))
                    : 0
            }
            sampleIndex += Int(frames)
            try file.write(from: buffer)
        }
        file.close()
    }

    /// A BGRA pixel buffer filled with one gray level.
    static func pixelBuffer(width: Int, height: Int, gray: UInt8) throws -> CVPixelBuffer {
        let attributes: [CFString: Any] = [
            kCVPixelBufferCGImageCompatibilityKey: true,
            kCVPixelBufferCGBitmapContextCompatibilityKey: true,
            kCVPixelBufferIOSurfacePropertiesKey: [:] as CFDictionary
        ]
        var buffer: CVPixelBuffer?
        let status = CVPixelBufferCreate(
            kCFAllocatorDefault, width, height, kCVPixelFormatType_32BGRA, attributes as CFDictionary, &buffer
        )
        guard status == kCVReturnSuccess, let buffer else {
            throw MediaError(description: "CVPixelBufferCreate failed: \(status)")
        }
        CVPixelBufferLockBaseAddress(buffer, [])
        defer { CVPixelBufferUnlockBaseAddress(buffer, []) }
        if let base = CVPixelBufferGetBaseAddress(buffer) {
            memset(base, Int32(gray), CVPixelBufferGetBytesPerRow(buffer) * height)
        }
        return buffer
    }

    /// Wraps a pixel buffer in a sample buffer stamped at `time`.
    static func videoSampleBuffer(_ pixelBuffer: CVPixelBuffer, at time: CMTime, frameDuration: CMTime) throws -> CMSampleBuffer {
        var format: CMVideoFormatDescription?
        let formatStatus = CMVideoFormatDescriptionCreateForImageBuffer(
            allocator: kCFAllocatorDefault, imageBuffer: pixelBuffer, formatDescriptionOut: &format
        )
        guard formatStatus == noErr, let format else {
            throw MediaError(description: "Video format description failed: \(formatStatus)")
        }
        var timing = CMSampleTimingInfo(duration: frameDuration, presentationTimeStamp: time, decodeTimeStamp: .invalid)
        var sample: CMSampleBuffer?
        let status = CMSampleBufferCreateReadyWithImageBuffer(
            allocator: kCFAllocatorDefault, imageBuffer: pixelBuffer, formatDescription: format,
            sampleTiming: &timing, sampleBufferOut: &sample
        )
        guard status == noErr, let sample else {
            throw MediaError(description: "Video sample buffer failed: \(status)")
        }
        return sample
    }

    /// Interleaved 16-bit stereo PCM at 48 kHz holding a 440 Hz tone, starting at `startFrame`.
    static func pcmSampleBuffer(frames: Int, startFrame: Int, sampleRate: Double = 48000) throws -> CMSampleBuffer {
        let channels = 2
        var asbd = AudioStreamBasicDescription(
            mSampleRate: sampleRate,
            mFormatID: kAudioFormatLinearPCM,
            mFormatFlags: kLinearPCMFormatFlagIsSignedInteger | kAudioFormatFlagIsPacked,
            mBytesPerPacket: UInt32(2 * channels),
            mFramesPerPacket: 1,
            mBytesPerFrame: UInt32(2 * channels),
            mChannelsPerFrame: UInt32(channels),
            mBitsPerChannel: 16,
            mReserved: 0
        )
        var format: CMAudioFormatDescription?
        let formatStatus = CMAudioFormatDescriptionCreate(
            allocator: kCFAllocatorDefault, asbd: &asbd, layoutSize: 0, layout: nil,
            magicCookieSize: 0, magicCookie: nil, extensions: nil, formatDescriptionOut: &format
        )
        guard formatStatus == noErr, let format else {
            throw MediaError(description: "Audio format description failed: \(formatStatus)")
        }

        var samples = [Int16](repeating: 0, count: frames * channels)
        for frame in 0 ..< frames {
            let value = Int16(8000 * sin(2 * Double.pi * 440 * Double(startFrame + frame) / sampleRate))
            samples[frame * channels] = value
            samples[frame * channels + 1] = value
        }
        let byteCount = samples.count * MemoryLayout<Int16>.size

        var block: CMBlockBuffer?
        let blockStatus = CMBlockBufferCreateWithMemoryBlock(
            allocator: kCFAllocatorDefault, memoryBlock: nil, blockLength: byteCount, blockAllocator: nil,
            customBlockSource: nil, offsetToData: 0, dataLength: byteCount,
            flags: kCMBlockBufferAssureMemoryNowFlag, blockBufferOut: &block
        )
        guard blockStatus == kCMBlockBufferNoErr, let block else {
            throw MediaError(description: "Block buffer failed: \(blockStatus)")
        }
        let copyStatus = samples.withUnsafeBytes { bytes in
            CMBlockBufferReplaceDataBytes(
                with: bytes.baseAddress!, blockBuffer: block, offsetIntoDestination: 0, dataLength: byteCount
            )
        }
        guard copyStatus == kCMBlockBufferNoErr else {
            throw MediaError(description: "Block copy failed: \(copyStatus)")
        }

        var sample: CMSampleBuffer?
        let status = CMAudioSampleBufferCreateReadyWithPacketDescriptions(
            allocator: kCFAllocatorDefault, dataBuffer: block, formatDescription: format,
            sampleCount: frames,
            presentationTimeStamp: CMTime(value: CMTimeValue(startFrame), timescale: CMTimeScale(sampleRate)),
            packetDescriptions: nil, sampleBufferOut: &sample
        )
        guard status == noErr, let sample else {
            throw MediaError(description: "Audio sample buffer failed: \(status)")
        }
        return sample
    }

    /// Writes a silent H.264 MP4 of `frameCount` gray frames at `fps`, with plain AVAssetWriter.
    static func writeVideo(to url: URL, width: Int, height: Int, fps: Int32, frameCount: Int) async throws {
        let writer = try AVAssetWriter(outputURL: url, fileType: .mp4)
        let input = AVAssetWriterInput(mediaType: .video, outputSettings: [
            AVVideoCodecKey: AVVideoCodecType.h264,
            AVVideoWidthKey: width,
            AVVideoHeightKey: height
        ])
        input.expectsMediaDataInRealTime = false
        let adaptor = AVAssetWriterInputPixelBufferAdaptor(assetWriterInput: input, sourcePixelBufferAttributes: nil)
        writer.add(input)
        guard writer.startWriting() else {
            throw MediaError(description: "startWriting failed: \(String(describing: writer.error))")
        }
        writer.startSession(atSourceTime: .zero)
        for index in 0 ..< frameCount {
            while !input.isReadyForMoreMediaData {
                try await Task.sleep(for: .milliseconds(1))
            }
            let gray = UInt8(40 + (index * 10) % 200)
            let buffer = try pixelBuffer(width: width, height: height, gray: gray)
            guard adaptor.append(buffer, withPresentationTime: CMTime(value: CMTimeValue(index), timescale: fps)) else {
                throw MediaError(description: "append failed: \(String(describing: writer.error))")
            }
        }
        input.markAsFinished()
        await writer.finishWriting()
        guard writer.status == .completed else {
            throw MediaError(description: "finishWriting failed: \(String(describing: writer.error))")
        }
    }
}
