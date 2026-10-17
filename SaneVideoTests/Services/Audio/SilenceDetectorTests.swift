//
//  SilenceDetectorTests.swift
//  SaneVideoTests
//
//  Silence detection on real audio: a generated tone/silence WAV with known gaps,
//  plus the fixture clips (fully silent, constant tone, no audio track).
//

import AVFoundation
import CoreMedia
import Foundation
@testable import SaneVideo
import Testing

@Suite("SilenceDetector")
struct SilenceDetectorTests {
    /// 1 s tone, 1.5 s silence, 1 s tone, 1 s silence, 0.5 s tone: silent spans are 1.0-2.5 s and 3.5-4.5 s.
    static let pattern: [(isTone: Bool, seconds: Double)] = [
        (true, 1.0), (false, 1.5), (true, 1.0), (false, 1.0), (true, 0.5)
    ]
    static let silentSpans: [(start: Double, end: Double)] = [(1.0, 2.5), (3.5, 4.5)]

    /// Reader buffers are a few thousand samples long, so edges land within about 0.2 s of the truth.
    static let edgeSlack = 0.25

    static func makePatternClip(in directory: URL) throws -> VideoClip {
        let url = directory.appendingPathComponent("tone-silence.wav")
        try TestMedia.writeToneAndSilence(pattern, to: url)
        return VideoClip(url: url, duration: CMTime(seconds: 5, preferredTimescale: 600))
    }

    private func clip(forAsset name: String) async throws -> VideoClip {
        let url = TestEnvironment.testAsset(named: name)
        let duration = try await AVURLAsset(url: url).load(.duration)
        return VideoClip(url: url, duration: duration)
    }

    // MARK: - Detection on real audio

    @Test("Finds exactly the two known silent spans in a tone/silence file")
    func findsKnownSilentSpans() async throws {
        let directory = try TestMedia.makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let clip = try Self.makePatternClip(in: directory)
        let config = SilenceDetector.Configuration(dbThreshold: -45, minDuration: 0.3, margin: 0, tolerance: 0)

        let ranges = try await SilenceDetector().detectSilence(in: clip, config: config)

        try #require(ranges.count == 2)
        for (range, expected) in zip(ranges, Self.silentSpans) {
            #expect(abs(range.start.seconds - expected.start) < Self.edgeSlack)
            #expect(abs(range.end.seconds - expected.end) < Self.edgeSlack)
            #expect(range.start.seconds >= expected.start - 0.01, "Detected silence must not start inside the tone")
            #expect(range.end.seconds <= expected.end + 0.01, "Detected silence must not run into the next tone")
        }
    }

    @Test("Silence shorter than minDuration is not reported")
    func ignoresShortSilence() async throws {
        let directory = try TestMedia.makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let clip = try Self.makePatternClip(in: directory)
        let config = SilenceDetector.Configuration(dbThreshold: -45, minDuration: 1.2, margin: 0, tolerance: 0)

        let ranges = try await SilenceDetector().detectSilence(in: clip, config: config)

        try #require(ranges.count == 1)
        #expect(abs(ranges[0].start.seconds - 1.0) < Self.edgeSlack)
    }

    @Test("A fully silent clip is one silent span, shrunk by the margin at both ends")
    func fullySilentClip() async throws {
        let clip = try await clip(forAsset: "test_silence.mp4")

        let ranges = try await SilenceDetector().detectSilence(in: clip)

        try #require(ranges.count == 1)
        #expect(abs(ranges[0].start.seconds - 0.1) < 0.15)
        #expect(abs(ranges[0].end.seconds - (clip.duration.seconds - 0.1)) < 0.15)
    }

    @Test("A clip with a continuous tone has no silence")
    func continuousToneHasNoSilence() async throws {
        let clip = try await clip(forAsset: "test_video.mp4")

        let ranges = try await SilenceDetector().detectSilence(in: clip)

        #expect(ranges.isEmpty)
    }

    @Test("A clip with no audio track returns no ranges instead of failing")
    func noAudioTrackReturnsEmpty() async throws {
        let clip = try await clip(forAsset: "website-demo-video-call.mp4")

        let ranges = try await SilenceDetector().detectSilence(in: clip)

        #expect(ranges.isEmpty)
    }

    // MARK: - Magic Fix end to end

    @Test("Magic Fix cuts only silent time, and the clip shrinks by exactly what was cut")
    @MainActor
    func magicFixRemovesOnlySilence() async throws {
        let directory = try TestMedia.makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        var clip = try Self.makePatternClip(in: directory)
        var options = MagicFixOptions.minimal
        options.silenceTolerance = 0

        let keep = try await MagicFixService.applyMagicFix(to: clip, options: options) { _, _ in }
        let removed = MagicFixService.calculateRemovedRanges(from: keep, duration: clip.duration)
        clip.removedRanges = removed.map { CodableTimeRange($0) }

        let removedSeconds = removed.reduce(0) { $0 + $1.duration.seconds }
        #expect(removed.count == 2)
        #expect(removedSeconds > 1.2 && removedSeconds < 2.2)
        #expect(abs(clip.effectiveDuration.seconds - (5.0 - removedSeconds)) < 0.001)
        for range in removed {
            let insideSilence = Self.silentSpans.contains { span in
                range.start.seconds >= span.start - 0.01 && range.end.seconds <= span.end + 0.01
            }
            #expect(insideSilence, "Cut \(range.start.seconds)-\(range.end.seconds) s removes audible tone")
        }
    }

    // MARK: - Margin

    @Test("Margin shrinks ranges on both sides")
    func marginShrinksRanges() {
        let ranges = [CMTimeRange(start: CMTime(seconds: 10, preferredTimescale: 600), end: CMTime(seconds: 20, preferredTimescale: 600))]

        let result = SilenceDetector.applyMargin(ranges, margin: 0.1)

        #expect(result.count == 1)
        #expect(abs(result[0].start.seconds - 10.1) < 0.01)
        #expect(abs(result[0].end.seconds - 19.9) < 0.01)
    }

    @Test("Margin drops ranges that collapse and keeps the rest")
    func marginDropsCollapsedRanges() {
        let ranges = [
            CMTimeRange(start: .zero, end: CMTime(seconds: 5, preferredTimescale: 600)),
            CMTimeRange(start: CMTime(seconds: 10, preferredTimescale: 600), end: CMTime(seconds: 10.15, preferredTimescale: 600))
        ]

        let result = SilenceDetector.applyMargin(ranges, margin: 0.1)

        #expect(result.count == 1)
        #expect(abs(result[0].start.seconds - 0.1) < 0.01)
        #expect(abs(result[0].end.seconds - 4.9) < 0.01)
    }

    @Test("Zero margin returns ranges unchanged")
    func zeroMarginUnchanged() {
        let range = CMTimeRange(start: CMTime(seconds: 5, preferredTimescale: 600), end: CMTime(seconds: 15, preferredTimescale: 600))

        #expect(SilenceDetector.applyMargin([range], margin: 0) == [range])
    }
}
