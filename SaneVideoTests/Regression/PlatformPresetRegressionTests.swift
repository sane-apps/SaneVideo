//
//  PlatformPresetRegressionTests.swift
//  SaneVideoTests
//
//  Regression tests for platform preset UI feature (2026-01-01)
//
//  Feature: Export presets with vertical aspect ratio support
//  Components:
//  - SaneExportSettings: Added aspectRatio field for vertical/square export
//  - ExportPreset: TikTok, Instagram, Twitter now use 9:16 vertical
//  - ExportCompositor: Uses settings.renderSize for aspect-aware dimensions
//

import Foundation
import Testing

@testable import SaneVideo

/// Regression tests for platform preset UI feature
@Suite("Platform Preset Regression Tests")
struct PlatformPresetRegressionTests {
    // MARK: - SaneExportSettings Tests

    @Test("SaneExportSettings has aspectRatio field")
    func saneExportSettingsHasAspectRatio() {
        var settings = SaneExportSettings()

        // Default should be nil (use source aspect ratio)
        #expect(settings.aspectRatio == nil, "Default aspectRatio should be nil")

        // Should be settable
        settings.aspectRatio = .vertical9x16
        #expect(settings.aspectRatio == .vertical9x16)

        settings.aspectRatio = .square1x1
        #expect(settings.aspectRatio == .square1x1)
    }

    @Test("renderSize returns resolution.size when aspectRatio is nil")
    func renderSizeWithNilAspectRatio() {
        var settings = SaneExportSettings()
        settings.aspectRatio = nil

        // 1080p
        settings.resolution = .hd1080
        let expected1080Size = settings.resolution.size
        #expect(settings.renderSize == expected1080Size)

        // 4K
        settings.resolution = .uhd4K
        let expected4KSize = settings.resolution.size
        #expect(settings.renderSize == expected4KSize)
    }

    @Test("renderSize calculates vertical 9:16 correctly")
    func renderSizeVertical() {
        var settings = SaneExportSettings()
        settings.aspectRatio = .vertical9x16

        // 1080p base (1920×1080) → vertical 1080×1920
        settings.resolution = .hd1080
        let size1080 = settings.renderSize
        #expect(size1080.width < size1080.height, "Vertical should have width < height")
        // Width = base height (1080), height = 1080 * 16/9 = 1920
        #expect(size1080.width == 1080, "1080p vertical width should be 1080")
        #expect(size1080.height == 1920, "1080p vertical height should be 1920")
    }

    @Test("renderSize calculates square 1:1 correctly")
    func renderSizeSquare() {
        var settings = SaneExportSettings()
        settings.aspectRatio = .square1x1
        settings.resolution = .hd1080

        let size = settings.renderSize
        let expectedSide = settings.resolution.size.height
        #expect(size.width == size.height, "Square should have equal width and height")
        #expect(size.width == expectedSide, "Square at 1080p should match resolution height")
    }

    @Test("SaneExportSettings is Codable with aspectRatio")
    func saneExportSettingsCodableWithAspectRatio() throws {
        var original = SaneExportSettings()
        original.aspectRatio = .vertical9x16
        original.resolution = .hd1080

        let encoded = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(SaneExportSettings.self, from: encoded)

        #expect(decoded.aspectRatio == .vertical9x16)
        #expect(decoded.resolution == .hd1080)
    }

    @Test("SaneExportSettings Codable handles nil aspectRatio")
    func saneExportSettingsCodableNilAspectRatio() throws {
        var original = SaneExportSettings()
        original.aspectRatio = nil

        let encoded = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(SaneExportSettings.self, from: encoded)

        #expect(decoded.aspectRatio == nil)
    }

    // MARK: - ExportPreset Tests

    @Test("ExportPreset TikTok description mentions vertical")
    func tikTokPresetDescription() {
        let description = ExportPreset.tiktok.description
        #expect(description.contains("9:16") || description.contains("vertical"),
                "TikTok preset should mention vertical format")
    }

    @Test("ExportPreset Instagram description mentions vertical")
    func instagramPresetDescription() {
        let description = ExportPreset.instagram.description
        #expect(description.contains("9:16") || description.contains("vertical") || description.contains("Reels"),
                "Instagram preset should mention vertical/Reels format")
    }

    @Test("ExportPreset Twitter description mentions vertical")
    func twitterPresetDescription() {
        let description = ExportPreset.twitter.description
        #expect(description.contains("9:16") || description.contains("vertical"),
                "Twitter preset should mention vertical format")
    }

    @Test("All presets have icons")
    func allPresetsHaveIcons() {
        for preset in ExportPreset.allCases {
            #expect(!preset.icon.isEmpty, "\(preset.rawValue) should have an icon")
        }
    }

    // MARK: - ShortAspectRatio Tests

    @Test("ShortAspectRatio vertical9x16 dimensions")
    func shortAspectRatioVertical() {
        let height = 1920
        let dims = ShortAspectRatio.vertical9x16.dimensions(forHeight: height)
        let expectedWidth = Int(CGFloat(height) * (9.0 / 16.0))
        #expect(dims.width == expectedWidth, "9:16 width should be derived from height")
        #expect(dims.height == height)
    }

    @Test("ShortAspectRatio square1x1 dimensions")
    func shortAspectRatioSquare() {
        let dims = ShortAspectRatio.square1x1.dimensions(forHeight: 1080)
        #expect(dims.width == dims.height, "Square should have equal dimensions")
    }

    @Test("ShortAspectRatio is Codable")
    func shortAspectRatioCodable() throws {
        let original = ShortAspectRatio.portrait4x5

        let encoded = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(ShortAspectRatio.self, from: encoded)

        #expect(decoded == original)
    }
}
