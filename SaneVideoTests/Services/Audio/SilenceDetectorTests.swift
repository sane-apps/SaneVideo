//
//  SilenceDetectorTests.swift
//  SaneVideoTests
//
//  Tests for SilenceDetector: no-audio-track handling, margin, tolerance
//

import Testing
import Foundation
import CoreMedia
@testable import SaneVideo

@Suite("SilenceDetector Tests")
struct SilenceDetectorTests {

    // MARK: - Apply Margin Tests

    @Suite("Apply Margin")
    struct ApplyMarginTests {

        @Test("Margin shrinks ranges on both sides")
        func marginShrinksRanges() {
            // Arrange: 10s-20s range with 0.1s margin
            let ranges = [
                CMTimeRange(
                    start: CMTime(seconds: 10, preferredTimescale: 600),
                    end: CMTime(seconds: 20, preferredTimescale: 600)
                )
            ]

            // Act
            let result = SilenceDetector.applyMargin(ranges, margin: 0.1)

            // Assert: should be 10.1 - 19.9
            #expect(result.count == 1)
            #expect(abs(result[0].start.seconds - 10.1) < 0.01)
            #expect(abs(result[0].end.seconds - 19.9) < 0.01)
        }

        @Test("Margin drops ranges that collapse")
        func marginDropsCollapsedRanges() {
            // Arrange: 10.0-10.15s range (150ms) with 100ms margin = collapses
            let ranges = [
                CMTimeRange(
                    start: CMTime(seconds: 10.0, preferredTimescale: 600),
                    end: CMTime(seconds: 10.15, preferredTimescale: 600)
                )
            ]

            // Act
            let result = SilenceDetector.applyMargin(ranges, margin: 0.1)

            // Assert: range too small after margin, should be dropped
            #expect(result.isEmpty)
        }

        @Test("Zero margin returns ranges unchanged")
        func zeroMarginUnchanged() {
            // Arrange
            let ranges = [
                CMTimeRange(
                    start: CMTime(seconds: 5, preferredTimescale: 600),
                    end: CMTime(seconds: 15, preferredTimescale: 600)
                )
            ]

            // Act
            let result = SilenceDetector.applyMargin(ranges, margin: 0.0)

            // Assert
            #expect(result.count == 1)
            #expect(result[0].start.seconds == 5)
            #expect(result[0].end.seconds == 15)
        }

        @Test("Multiple ranges with margin")
        func multipleRangesWithMargin() {
            // Arrange: two ranges, one survives margin, one collapses
            let ranges = [
                CMTimeRange(
                    start: CMTime(seconds: 0, preferredTimescale: 600),
                    end: CMTime(seconds: 5, preferredTimescale: 600)
                ),
                CMTimeRange(
                    start: CMTime(seconds: 10, preferredTimescale: 600),
                    end: CMTime(seconds: 10.1, preferredTimescale: 600)
                )
            ]

            // Act
            let result = SilenceDetector.applyMargin(ranges, margin: 0.1)

            // Assert: first survives (0.1-4.9), second collapses
            #expect(result.count == 1)
            #expect(abs(result[0].start.seconds - 0.1) < 0.01)
            #expect(abs(result[0].end.seconds - 4.9) < 0.01)
        }

        @Test("Empty ranges returns empty")
        func emptyRangesReturnsEmpty() {
            let result = SilenceDetector.applyMargin([], margin: 0.5)
            #expect(result.isEmpty)
        }
    }

    // MARK: - Configuration Tests

    @Suite("Configuration")
    struct ConfigurationTests {

        @Test("Default configuration has expected values")
        func defaultConfig() {
            let config = SilenceDetector.Configuration.default

            #expect(config.dbThreshold == -45.0)
            #expect(config.minDuration == 0.3)
            #expect(config.margin == 0.1)
            #expect(config.tolerance == 0.1)
        }

        @Test("Custom configuration preserves values")
        func customConfig() {
            let config = SilenceDetector.Configuration(
                dbThreshold: -35.0,
                minDuration: 0.5,
                margin: 0.2,
                tolerance: 0.05
            )

            #expect(config.dbThreshold == -35.0)
            #expect(config.minDuration == 0.5)
            #expect(config.margin == 0.2)
            #expect(config.tolerance == 0.05)
        }
    }

    // MARK: - MagicFixOptions Integration Tests

    @Suite("MagicFixOptions Silence Settings")
    struct MagicFixOptionsSilenceTests {

        @Test("Default options include margin and tolerance")
        func defaultOptionsHaveMarginAndTolerance() {
            let options = MagicFixOptions()

            #expect(options.silenceMargin == 0.1)
            #expect(options.silenceTolerance == 0.1)
        }

        @Test("Options are Codable with new fields")
        func codableWithNewFields() throws {
            let original = MagicFixOptions(
                silenceMargin: 0.2,
                silenceTolerance: 0.15
            )

            let data = try JSONEncoder().encode(original)
            let decoded = try JSONDecoder().decode(MagicFixOptions.self, from: data)

            #expect(decoded.silenceMargin == 0.2)
            #expect(decoded.silenceTolerance == 0.15)
        }
    }
}
