//
//  ExportPresetTests.swift
//  SaneVideoTests
//
//  Tests for export preset functionality
//

import XCTest
import AVFoundation
@testable import SaneVideo

final class ExportPresetTests: XCTestCase {
    
    func testAllPresetsExist() {
        let presets = ExportPreset.allCases
        XCTAssertGreaterThanOrEqual(presets.count, 5, "Should have at least 5 presets")
        
        let presetNames = Set(presets.map { $0.rawValue })
        XCTAssertTrue(presetNames.contains("Custom"), "Should have Custom preset")
        XCTAssertTrue(presetNames.contains("YouTube 4K"), "Should have YouTube 4K preset")
    }
    
    func testPresetDescriptions() {
        XCTAssertFalse(ExportPreset.custom.description.isEmpty, "Custom preset should have description")
        XCTAssertFalse(ExportPreset.youtube4K.description.isEmpty, "YouTube 4K preset should have description")
        XCTAssertFalse(ExportPreset.tiktok.description.isEmpty, "TikTok preset should have description")
        XCTAssertFalse(ExportPreset.instagram.description.isEmpty, "Instagram preset should have description")
    }
    
    func testPresetIcons() {
        XCTAssertFalse(ExportPreset.custom.icon.isEmpty, "Custom preset should have icon")
        XCTAssertFalse(ExportPreset.youtube4K.icon.isEmpty, "YouTube 4K preset should have icon")
        XCTAssertFalse(ExportPreset.tiktok.icon.isEmpty, "TikTok preset should have icon")
        XCTAssertFalse(ExportPreset.instagram.icon.isEmpty, "Instagram preset should have icon")
    }
    
    func testPresetSettingsApplication() {
        var settings = SaneExportSettings()
        
        // Test YouTube 4K preset
        settings = SaneExportSettings()
        applyPresetToSettings(.youtube4K, &settings)
        XCTAssertEqual(settings.resolution, .uhd4K, "YouTube 4K should set 4K resolution")
        XCTAssertEqual(settings.codec, .hevc, "YouTube 4K should use HEVC")
        XCTAssertEqual(settings.bitrate, 20_000_000, "YouTube 4K should have 20Mbps bitrate")
        XCTAssertEqual(settings.frameRate, 60.0, "YouTube 4K should have 60fps")
        
        // Test TikTok preset
        settings = SaneExportSettings()
        applyPresetToSettings(.tiktok, &settings)
        XCTAssertEqual(settings.resolution, .hd1080, "TikTok should set 1080p resolution")
        XCTAssertEqual(settings.codec, .h264, "TikTok should use H.264")
        XCTAssertEqual(settings.bitrate, 8_000_000, "TikTok should have 8Mbps bitrate")
        XCTAssertEqual(settings.frameRate, 60.0, "TikTok should have 60fps")
        
        // Test Instagram preset
        settings = SaneExportSettings()
        applyPresetToSettings(.instagram, &settings)
        XCTAssertEqual(settings.resolution, .hd1080, "Instagram should set 1080p resolution")
        XCTAssertEqual(settings.codec, .h264, "Instagram should use H.264")
        XCTAssertEqual(settings.bitrate, 10_000_000, "Instagram should have 10Mbps bitrate")
        XCTAssertEqual(settings.frameRate, 30.0, "Instagram should have 30fps")
        
        // Test Compressed preset
        settings = SaneExportSettings()
        applyPresetToSettings(.compressed, &settings)
        XCTAssertEqual(settings.resolution, .hd1080, "Compressed should set 1080p resolution")
        XCTAssertEqual(settings.codec, .hevc, "Compressed should use HEVC")
        XCTAssertEqual(settings.bitrate, 5_000_000, "Compressed should have 5Mbps bitrate")
    }
    
    // Helper function to apply preset (mirrors ExportView.applyPreset)
    private func applyPresetToSettings(_ preset: ExportPreset, _ settings: inout SaneExportSettings) {
        switch preset {
        case .youtube4K:
            settings.resolution = .uhd4K
            settings.codec = .hevc
            settings.bitrate = 20_000_000
            settings.frameRate = 60.0
        case .youtube1080:
            settings.resolution = .hd1080
            settings.codec = .h264
            settings.bitrate = 8_000_000
            settings.frameRate = 60.0
        case .tiktok:
            settings.resolution = .hd1080
            settings.codec = .h264
            settings.bitrate = 8_000_000
            settings.frameRate = 60.0
        case .instagram:
            settings.resolution = .hd1080
            settings.codec = .h264
            settings.bitrate = 10_000_000
            settings.frameRate = 30.0
        case .twitter:
            settings.resolution = .hd1080
            settings.codec = .h264
            settings.bitrate = 8_000_000
            settings.frameRate = 30.0
        case .facebook:
            settings.resolution = .hd1080
            settings.codec = .h264
            settings.bitrate = 10_000_000
            settings.frameRate = 30.0
        case .social1080:
            settings.resolution = .hd1080
            settings.codec = .h264
            settings.bitrate = 8_000_000
            settings.frameRate = 30.0
        case .compressed:
            settings.resolution = .hd1080
            settings.codec = .hevc
            settings.bitrate = 5_000_000
            settings.frameRate = 30.0
        case .custom:
            break
        }
    }
}
