//
//  MagicFixServiceTests.swift
//  SaneVideoTests
//
//

import Testing
import Foundation
import CoreMedia
@testable import SaneVideo

@Suite("MagicFixService Tests")
struct MagicFixServiceTests {

    // MARK: - Calculate Keep Ranges Tests

    @Suite("Calculate Keep Ranges")
    struct CalculateKeepRangesTests {

        @Test("No removals returns full duration as keep range")
        func noRemovalsReturnsFull() {
            // Arrange
            let removals: [CMTimeRange] = []
            let duration = CMTime(seconds: 60, preferredTimescale: 600)

            // Act
            let keepRanges = MagicFixService.calculateKeepRanges(removals: removals, duration: duration)

            // Assert
            #expect(keepRanges.count == 1)
            #expect(keepRanges[0].start == .zero)
            #expect(keepRanges[0].end == duration)
        }

        @Test("Single removal at start")
        func singleRemovalAtStart() {
            // Arrange
            let removals = [
                CMTimeRange(
                    start: CMTime(seconds: 0, preferredTimescale: 600),
                    end: CMTime(seconds: 5, preferredTimescale: 600)
                )
            ]
            let duration = CMTime(seconds: 60, preferredTimescale: 600)
            let removal = removals[0]

            // Act
            let keepRanges = MagicFixService.calculateKeepRanges(removals: removals, duration: duration)

            // Assert
            #expect(keepRanges.count == 1)
            #expect(keepRanges[0].start == removal.end)
            #expect(keepRanges[0].end == duration)
        }

        @Test("Single removal at end")
        func singleRemovalAtEnd() {
            // Arrange
            let removals = [
                CMTimeRange(
                    start: CMTime(seconds: 55, preferredTimescale: 600),
                    end: CMTime(seconds: 60, preferredTimescale: 600)
                )
            ]
            let duration = CMTime(seconds: 60, preferredTimescale: 600)
            let removal = removals[0]

            // Act
            let keepRanges = MagicFixService.calculateKeepRanges(removals: removals, duration: duration)

            // Assert
            #expect(keepRanges.count == 1)
            #expect(keepRanges[0].start == .zero)
            #expect(keepRanges[0].end == removal.start)
        }

        @Test("Single removal in middle")
        func singleRemovalInMiddle() {
            // Arrange
            let removals = [
                CMTimeRange(
                    start: CMTime(seconds: 20, preferredTimescale: 600),
                    end: CMTime(seconds: 30, preferredTimescale: 600)
                )
            ]
            let duration = CMTime(seconds: 60, preferredTimescale: 600)
            let removal = removals[0]
            let expectedKeepCount = removals.count + 1

            // Act
            let keepRanges = MagicFixService.calculateKeepRanges(removals: removals, duration: duration)

            // Assert
            #expect(keepRanges.count == expectedKeepCount)
            #expect(keepRanges[0].start == .zero)
            #expect(keepRanges[0].end == removal.start)
            #expect(keepRanges[1].start == removal.end)
            #expect(keepRanges[1].end == duration)
        }

        @Test("Multiple non-overlapping removals")
        func multipleNonOverlappingRemovals() {
            // Arrange
            let removals = [
                CMTimeRange(
                    start: CMTime(seconds: 10, preferredTimescale: 600),
                    end: CMTime(seconds: 15, preferredTimescale: 600)
                ),
                CMTimeRange(
                    start: CMTime(seconds: 30, preferredTimescale: 600),
                    end: CMTime(seconds: 35, preferredTimescale: 600)
                )
            ]
            let duration = CMTime(seconds: 60, preferredTimescale: 600)
            let firstRemoval = removals[0]
            let secondRemoval = removals[1]
            let expectedKeepCount = removals.count + 1

            // Act
            let keepRanges = MagicFixService.calculateKeepRanges(removals: removals, duration: duration)

            // Assert
            #expect(keepRanges.count == expectedKeepCount)
            #expect(keepRanges[0].start == .zero)
            #expect(keepRanges[0].end == firstRemoval.start)
            #expect(keepRanges[1].start == firstRemoval.end)
            #expect(keepRanges[1].end == secondRemoval.start)
            #expect(keepRanges[2].start == secondRemoval.end)
            #expect(keepRanges[2].end == duration)
        }

        @Test("Overlapping removals are consolidated")
        func overlappingRemovalsConsolidated() {
            // Arrange
            let removals = [
                CMTimeRange(
                    start: CMTime(seconds: 10, preferredTimescale: 600),
                    end: CMTime(seconds: 20, preferredTimescale: 600)
                ),
                CMTimeRange(
                    start: CMTime(seconds: 15, preferredTimescale: 600),
                    end: CMTime(seconds: 25, preferredTimescale: 600)
                )
            ]
            let duration = CMTime(seconds: 60, preferredTimescale: 600)
            let firstRemoval = removals[0]
            let secondRemoval = removals[1]

            // Act
            let keepRanges = MagicFixService.calculateKeepRanges(removals: removals, duration: duration)

            // Assert
            #expect(keepRanges.count == removals.count)
            #expect(keepRanges[0].start == .zero)
            #expect(keepRanges[0].end == firstRemoval.start)
            #expect(keepRanges[1].start == secondRemoval.end)
            #expect(keepRanges[1].end == duration)
        }

        @Test("Adjacent removals are consolidated")
        func adjacentRemovalsConsolidated() {
            // Arrange
            let removals = [
                CMTimeRange(
                    start: CMTime(seconds: 10, preferredTimescale: 600),
                    end: CMTime(seconds: 20, preferredTimescale: 600)
                ),
                CMTimeRange(
                    start: CMTime(seconds: 20, preferredTimescale: 600),
                    end: CMTime(seconds: 30, preferredTimescale: 600)
                )
            ]
            let duration = CMTime(seconds: 60, preferredTimescale: 600)
            let firstRemoval = removals[0]
            let secondRemoval = removals[1]

            // Act
            let keepRanges = MagicFixService.calculateKeepRanges(removals: removals, duration: duration)

            // Assert
            #expect(keepRanges.count == removals.count)
            #expect(keepRanges[0].end == firstRemoval.start)
            #expect(keepRanges[1].start == secondRemoval.end)
        }

        @Test("Removal covering full duration returns empty")
        func fullRemovalReturnsEmpty() {
            // Arrange
            let removals = [
                CMTimeRange(
                    start: CMTime(seconds: 0, preferredTimescale: 600),
                    end: CMTime(seconds: 60, preferredTimescale: 600)
                )
            ]
            let duration = CMTime(seconds: 60, preferredTimescale: 600)

            // Act
            let keepRanges = MagicFixService.calculateKeepRanges(removals: removals, duration: duration)

            // Assert
            #expect(keepRanges.isEmpty)
        }

        @Test("Unsorted removals are handled correctly")
        func unsortedRemovalsHandled() {
            // Arrange - removals not in order
            let removals = [
                CMTimeRange(
                    start: CMTime(seconds: 30, preferredTimescale: 600),
                    end: CMTime(seconds: 35, preferredTimescale: 600)
                ),
                CMTimeRange(
                    start: CMTime(seconds: 10, preferredTimescale: 600),
                    end: CMTime(seconds: 15, preferredTimescale: 600)
                )
            ]
            let duration = CMTime(seconds: 60, preferredTimescale: 600)
            let expectedKeepCount = removals.count + 1

            // Act
            let keepRanges = MagicFixService.calculateKeepRanges(removals: removals, duration: duration)

            // Assert - should still work correctly
            #expect(keepRanges.count == expectedKeepCount)
        }
    }

    // MARK: - Calculate Removed Ranges Tests

    @Suite("Calculate Removed Ranges")
    struct CalculateRemovedRangesTests {

        @Test("No keep ranges means everything removed")
        func noKeepRangesMeansFullRemoval() {
            // Arrange
            let keepRanges: [CMTimeRange] = []
            let duration = CMTime(seconds: 60, preferredTimescale: 600)

            // Act
            let removedRanges = MagicFixService.calculateRemovedRanges(from: keepRanges, duration: duration)

            // Assert
            #expect(removedRanges.count == 1)
            #expect(removedRanges[0].start == .zero)
            #expect(removedRanges[0].end == duration)
        }

        @Test("Full keep range means nothing removed")
        func fullKeepRangeMeansNoRemoval() {
            // Arrange
            let keepRanges = [
                CMTimeRange(
                    start: CMTime(seconds: 0, preferredTimescale: 600),
                    end: CMTime(seconds: 60, preferredTimescale: 600)
                )
            ]
            let duration = CMTime(seconds: 60, preferredTimescale: 600)

            // Act
            let removedRanges = MagicFixService.calculateRemovedRanges(from: keepRanges, duration: duration)

            // Assert
            #expect(removedRanges.isEmpty)
        }

        @Test("Gap at start is removed")
        func gapAtStartRemoved() {
            // Arrange
            let keepRanges = [
                CMTimeRange(
                    start: CMTime(seconds: 10, preferredTimescale: 600),
                    end: CMTime(seconds: 60, preferredTimescale: 600)
                )
            ]
            let duration = CMTime(seconds: 60, preferredTimescale: 600)
            let keepRange = keepRanges[0]

            // Act
            let removedRanges = MagicFixService.calculateRemovedRanges(from: keepRanges, duration: duration)

            // Assert
            #expect(removedRanges.count == keepRanges.count)
            #expect(removedRanges[0].start == .zero)
            #expect(removedRanges[0].end == keepRange.start)
        }

        @Test("Gap at end is removed")
        func gapAtEndRemoved() {
            // Arrange
            let keepRanges = [
                CMTimeRange(
                    start: CMTime(seconds: 0, preferredTimescale: 600),
                    end: CMTime(seconds: 50, preferredTimescale: 600)
                )
            ]
            let duration = CMTime(seconds: 60, preferredTimescale: 600)
            let keepRange = keepRanges[0]

            // Act
            let removedRanges = MagicFixService.calculateRemovedRanges(from: keepRanges, duration: duration)

            // Assert
            #expect(removedRanges.count == keepRanges.count)
            #expect(removedRanges[0].start == keepRange.end)
            #expect(removedRanges[0].end == duration)
        }

        @Test("Gap in middle is removed")
        func gapInMiddleRemoved() {
            // Arrange
            let keepRanges = [
                CMTimeRange(
                    start: CMTime(seconds: 0, preferredTimescale: 600),
                    end: CMTime(seconds: 20, preferredTimescale: 600)
                ),
                CMTimeRange(
                    start: CMTime(seconds: 40, preferredTimescale: 600),
                    end: CMTime(seconds: 60, preferredTimescale: 600)
                )
            ]
            let duration = CMTime(seconds: 60, preferredTimescale: 600)
            let firstKeepRange = keepRanges[0]
            let secondKeepRange = keepRanges[1]
            let expectedRemovedCount = keepRanges.count - 1

            // Act
            let removedRanges = MagicFixService.calculateRemovedRanges(from: keepRanges, duration: duration)

            // Assert
            #expect(removedRanges.count == expectedRemovedCount)
            #expect(removedRanges[0].start == firstKeepRange.end)
            #expect(removedRanges[0].end == secondKeepRange.start)
        }

        @Test("Multiple gaps are all removed")
        func multipleGapsRemoved() {
            // Arrange
            let keepRanges = [
                CMTimeRange(
                    start: CMTime(seconds: 5, preferredTimescale: 600),
                    end: CMTime(seconds: 15, preferredTimescale: 600)
                ),
                CMTimeRange(
                    start: CMTime(seconds: 25, preferredTimescale: 600),
                    end: CMTime(seconds: 35, preferredTimescale: 600)
                ),
                CMTimeRange(
                    start: CMTime(seconds: 45, preferredTimescale: 600),
                    end: CMTime(seconds: 55, preferredTimescale: 600)
                )
            ]
            let duration = CMTime(seconds: 60, preferredTimescale: 600)
            let expectedRemovedCount = keepRanges.count + 1

            // Act
            let removedRanges = MagicFixService.calculateRemovedRanges(from: keepRanges, duration: duration)

            // Assert
            #expect(removedRanges.count == expectedRemovedCount)
            // Gap at start
            #expect(removedRanges[0].start == .zero)
            #expect(removedRanges[0].end == keepRanges[0].start)
            // Gap between first and second
            #expect(removedRanges[1].start == keepRanges[0].end)
            #expect(removedRanges[1].end == keepRanges[1].start)
            // Gap between second and third
            #expect(removedRanges[2].start == keepRanges[1].end)
            #expect(removedRanges[2].end == keepRanges[2].start)
            // Gap at end
            #expect(removedRanges[3].start == keepRanges[2].end)
            #expect(removedRanges[3].end == duration)
        }
    }

    // MARK: - Roundtrip Tests

    @Suite("Roundtrip Tests")
    struct RoundtripTests {

        @Test("Keep to remove to keep is consistent")
        func keepToRemoveToKeepRoundtrip() {
            // Arrange
            let originalRemovals = [
                CMTimeRange(
                    start: CMTime(seconds: 10, preferredTimescale: 600),
                    end: CMTime(seconds: 20, preferredTimescale: 600)
                ),
                CMTimeRange(
                    start: CMTime(seconds: 40, preferredTimescale: 600),
                    end: CMTime(seconds: 50, preferredTimescale: 600)
                )
            ]
            let duration = CMTime(seconds: 60, preferredTimescale: 600)

            // Act
            let keepRanges = MagicFixService.calculateKeepRanges(removals: originalRemovals, duration: duration)
            let recoveredRemovals = MagicFixService.calculateRemovedRanges(from: keepRanges, duration: duration)

            // Assert - recovered removals should match original
            #expect(recoveredRemovals.count == originalRemovals.count)
            for (recovered, original) in zip(recoveredRemovals, originalRemovals) {
                #expect(abs(recovered.start.seconds - original.start.seconds) < 0.001)
                #expect(abs(recovered.end.seconds - original.end.seconds) < 0.001)
            }
        }
    }

    // MARK: - Edge Cases

    @Suite("Edge Cases")
    struct EdgeCaseTests {

        @Test("Zero duration handled gracefully")
        func zeroDurationHandled() {
            // Arrange
            let removals: [CMTimeRange] = []
            let duration = CMTime.zero

            // Act
            let keepRanges = MagicFixService.calculateKeepRanges(removals: removals, duration: duration)

            // Assert - should not crash
            #expect(keepRanges.isEmpty)
        }

        @Test("Very small removal ranges")
        func verySmallRemovalRanges() {
            // Arrange - 100ms removal
            let removals = [
                CMTimeRange(
                    start: CMTime(seconds: 10, preferredTimescale: 600),
                    end: CMTime(seconds: 10.1, preferredTimescale: 600)
                )
            ]
            let duration = CMTime(seconds: 60, preferredTimescale: 600)
            let expectedKeepCount = removals.count + 1

            // Act
            let keepRanges = MagicFixService.calculateKeepRanges(removals: removals, duration: duration)

            // Assert
            #expect(keepRanges.count == expectedKeepCount)
        }

        @Test("Many small removals")
        func manySmallRemovals() {
            // Arrange - 10 small removals
            var removals: [CMTimeRange] = []
            let removalCount = 10
            for i in 0..<removalCount {
                let start = Double(i * 6)
                removals.append(CMTimeRange(
                    start: CMTime(seconds: start, preferredTimescale: 600),
                    end: CMTime(seconds: start + 1, preferredTimescale: 600)
                ))
            }
            let duration = CMTime(seconds: 60, preferredTimescale: 600)

            // Act
            let keepRanges = MagicFixService.calculateKeepRanges(removals: removals, duration: duration)

            // Assert - should have 10 keep ranges (between each removal) + 1 at end
            #expect(keepRanges.count == removalCount)
        }

        @Test("Removal extending beyond duration is clipped")
        func removalBeyondDurationClipped() {
            // Arrange
            let removals = [
                CMTimeRange(
                    start: CMTime(seconds: 50, preferredTimescale: 600),
                    end: CMTime(seconds: 100, preferredTimescale: 600)  // Beyond 60s duration
                )
            ]
            let duration = CMTime(seconds: 60, preferredTimescale: 600)
            let removal = removals[0]

            // Act
            let keepRanges = MagicFixService.calculateKeepRanges(removals: removals, duration: duration)

            // Assert - should keep 0-50
            #expect(keepRanges.count == 1)
            #expect(keepRanges[0].start == .zero)
            #expect(keepRanges[0].end == removal.start)
        }
    }

    // MARK: - Applying keep ranges to a clip

    @Suite("Applying keep ranges")
    struct ApplyKeepRangesTests {
        @Test("Removed ranges from Magic Fix shrink effectiveDuration by exactly the removed time")
        func keepRangesShrinkEffectiveDuration() {
            let duration = CMTime(seconds: 30, preferredTimescale: 600)
            let silences = [
                CMTimeRange(start: CMTime(seconds: 4, preferredTimescale: 600), end: CMTime(seconds: 6.5, preferredTimescale: 600)),
                CMTimeRange(start: CMTime(seconds: 20, preferredTimescale: 600), end: CMTime(seconds: 21, preferredTimescale: 600))
            ]
            var clip = VideoClip(url: URL(fileURLWithPath: "/tmp/talk.mov"), duration: duration)

            let keep = MagicFixService.calculateKeepRanges(removals: silences, duration: duration)
            let removed = MagicFixService.calculateRemovedRanges(from: keep, duration: duration)
            clip.removedRanges = removed.map { CodableTimeRange($0) }

            #expect(abs(clip.effectiveDuration.seconds - 26.5) < 0.001)
        }

        @Test("Removed time outside the trim window does not shrink effectiveDuration")
        func removalsOutsideTrimAreIgnored() {
            var clip = VideoClip(url: URL(fileURLWithPath: "/tmp/talk.mov"), duration: CMTime(seconds: 30, preferredTimescale: 600))
            clip.trimEnd = CMTime(seconds: 10, preferredTimescale: 600)
            clip.removedRanges = [
                CodableTimeRange(CMTimeRange(start: CMTime(seconds: 8, preferredTimescale: 600), end: CMTime(seconds: 12, preferredTimescale: 600)))
            ]

            #expect(abs(clip.effectiveDuration.seconds - 8.0) < 0.001)
        }
    }

    // MARK: - Audio enhancement gating

    @Test("Audio enhancement runs only when enabled and the clip has an audio track")
    @MainActor
    func audioEnhancementIsSkippedForVideoOnlyClips() async {
        let videoOnly = VideoClip(
            url: TestEnvironment.testAsset(named: "website-demo-video-call.mp4"),
            duration: CMTime(seconds: 12, preferredTimescale: 600)
        )
        let withAudio = VideoClip(url: TestEnvironment.mockAssetURL, duration: CMTime(seconds: 5, preferredTimescale: 600))
        var disabled = MagicFixOptions()
        disabled.enhanceAudio = false

        #expect(await MagicFixService.shouldAttemptAudioEnhancement(for: videoOnly, options: MagicFixOptions()) == false)
        #expect(await MagicFixService.shouldAttemptAudioEnhancement(for: withAudio, options: MagicFixOptions()) == true)
        #expect(await MagicFixService.shouldAttemptAudioEnhancement(for: withAudio, options: disabled) == false)
    }

    // MARK: - MagicFixOptions

    @Suite("MagicFixOptions")
    struct MagicFixOptionsTests {
        @Test("isEmpty is true only when no cleanup step is selected")
        func isEmptyReflectsCleanupSteps() {
            var none = MagicFixOptions.minimal
            none.removeSilence = false
            var cursorOnly = none
            cursorOnly.applyHighlightCursor = true

            #expect(none.isEmpty)
            #expect(cursorOnly.isEmpty, "The highlight cursor alone is not a cleanup step")
            #expect(!MagicFixOptions.minimal.isEmpty)
            #expect(!MagicFixOptions.proClean.isEmpty)
        }

        @Test("summary lists the selected steps in a fixed order")
        func summaryListsSelectedSteps() {
            var options = MagicFixOptions.minimal
            options.enhanceAudio = true
            var none = MagicFixOptions.minimal
            none.removeSilence = false

            #expect(MagicFixOptions.proClean.summary == "Silence, Fillers, Captions, Speech, Cuts")
            #expect(options.summary == "Silence, Speech")
            #expect(none.summary == "No options selected")
        }

        @Test("Preset names follow equality with the presets; any change is Custom")
        func presetNameFollowsEquality() {
            var tweaked = MagicFixOptions.proClean
            tweaked.silenceThreshold = -50

            #expect(MagicFixOptions().presetName == "Pro Clean-up")
            #expect(MagicFixOptions.minimal.presetName == "Minimal Fix")
            #expect(tweaked != .proClean)
            #expect(tweaked.presetName == "Custom")
        }
    }
}
