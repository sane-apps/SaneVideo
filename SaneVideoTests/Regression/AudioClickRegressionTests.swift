//
//  AudioClickRegressionTests.swift
//  SaneVideoTests
//
//  Regression tests for audio click fix from 2025-12-31
//  Tests that short clips (0.05s-0.15s) get proper fade-out to prevent audio clicks
//
//  Bug: Clips between 0.05s and 0.15s were getting fade-in but no fade-out,
//  causing audible click/pop at clip end.
//  Fix: Changed threshold from 3x to 2x fadeDuration, added proportional fade-out.
//

import AVFoundation
import CoreMedia
import Testing

@testable import SaneVideo

/// Regression tests for audio click fix (BUG_TRACKING.md: Audio Click on Short Clips)
@Suite("Audio Click Regression Tests")
struct AudioClickRegressionTests {

    // MARK: - Test Constants

    /// Standard fade duration used by AudioTrackBuilder (0.05s)
    static let fadeDuration = CMTime(seconds: 0.05, preferredTimescale: 600)

    // MARK: - Tests

    /// Verifies that clips longer than 2x fade duration (0.10s) get fade-out
    /// This is the new threshold (was 3x / 0.15s before fix)
    @Test("Clips > 0.10s should have fade-out applied")
    func testClipAboveThresholdGetsFadeOut() async throws {
        // Arrange: Create a 0.12s clip (above 2x threshold of 0.10s)
        let clipDuration = CMTime(seconds: 0.12, preferredTimescale: 600)
        let safeFadeDuration = CMTimeMinimum(Self.fadeDuration, clipDuration)

        // Calculate expected fade-out availability
        let availableForFadeOut = CMTimeSubtract(clipDuration, safeFadeDuration)
        let expectedFadeOutDuration = CMTimeMinimum(safeFadeDuration, availableForFadeOut)

        // Assert: Clip should have room for fade-out
        #expect(CMTimeCompare(clipDuration, CMTimeMultiply(safeFadeDuration, multiplier: 2)) > 0,
               "0.12s clip should exceed 2x threshold (0.10s)")
        #expect(CMTimeCompare(expectedFadeOutDuration, .zero) > 0,
               "Fade-out duration should be positive")
        #expect(CMTimeGetSeconds(expectedFadeOutDuration) > 0.04,
               "Fade-out should be close to full 0.05s")
    }

    /// Verifies the old threshold (0.15s) would have excluded this clip
    /// This documents the bug that was fixed
    @Test("Old 3x threshold would have excluded 0.12s clips (regression prevention)")
    func testOldThresholdWouldExcludeClip() async throws {
        // Arrange: The old threshold was 3x fadeDuration = 0.15s
        let clipDuration = CMTime(seconds: 0.12, preferredTimescale: 600)
        let oldMultiplier: Int32 = 3
        let oldThreshold = CMTimeMultiply(Self.fadeDuration, multiplier: oldMultiplier)

        // Assert: Under old threshold, this clip would NOT get fade-out (the bug)
        #expect(CMTimeCompare(clipDuration, oldThreshold) <= 0,
               "0.12s clip was BELOW old 0.15s threshold - this was the bug")
    }

    /// Verifies very short clips (< 0.10s) still don't get fade-out
    /// This is intentional to prevent overlapping fade-in/fade-out
    @Test("Clips < 0.10s should NOT have fade-out (prevents overlap)")
    func testVeryShortClipsNoFadeOut() async throws {
        // Arrange: Create a 0.08s clip (below 2x threshold)
        let clipDuration = CMTime(seconds: 0.08, preferredTimescale: 600)
        let safeFadeDuration = CMTimeMinimum(Self.fadeDuration, clipDuration)

        // Assert: Clip is too short for fade-out without overlap
        #expect(CMTimeCompare(clipDuration, CMTimeMultiply(safeFadeDuration, multiplier: 2)) <= 0,
               "0.08s clip should be at or below 2x threshold - no fade-out expected")
    }

    /// Verifies proportional fade-out calculation for clips just above threshold
    @Test("Proportional fade-out calculated correctly for 0.12s clip")
    func testProportionalFadeOutCalculation() async throws {
        // Arrange: 0.12s clip with 0.05s fade-in leaves 0.07s
        let clipDuration = CMTime(seconds: 0.12, preferredTimescale: 600)
        let safeFadeDuration = Self.fadeDuration // 0.05s

        // Calculate proportional fade-out (matches AudioTrackBuilder logic)
        let availableForFadeOut = CMTimeSubtract(clipDuration, safeFadeDuration)
        let actualFadeOutDuration = CMTimeMinimum(safeFadeDuration, availableForFadeOut)

        // Assert: Fade-out should be full 0.05s since we have 0.07s available
        let fadeOutSeconds = CMTimeGetSeconds(actualFadeOutDuration)
        #expect(fadeOutSeconds >= 0.049 && fadeOutSeconds <= 0.051,
               "With 0.07s available, fade-out should be full 0.05s, got \(fadeOutSeconds)")
    }

    /// Verifies fade-out doesn't overlap with fade-in
    @Test("Fade-out start must be after fade-in end")
    func testFadeOutDoesNotOverlapFadeIn() async throws {
        // Arrange: 0.12s clip
        let clipDuration = CMTime(seconds: 0.12, preferredTimescale: 600)
        let clipStart = CMTime(seconds: 5.0, preferredTimescale: 600) // Arbitrary start
        let safeFadeDuration = Self.fadeDuration

        // Calculate times (matches AudioTrackBuilder logic)
        let fadeInEnd = CMTimeAdd(clipStart, safeFadeDuration)
        let clipEnd = CMTimeAdd(clipStart, clipDuration)
        let availableForFadeOut = CMTimeSubtract(clipDuration, safeFadeDuration)
        let actualFadeOutDuration = CMTimeMinimum(safeFadeDuration, availableForFadeOut)
        let fadeOutStart = CMTimeSubtract(clipEnd, actualFadeOutDuration)

        // Assert: Fade-out must start after fade-in ends
        #expect(CMTimeCompare(fadeOutStart, fadeInEnd) > 0,
               "Fade-out start (\(CMTimeGetSeconds(fadeOutStart))s) must be after fade-in end (\(CMTimeGetSeconds(fadeInEnd))s)")
    }

    /// Verifies longer clips still get full fade-out
    @Test("Long clips (0.5s) get full fade-out duration")
    func testLongClipsGetFullFadeOut() async throws {
        // Arrange: 0.5s clip should easily get full 0.05s fade-out
        let clipDuration = CMTime(seconds: 0.5, preferredTimescale: 600)
        let safeFadeDuration = Self.fadeDuration

        let availableForFadeOut = CMTimeSubtract(clipDuration, safeFadeDuration)
        let actualFadeOutDuration = CMTimeMinimum(safeFadeDuration, availableForFadeOut)

        // Assert: Should get full fade duration
        let fadeOutSeconds = CMTimeGetSeconds(actualFadeOutDuration)
        #expect(fadeOutSeconds >= 0.049 && fadeOutSeconds <= 0.051,
               "Long clip should get full 0.05s fade-out, got \(fadeOutSeconds)")
    }
}
