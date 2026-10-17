//
//  RepurposingTests.swift
//  SaneVideoTests
//
//  Shorts candidate labels and repurposing settings rules.
//

import CoreMedia
@testable import SaneVideo
import Testing

@Suite("Repurposing")
struct RepurposingTests {
    private func range(seconds: Double) -> CMTimeRange {
        CMTimeRange(start: .zero, duration: CMTime(seconds: seconds, preferredTimescale: 600))
    }

    @Test(
        "Candidate score maps to its label band",
        arguments: [(0.9, "Excellent"), (0.7, "Good"), (0.5, "Fair"), (0.2, "Low")]
    )
    func scoreLabel(score: Double, label: String) {
        #expect(ShortCandidate(timeRange: range(seconds: 30), score: score).scoreLabel == label)
    }

    @Test(
        "Candidate duration label uses seconds, then minutes and seconds",
        arguments: [(30.0, "30s"), (90.0, "1m 30s")]
    )
    func durationLabel(seconds: Double, label: String) {
        #expect(ShortCandidate(timeRange: range(seconds: seconds)).durationLabel == label)
    }

    @Test("maxShorts is clamped to 1...10")
    func maxShortsClamping() {
        #expect(RepurposingSettings(maxShorts: 0).maxShorts == 1)
        #expect(RepurposingSettings(maxShorts: 100).maxShorts == 10)
    }

    @Test("Applying the YouTube Shorts preset sets platform, 60 s duration and 9:16")
    func applyPlatformPreset() {
        var settings = RepurposingSettings(
            targetDuration: .fifteen,
            aspectRatio: .square1x1,
            platform: .tiktok,
            maxShorts: 3
        )

        settings.applyPlatformPreset(.youtubeShorts)

        #expect(settings.platform == .youtubeShorts)
        #expect(settings.targetDuration == .sixty)
        #expect(settings.aspectRatio == .vertical9x16)
    }
}
