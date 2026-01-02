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
    func testSaneExportSettingsHasAspectRatio() {
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
    func testRenderSizeWithNilAspectRatio() {
        var settings = SaneExportSettings()
        settings.aspectRatio = nil

        // 1080p
        settings.resolution = .hd1080
        #expect(settings.renderSize.width == 1920)
        #expect(settings.renderSize.height == 1080)

        // 4K
        settings.resolution = .uhd4K
        #expect(settings.renderSize.width == 3840)
        #expect(settings.renderSize.height == 2160)
    }

    @Test("renderSize calculates vertical 9:16 correctly")
    func testRenderSizeVertical() {
        var settings = SaneExportSettings()
        settings.aspectRatio = .vertical9x16

        // 1080p base -> 1080x1920 vertical
        settings.resolution = .hd1080
        let size1080 = settings.renderSize
        #expect(size1080.width < size1080.height, "Vertical should have width < height")
        // Width should be 9/16 of height
        let expectedWidth1080 = 1080.0 * (9.0 / 16.0)  // 607.5
        #expect(abs(size1080.width - expectedWidth1080) < 1, "1080p vertical width calculation")
    }

    @Test("renderSize calculates square 1:1 correctly")
    func testRenderSizeSquare() {
        var settings = SaneExportSettings()
        settings.aspectRatio = .square1x1
        settings.resolution = .hd1080

        let size = settings.renderSize
        #expect(size.width == size.height, "Square should have equal width and height")
        #expect(size.width == 1080, "Square at 1080p should be 1080x1080")
    }

    @Test("SaneExportSettings is Codable with aspectRatio")
    func testSaneExportSettingsCodableWithAspectRatio() throws {
        var original = SaneExportSettings()
        original.aspectRatio = .vertical9x16
        original.resolution = .hd1080

        let encoded = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(SaneExportSettings.self, from: encoded)

        #expect(decoded.aspectRatio == .vertical9x16)
        #expect(decoded.resolution == .hd1080)
    }

    @Test("SaneExportSettings Codable handles nil aspectRatio")
    func testSaneExportSettingsCodableNilAspectRatio() throws {
        var original = SaneExportSettings()
        original.aspectRatio = nil

        let encoded = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(SaneExportSettings.self, from: encoded)

        #expect(decoded.aspectRatio == nil)
    }

    // MARK: - ExportPreset Tests

    @Test("ExportPreset TikTok description mentions vertical")
    func testTikTokPresetDescription() {
        let description = ExportPreset.tiktok.description
        #expect(description.contains("9:16") || description.contains("vertical"),
                "TikTok preset should mention vertical format")
    }

    @Test("ExportPreset Instagram description mentions vertical")
    func testInstagramPresetDescription() {
        let description = ExportPreset.instagram.description
        #expect(description.contains("9:16") || description.contains("vertical") || description.contains("Reels"),
                "Instagram preset should mention vertical/Reels format")
    }

    @Test("ExportPreset Twitter description mentions vertical")
    func testTwitterPresetDescription() {
        let description = ExportPreset.twitter.description
        #expect(description.contains("9:16") || description.contains("vertical"),
                "Twitter preset should mention vertical format")
    }

    @Test("All presets have icons")
    func testAllPresetsHaveIcons() {
        for preset in ExportPreset.allCases {
            #expect(!preset.icon.isEmpty, "\(preset.rawValue) should have an icon")
        }
    }

    // MARK: - ShortAspectRatio Tests

    @Test("ShortAspectRatio vertical9x16 dimensions")
    func testShortAspectRatioVertical() {
        let dims = ShortAspectRatio.vertical9x16.dimensions(forHeight: 1920)
        #expect(dims.width == 1080, "9:16 at height 1920 should have width 1080")
        #expect(dims.height == 1920)
    }

    @Test("ShortAspectRatio square1x1 dimensions")
    func testShortAspectRatioSquare() {
        let dims = ShortAspectRatio.square1x1.dimensions(forHeight: 1080)
        #expect(dims.width == dims.height, "Square should have equal dimensions")
    }

    @Test("ShortAspectRatio is Codable")
    func testShortAspectRatioCodable() throws {
        let original = ShortAspectRatio.portrait4x5

        let encoded = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(ShortAspectRatio.self, from: encoded)

        #expect(decoded == original)
    }
}
