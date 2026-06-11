//
//  MagicFixTests.swift
//  SaneVideoTests
//
//  Created by SaneVideo Refactor
//

import XCTest
@testable import SaneVideo
import AVFoundation

@MainActor
final class MagicFixTests: XCTestCase {
    private var sourceRoot: URL {
        URL(fileURLWithPath: #file)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
    }
    
    // MARK: - Options Tests
    
    func testMagicFixOptionsDefault() {
        let options = MagicFixOptions()
        XCTAssertTrue(options.removeSilence)
        XCTAssertTrue(options.removeFillers)
        XCTAssertTrue(options.generateCaptions)
    }

    func testAudioEnhancementIsSkippedForVideoOnlyClips() async {
        let videoOnlyURL = sourceRoot.appendingPathComponent("Tests/Assets/website-demo-video-call.mp4")
        let audioURL = sourceRoot.appendingPathComponent("Tests/Assets/test_video.mp4")
        let videoOnlyClip = VideoClip(url: videoOnlyURL, duration: CMTime(seconds: 12, preferredTimescale: 600))
        let audioClip = VideoClip(url: audioURL, duration: CMTime(seconds: 12, preferredTimescale: 600))
        let shouldEnhanceVideoOnly = await MagicFixService.shouldAttemptAudioEnhancement(
            for: videoOnlyClip,
            options: MagicFixOptions()
        )
        let shouldEnhanceAudio = await MagicFixService.shouldAttemptAudioEnhancement(
            for: audioClip,
            options: MagicFixOptions()
        )

        XCTAssertFalse(
            shouldEnhanceVideoOnly,
            "Magic Fix should not surface audio-enhancement failures for video-only clips."
        )
        XCTAssertTrue(
            shouldEnhanceAudio,
            "Magic Fix should still enhance audio when the source clip has an audio track."
        )

        var disabledOptions = MagicFixOptions()
        disabledOptions.enhanceAudio = false
        let shouldEnhanceDisabled = await MagicFixService.shouldAttemptAudioEnhancement(
            for: audioClip,
            options: disabledOptions
        )
        XCTAssertFalse(shouldEnhanceDisabled)
    }
    
    // MARK: - Range Calculation Tests
    
    func testCalculateKeepRanges_NoRemovals() {
        let duration = CMTime(seconds: 10, preferredTimescale: 600)
        let removals: [CMTimeRange] = []
        
        let keepRanges = MagicFixService.calculateKeepRanges(removals: removals, duration: duration)
        
        XCTAssertEqual(keepRanges.count, 1)
        XCTAssertEqual(keepRanges.first?.start.seconds, 0)
        XCTAssertEqual(keepRanges.first?.end.seconds, 10)
    }
    
    func testCalculateKeepRanges_FullRemoval() {
        let duration = CMTime(seconds: 10, preferredTimescale: 600)
        let removals = [CMTimeRange(start: .zero, duration: duration)]
        
        let keepRanges = MagicFixService.calculateKeepRanges(removals: removals, duration: duration)
        
        XCTAssertTrue(keepRanges.isEmpty)
    }
    
    func testCalculateKeepRanges_SingleRemoval_Middle() {
        let duration = CMTime(seconds: 10, preferredTimescale: 600)
        // Remove 4s to 6s
        let removals = [
            CMTimeRange(start: CMTime(seconds: 4, preferredTimescale: 600), duration: CMTime(seconds: 2, preferredTimescale: 600))
        ]
        
        let keepRanges = MagicFixService.calculateKeepRanges(removals: removals, duration: duration)
        
        XCTAssertEqual(keepRanges.count, 2)
        // 0 to 4
        XCTAssertEqual(keepRanges[0].start.seconds, 0)
        XCTAssertEqual(keepRanges[0].end.seconds, 4)
        // 6 to 10
        XCTAssertEqual(keepRanges[1].start.seconds, 6)
        XCTAssertEqual(keepRanges[1].end.seconds, 10)
    }
    
    func testCalculateKeepRanges_MultipleRemovals_WithOverlap() {
        let duration = CMTime(seconds: 10, preferredTimescale: 600)
        // Remove 1-3, 2-4 (overlap -> 1-4), and 8-9
        let removals = [
            CMTimeRange(start: CMTime(seconds: 1, preferredTimescale: 600), duration: CMTime(seconds: 2, preferredTimescale: 600)), // 1-3
            CMTimeRange(start: CMTime(seconds: 2, preferredTimescale: 600), duration: CMTime(seconds: 2, preferredTimescale: 600)), // 2-4
            CMTimeRange(start: CMTime(seconds: 8, preferredTimescale: 600), duration: CMTime(seconds: 1, preferredTimescale: 600))  // 8-9
        ]
        
        let keepRanges = MagicFixService.calculateKeepRanges(removals: removals, duration: duration)
        
        // Expected: 0-1, 4-8, 9-10
        XCTAssertEqual(keepRanges.count, 3)
        
        XCTAssertEqual(keepRanges[0].start.seconds, 0)
        XCTAssertEqual(keepRanges[0].end.seconds, 1)
        
        XCTAssertEqual(keepRanges[1].start.seconds, 4)
        XCTAssertEqual(keepRanges[1].end.seconds, 8)
        
        XCTAssertEqual(keepRanges[2].start.seconds, 9)
        XCTAssertEqual(keepRanges[2].end.seconds, 10)
    }
    
    func testCalculateKeepRanges_OutOfBounds() {
        let duration = CMTime(seconds: 10, preferredTimescale: 600)
        // Remove 9-12 (extends beyond duration)
        let removals = [
            CMTimeRange(start: CMTime(seconds: 9, preferredTimescale: 600), duration: CMTime(seconds: 3, preferredTimescale: 600))
        ]
        
        let keepRanges = MagicFixService.calculateKeepRanges(removals: removals, duration: duration)
        
        // Expected: 0-9
        XCTAssertEqual(keepRanges.count, 1)
        XCTAssertEqual(keepRanges[0].start.seconds, 0)
        XCTAssertEqual(keepRanges[0].end.seconds, 9)
    }
}
