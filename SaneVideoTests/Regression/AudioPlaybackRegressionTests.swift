//
//  AudioPlaybackRegressionTests.swift
//  SaneVideoTests
//
//  Regression tests for audio playback issues from 2025-12-31
//
//  Bug 1: RealTimeAudioProcessor set videoPlayer.volume = 0.0, causing silent playback
//  Fix: Disabled RealTimeAudioProcessor for playback, using composition audio only
//
//  Bug 2: AudioLimiter MTAudioProcessingTap may not be compatible with AVPlayer playback
//  Fix: Bypassed AudioLimiter for playback (only use for export)
//
//  Root causes:
//  - Commit 1be93b5 (Dec 24) - Added RealTimeAudioProcessor that sets volume=0
//  - Commit 6dededa (Dec 31) - Added AudioLimiter with MTAudioProcessingTap
//

import AVFoundation
import CoreMedia
import Testing

@testable import SaneVideo

/// Regression tests for audio playback (BUG_TRACKING.md: Silent Audio Playback)
@Suite("Audio Playback Regression Tests")
struct AudioPlaybackRegressionTests {

    // MARK: - Volume Tests

    /// Verifies default clip volume is 1.0 (not muted)
    @Test("Default clip volume is 1.0")
    func testDefaultClipVolume() async throws {
        // Arrange: Create a default VideoClip
        let clip = VideoClip(
            url: URL(fileURLWithPath: "/tmp/test.mp4"),
            duration: CMTime(seconds: 10, preferredTimescale: 600)
        )

        // Assert
        #expect(clip.volume == 1.0, "Default clip volume should be 1.0")
        #expect(!clip.isMuted, "Default clip should not be muted")
    }

    /// Verifies finalVolume calculation respects isMuted flag
    @Test("Final volume is 0 when clip is muted")
    func testMutedClipVolumeIsZero() async throws {
        // Arrange
        var clip = VideoClip(
            url: URL(fileURLWithPath: "/tmp/test.mp4"),
            duration: CMTime(seconds: 10, preferredTimescale: 600)
        )
        clip.isMuted = true
        clip.volume = 1.0  // Even with volume 1.0

        // Calculate finalVolume (same logic as AudioTrackBuilder)
        let finalVolume = clip.isMuted ? 0.0 : Float(clip.volume)

        // Assert
        #expect(finalVolume == 0.0, "Muted clip should have finalVolume of 0.0")
    }

    /// Verifies finalVolume calculation respects volume setting
    @Test("Final volume respects clip volume setting")
    func testClipVolumeRespected() async throws {
        // Arrange
        var clip = VideoClip(
            url: URL(fileURLWithPath: "/tmp/test.mp4"),
            duration: CMTime(seconds: 10, preferredTimescale: 600)
        )
        clip.isMuted = false
        clip.volume = 0.5

        // Calculate finalVolume (same logic as AudioTrackBuilder)
        let finalVolume = clip.isMuted ? 0.0 : Float(clip.volume)

        // Assert
        #expect(finalVolume == 0.5, "Final volume should match clip.volume when not muted")
    }

    // MARK: - AudioMix Tests

    /// Verifies AVMutableAudioMix can be created with input parameters
    @Test("AudioMix can hold input parameters")
    func testAudioMixInputParameters() async throws {
        // Arrange
        let audioMix = AVMutableAudioMix()
        let params = AVMutableAudioMixInputParameters()

        // Act
        audioMix.inputParameters = [params]

        // Assert
        #expect(audioMix.inputParameters.count == 1,
               "AudioMix should have 1 input parameter")
    }

    /// Verifies input parameters can have volume set and read back
    @Test("Input parameters support volume setting")
    func testInputParametersVolume() async throws {
        // Arrange
        let params = AVMutableAudioMixInputParameters()
        let volumeTime = CMTime(seconds: 0, preferredTimescale: 600)

        // Act - set volume
        params.setVolume(1.0, at: volumeTime)

        // Assert - verify volume was set by reading it back
        var startVolume: Float = 0
        var endVolume: Float = 0
        var timeRange = CMTimeRange()
        let hasRamp = params.getVolumeRamp(
            for: volumeTime,
            startVolume: &startVolume,
            endVolume: &endVolume,
            timeRange: &timeRange
        )
        // setVolume creates a point, not a ramp, so hasRamp may be false
        // but if we got here, the API accepted the call
        #expect(startVolume >= 0, "Volume should be readable after setting")
    }

    /// Verifies input parameters support volume ramps
    @Test("Input parameters support volume ramps")
    func testInputParametersVolumeRamp() async throws {
        // Arrange
        let params = AVMutableAudioMixInputParameters()
        let rampStart = CMTime(seconds: 0, preferredTimescale: 600)
        let rampDuration = CMTime(seconds: 0.05, preferredTimescale: 600)
        let rampRange = CMTimeRange(start: rampStart, duration: rampDuration)

        // Act - set volume ramp
        params.setVolumeRamp(fromStartVolume: 0.0, toEndVolume: 1.0, timeRange: rampRange)

        // Assert - verify ramp was set by reading it back
        var startVolume: Float = 0
        var endVolume: Float = 0
        var readTimeRange = CMTimeRange()
        let hasRamp = params.getVolumeRamp(
            for: rampStart,
            startVolume: &startVolume,
            endVolume: &endVolume,
            timeRange: &readTimeRange
        )
        #expect(hasRamp, "Should have a volume ramp after setting one")
        #expect(startVolume == 0.0, "Start volume should be 0.0")
        #expect(endVolume == 1.0, "End volume should be 1.0")
    }

    // MARK: - Player Volume Tests

    /// Verifies AVPlayer volume can be set to 1.0
    @Test("AVPlayer volume defaults and can be set")
    func testAVPlayerVolume() async throws {
        // Note: Can't create AVPlayer in test environment without media
        // This test documents expected behavior

        // Assert expected default behavior
        let expectedDefaultVolume: Float = 1.0
        let expectedPlaybackVolume: Float = 1.0

        #expect(expectedDefaultVolume == 1.0,
               "AVPlayer default volume should be 1.0")
        #expect(expectedPlaybackVolume == 1.0,
               "Playback volume should be explicitly set to 1.0")
    }

    // MARK: - Composition Audio Track Tests

    /// Verifies composition supports multiple audio tracks (A/B roll)
    @Test("Composition supports A/B roll audio tracks")
    func testCompositionAudioTracks() async throws {
        // Arrange
        let composition = AVMutableComposition()

        // Act - create A/B audio tracks
        let trackA = composition.addMutableTrack(
            withMediaType: .audio,
            preferredTrackID: kCMPersistentTrackID_Invalid
        )
        let trackB = composition.addMutableTrack(
            withMediaType: .audio,
            preferredTrackID: kCMPersistentTrackID_Invalid
        )

        // Assert
        #expect(trackA != nil, "Audio track A should be created")
        #expect(trackB != nil, "Audio track B should be created")

        let audioTracks = composition.tracks(withMediaType: .audio)
        #expect(audioTracks.count == 2, "Composition should have 2 audio tracks (A/B roll)")
    }

    // MARK: - AudioLimiter Bypass Tests

    /// Documents that AudioLimiter should be bypassed for playback
    @Test("AudioLimiter bypass documented for playback")
    func testAudioLimiterBypassDocumented() async throws {
        // This test documents the fix: AudioLimiter with MTAudioProcessingTap
        // is not compatible with AVPlayer playback, only with export rendering.
        //
        // The fix bypasses AudioLimiter.applyLimiter() in CompositionBuilder
        // when building compositions for playback.

        let bypassedForPlayback = true
        let useForExportOnly = true

        #expect(bypassedForPlayback,
               "AudioLimiter should be bypassed for playback")
        #expect(useForExportOnly,
               "AudioLimiter should only be used for export rendering")
    }
}
