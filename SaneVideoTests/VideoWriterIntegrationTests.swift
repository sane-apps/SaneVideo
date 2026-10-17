//
//  VideoWriterIntegrationTests.swift
//  SaneVideoTests
//
//  The real VideoWriter fed synthetic frames and PCM audio, then the file read back with AVFoundation.
//

import AVFoundation
import CoreMedia
import Foundation
@testable import SaneVideo
import Testing

@Suite("VideoWriter Integration")
@RecordingActor
struct VideoWriterIntegrationTests {
    private static let size = CGSize(width: 320, height: 240)
    private static let fps: Int32 = 30

    /// Retries a write while the real-time input is briefly not ready. Returns whether it was appended.
    private static func appendWhenReady(_ write: () -> Bool) async throws -> Bool {
        for _ in 0 ..< 2000 {
            if write() {
                return true
            }
            try await Task.sleep(for: .milliseconds(1))
        }
        return false
    }

    /// Writes `frameCount` frames at 30 fps plus matching 48 kHz stereo tone, then finishes.
    private static func writeClip(frameCount: Int, to url: URL) async throws -> (URL?, framesWritten: Int) {
        let writer = VideoWriter(targetSize: size)
        try writer.start(outputURL: url, targetFrameRate: Double(fps))
        writer.startSession(at: .zero)

        let audioChunk = 1024
        var audioFrame = 0
        var framesWritten = 0
        for index in 0 ..< frameCount {
            let time = CMTime(value: CMTimeValue(index), timescale: fps)
            let pixels = try TestMedia.pixelBuffer(width: Int(size.width), height: Int(size.height), gray: UInt8(60 + index * 4))
            let sample = try TestMedia.videoSampleBuffer(pixels, at: time, frameDuration: CMTime(value: 1, timescale: fps))
            if try await appendWhenReady({ writer.writeVideo(sampleBuffer: sample, presentationTime: time, source: .camera) }) {
                framesWritten += 1
            }

            let audioEnd = Int(Double(index + 1) / Double(fps) * 48000)
            while audioFrame < audioEnd {
                let pcm = try TestMedia.pcmSampleBuffer(frames: audioChunk, startFrame: audioFrame)
                _ = try await appendWhenReady { writer.writeMicAudio(sampleBuffer: pcm) }
                audioFrame += audioChunk
            }
        }
        return await (writer.finish(), framesWritten)
    }

    @Test("Frames and audio written by VideoWriter make a playable 1 s, 320x240 file tagged Rec. 709")
    func writesPlayableTaggedFile() async throws {
        let directory = try TestMedia.makeTempDirectory("VideoWriter")
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("out.mp4")

        let (result, framesWritten) = try await Self.writeClip(frameCount: 30, to: url)

        #expect(result == url)
        #expect(framesWritten == 30)
        let asset = AVURLAsset(url: url)
        #expect(try await asset.load(.isPlayable))
        let duration = try await asset.load(.duration).seconds
        #expect(duration > 0.9 && duration < 1.1)

        let video = try #require(try await asset.loadTracks(withMediaType: .video).first)
        #expect(try await video.load(.naturalSize) == Self.size)
        let format = try #require(try await video.load(.formatDescriptions).first)
        func tag(_ key: CFString) -> String? {
            CMFormatDescriptionGetExtension(format, extensionKey: key) as? String
        }
        #expect(tag(kCMFormatDescriptionExtension_ColorPrimaries) == kCMFormatDescriptionColorPrimaries_ITU_R_709_2 as String)
        #expect(tag(kCMFormatDescriptionExtension_TransferFunction) == kCMFormatDescriptionTransferFunction_ITU_R_709_2 as String)
        #expect(tag(kCMFormatDescriptionExtension_YCbCrMatrix) == kCMFormatDescriptionYCbCrMatrix_ITU_R_709_2 as String)

        var audioDurations: [Double] = []
        for track in try await asset.loadTracks(withMediaType: .audio) {
            try await audioDurations.append(track.load(.timeRange).duration.seconds)
        }
        #expect(audioDurations.contains { $0 > 0.9 }, "The microphone track should hold about 1 s of audio")
    }

    @Test("A frame stamped earlier than the last written frame is dropped")
    func dropsOutOfOrderFrame() async throws {
        let directory = try TestMedia.makeTempDirectory("VideoWriter")
        defer { try? FileManager.default.removeItem(at: directory) }
        let writer = VideoWriter(targetSize: Self.size)
        try writer.start(outputURL: directory.appendingPathComponent("order.mp4"), targetFrameRate: 30)
        writer.startSession(at: .zero)
        let pixels = try TestMedia.pixelBuffer(width: 320, height: 240, gray: 128)
        let frameDuration = CMTime(value: 1, timescale: 30)
        let later = CMTime(value: 3, timescale: 30)
        let earlier = CMTime(value: 2, timescale: 30)

        let first = try await Self.appendWhenReady {
            guard let sample = try? TestMedia.videoSampleBuffer(pixels, at: later, frameDuration: frameDuration) else { return false }
            return writer.writeVideo(sampleBuffer: sample, presentationTime: later)
        }
        let earlierSample = try TestMedia.videoSampleBuffer(pixels, at: earlier, frameDuration: frameDuration)
        let second = writer.writeVideo(sampleBuffer: earlierSample, presentationTime: earlier)

        #expect(first)
        #expect(!second)
        _ = await writer.finish()
    }

    @Test("Finishing without a session cancels and deletes the file")
    func finishWithoutSessionDeletesFile() async throws {
        let directory = try TestMedia.makeTempDirectory("VideoWriter")
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("empty.mp4")
        let writer = VideoWriter(targetSize: Self.size)
        try writer.start(outputURL: url, targetFrameRate: 30)

        let result = await writer.finish()

        #expect(result == nil)
        #expect(!FileManager.default.fileExists(atPath: url.path))
        #expect(!writer.isWriting)
    }

    @Test("Concurrent finish calls return the same finished file")
    func concurrentFinishIsIdempotent() async throws {
        let directory = try TestMedia.makeTempDirectory("VideoWriter")
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("twice.mp4")
        let writer = VideoWriter(targetSize: Self.size)
        try writer.start(outputURL: url, targetFrameRate: 30)
        writer.startSession(at: .zero)
        let pixels = try TestMedia.pixelBuffer(width: 320, height: 240, gray: 90)
        let sample = try TestMedia.videoSampleBuffer(pixels, at: .zero, frameDuration: CMTime(value: 1, timescale: 30))
        let wrote = try await Self.appendWhenReady { writer.writeVideo(sampleBuffer: sample, presentationTime: .zero) }
        #expect(wrote)

        async let first = writer.finish()
        async let second = writer.finish()
        let (url1, url2) = await (first, second)

        #expect(url1 == url)
        #expect(url2 == url)
    }
}
