//
//  RepurposingTests.swift
//  SaneVideoTests
//
//  Tests for ShortCandidate, RepurposingSettings, and related models
//

import CoreMedia
import XCTest

@testable import SaneVideo

final class RepurposingTests: XCTestCase {

    // MARK: - HighlightType Tests

    func testHighlightTypeAllCases() {
        let allCases = HighlightType.allCases
        XCTAssertEqual(allCases.count, 7)
        XCTAssertTrue(allCases.contains(.applause))
        XCTAssertTrue(allCases.contains(.laughter))
        XCTAssertTrue(allCases.contains(.keyMoment))
    }

    func testHighlightTypeIcons() {
        for highlightType in HighlightType.allCases {
            XCTAssertFalse(highlightType.icon.isEmpty, "\(highlightType) should have an icon")
        }
    }

    func testHighlightTypeColors() {
        for highlightType in HighlightType.allCases {
            XCTAssertFalse(highlightType.color.isEmpty, "\(highlightType) should have a color")
        }
    }

    // MARK: - SuggestedCrop Tests

    func testSuggestedCropDefault() {
        let crop = SuggestedCrop.default

        XCTAssertEqual(crop.centerX, 0.5)
        XCTAssertEqual(crop.centerY, 0.5)
        XCTAssertEqual(crop.scale, 1.0)
    }

    func testSuggestedCropFocusedOn() {
        let faceCenter = CGPoint(x: 0.3, y: 0.7)
        let crop = SuggestedCrop.focusedOn(faceCenter: faceCenter, zoom: 1.5)

        XCTAssertEqual(crop.centerX, 0.3)
        XCTAssertEqual(crop.centerY, 0.7)
        XCTAssertEqual(crop.scale, 1.5)
    }

    func testSuggestedCropEquatable() {
        let crop1 = SuggestedCrop(centerX: 0.5, centerY: 0.5, scale: 1.0)
        let crop2 = SuggestedCrop(centerX: 0.5, centerY: 0.5, scale: 1.0)
        let crop3 = SuggestedCrop(centerX: 0.3, centerY: 0.7, scale: 1.2)

        XCTAssertEqual(crop1, crop2)
        XCTAssertNotEqual(crop1, crop3)
    }

    // MARK: - ShortCandidate Tests

    func testShortCandidateInitialization() {
        let timeRange = CMTimeRange(
            start: CMTime(seconds: 10, preferredTimescale: 600),
            duration: CMTime(seconds: 30, preferredTimescale: 600)
        )

        let candidate = ShortCandidate(
            timeRange: timeRange,
            score: 0.75,
            suggestedCrop: .default,
            highlights: [.applause, .laughter],
            hasFace: true,
            silencePercentage: 0.1,
            averageLoudness: -20.0,
            hasCaption: true
        )

        XCTAssertFalse(candidate.id.uuidString.isEmpty)
        XCTAssertEqual(candidate.score, 0.75)
        XCTAssertTrue(candidate.hasFace)
        XCTAssertEqual(candidate.highlights.count, 2)
        XCTAssertEqual(candidate.duration, 30.0, accuracy: 0.01)
        XCTAssertEqual(candidate.startTime, 10.0, accuracy: 0.01)
        XCTAssertEqual(candidate.endTime, 40.0, accuracy: 0.01)
    }

    func testShortCandidateScoreLabel() {
        let timeRange = CMTimeRange(
            start: .zero,
            duration: CMTime(seconds: 30, preferredTimescale: 600)
        )

        var candidate = ShortCandidate(timeRange: timeRange, score: 0.9)
        XCTAssertEqual(candidate.scoreLabel, "Excellent")

        candidate = ShortCandidate(timeRange: timeRange, score: 0.7)
        XCTAssertEqual(candidate.scoreLabel, "Good")

        candidate = ShortCandidate(timeRange: timeRange, score: 0.5)
        XCTAssertEqual(candidate.scoreLabel, "Fair")

        candidate = ShortCandidate(timeRange: timeRange, score: 0.2)
        XCTAssertEqual(candidate.scoreLabel, "Low")
    }

    func testShortCandidateDurationLabel() {
        let shortRange = CMTimeRange(
            start: .zero,
            duration: CMTime(seconds: 30, preferredTimescale: 600)
        )
        let shortCandidate = ShortCandidate(timeRange: shortRange)
        XCTAssertEqual(shortCandidate.durationLabel, "30s")

        let longRange = CMTimeRange(
            start: .zero,
            duration: CMTime(seconds: 90, preferredTimescale: 600)
        )
        let longCandidate = ShortCandidate(timeRange: longRange)
        XCTAssertEqual(longCandidate.durationLabel, "1m 30s")
    }

    func testShortCandidateCodable() throws {
        let timeRange = CMTimeRange(
            start: CMTime(seconds: 5, preferredTimescale: 600),
            duration: CMTime(seconds: 15, preferredTimescale: 600)
        )

        let original = ShortCandidate(
            timeRange: timeRange,
            score: 0.8,
            suggestedCrop: SuggestedCrop(centerX: 0.3, centerY: 0.7, scale: 1.2),
            titleSuggestion: "Test Title",
            highlights: [.keyMoment],
            hasFace: true,
            silencePercentage: 0.05,
            averageLoudness: -15.0,
            hasCaption: true
        )

        let encoder = JSONEncoder()
        let data = try encoder.encode(original)

        let decoder = JSONDecoder()
        let decoded = try decoder.decode(ShortCandidate.self, from: data)

        XCTAssertEqual(decoded.id, original.id)
        XCTAssertEqual(decoded.score, original.score)
        XCTAssertEqual(decoded.titleSuggestion, original.titleSuggestion)
        XCTAssertEqual(decoded.highlights, original.highlights)
        XCTAssertEqual(decoded.hasFace, original.hasFace)
        XCTAssertEqual(decoded.duration, 15.0, accuracy: 0.01)
    }

    func testShortCandidateHashable() {
        let timeRange = CMTimeRange(start: .zero, duration: CMTime(seconds: 30, preferredTimescale: 600))

        let candidate1 = ShortCandidate(timeRange: timeRange, score: 0.5)
        let candidate2 = ShortCandidate(timeRange: timeRange, score: 0.8)

        var set = Set<ShortCandidate>()
        set.insert(candidate1)
        set.insert(candidate2)
        set.insert(candidate1)  // Duplicate

        XCTAssertEqual(set.count, 2)
    }

    // MARK: - ShortDuration Tests

    func testShortDurationValues() {
        XCTAssertEqual(ShortDuration.fifteen.rawValue, 15)
        XCTAssertEqual(ShortDuration.thirty.rawValue, 30)
        XCTAssertEqual(ShortDuration.sixty.rawValue, 60)
        XCTAssertEqual(ShortDuration.ninety.rawValue, 90)
    }

    func testShortDurationLabels() {
        XCTAssertEqual(ShortDuration.fifteen.label, "15s")
        XCTAssertEqual(ShortDuration.thirty.label, "30s")
        XCTAssertEqual(ShortDuration.sixty.label, "60s")
        XCTAssertEqual(ShortDuration.ninety.label, "90s")
    }

    func testShortDurationDescriptions() {
        for duration in ShortDuration.allCases {
            XCTAssertFalse(duration.description.isEmpty)
        }
    }

    // MARK: - ShortAspectRatio Tests

    func testShortAspectRatioValues() {
        XCTAssertEqual(ShortAspectRatio.vertical9x16.rawValue, "9:16")
        XCTAssertEqual(ShortAspectRatio.square1x1.rawValue, "1:1")
        XCTAssertEqual(ShortAspectRatio.portrait4x5.rawValue, "4:5")
    }

    func testShortAspectRatioDimensions() {
        let vertical = ShortAspectRatio.vertical9x16.dimensions(forHeight: 1920)
        XCTAssertEqual(vertical.height, 1920)
        XCTAssertEqual(vertical.width, 1080)

        let square = ShortAspectRatio.square1x1.dimensions(forHeight: 1080)
        XCTAssertEqual(square.height, 1080)
        XCTAssertEqual(square.width, 1080)
    }

    // MARK: - ShortPlatform Tests

    func testShortPlatformRecommendedSettings() {
        XCTAssertEqual(ShortPlatform.tiktok.recommendedDuration, .thirty)
        XCTAssertEqual(ShortPlatform.youtubeShorts.recommendedDuration, .sixty)

        XCTAssertEqual(ShortPlatform.tiktok.recommendedAspectRatio, .vertical9x16)
        XCTAssertEqual(ShortPlatform.instagramReels.recommendedAspectRatio, .vertical9x16)
    }

    // MARK: - RepurposingSettings Tests

    func testRepurposingSettingsDefault() {
        let settings = RepurposingSettings.default

        XCTAssertEqual(settings.targetDuration, .thirty)
        XCTAssertEqual(settings.aspectRatio, .vertical9x16)
        XCTAssertEqual(settings.platform, .tiktok)
        XCTAssertEqual(settings.maxShorts, 5)
        XCTAssertTrue(settings.detectFaces)
        XCTAssertTrue(settings.detectHighlights)
        XCTAssertTrue(settings.smartCrop)
    }

    func testRepurposingSettingsMaxShortsClamping() {
        let tooLow = RepurposingSettings(maxShorts: 0)
        XCTAssertEqual(tooLow.maxShorts, 1, "Max shorts below 1 should be clamped")

        let tooHigh = RepurposingSettings(maxShorts: 100)
        XCTAssertEqual(tooHigh.maxShorts, 10, "Max shorts above 10 should be clamped")
    }

    func testRepurposingSettingsApplyPlatformPreset() {
        var settings = RepurposingSettings.default

        settings.applyPlatformPreset(.youtubeShorts)
        XCTAssertEqual(settings.platform, .youtubeShorts)
        XCTAssertEqual(settings.targetDuration, .sixty)
        XCTAssertEqual(settings.aspectRatio, .vertical9x16)
    }

    func testRepurposingSettingsPresets() {
        let tiktok = RepurposingSettings.tiktok
        XCTAssertEqual(tiktok.platform, .tiktok)
        XCTAssertEqual(tiktok.targetDuration, .thirty)

        let youtube = RepurposingSettings.youtubeShorts
        XCTAssertEqual(youtube.platform, .youtubeShorts)
        XCTAssertEqual(youtube.targetDuration, .sixty)
    }

    func testRepurposingSettingsEquatable() {
        let settings1 = RepurposingSettings.default
        let settings2 = RepurposingSettings.default
        var settings3 = RepurposingSettings.default
        settings3.maxShorts = 10

        XCTAssertEqual(settings1, settings2)
        XCTAssertNotEqual(settings1, settings3)
    }

    func testRepurposingSettingsCodable() throws {
        let original = RepurposingSettings(
            targetDuration: .sixty,
            aspectRatio: .square1x1,
            platform: .instagramReels,
            maxShorts: 3
        )

        let encoder = JSONEncoder()
        let data = try encoder.encode(original)

        let decoder = JSONDecoder()
        let decoded = try decoder.decode(RepurposingSettings.self, from: data)

        XCTAssertEqual(decoded.targetDuration, original.targetDuration)
        XCTAssertEqual(decoded.aspectRatio, original.aspectRatio)
        XCTAssertEqual(decoded.platform, original.platform)
        XCTAssertEqual(decoded.maxShorts, original.maxShorts)
    }

    // MARK: - RepurposingError Tests

    func testRepurposingErrorDescriptions() {
        let errors: [RepurposingError] = [
            .videoTooShort(duration: 10, required: 30),
            .analysisFailureAudio(NSError(domain: "test", code: 1)),
            .analysisFailureVideo(NSError(domain: "test", code: 2)),
            .noCandidatesFound
        ]

        for error in errors {
            XCTAssertNotNil(error.errorDescription)
            XCTAssertFalse(error.errorDescription!.isEmpty)
        }
    }
}
