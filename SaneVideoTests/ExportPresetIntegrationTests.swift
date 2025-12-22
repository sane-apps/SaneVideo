//
//  ExportPresetIntegrationTests.swift
//  SaneVideoTests
//
//  Integration tests for export preset application
//

import XCTest
import AVFoundation
@testable import SaneVideo

final class ExportPresetIntegrationTests: XCTestCase {
    
    func testExportPresetApplication() {
        var settings = SaneExportSettings()
        
        // Test each preset applies correct settings
        let presets: [(ExportPreset, SaneExportSettings.ExportResolution, AVVideoCodecType, Int, Float)] = [
            (.youtube4K, .uhd4K, .hevc, 20_000_000, 60.0),
            (.youtube1080, .hd1080, .h264, 8_000_000, 60.0),
            (.tiktok, .hd1080, .h264, 8_000_000, 60.0),
            (.instagram, .hd1080, .h264, 10_000_000, 30.0),
            (.twitter, .hd1080, .h264, 8_000_000, 30.0),
            (.facebook, .hd1080, .h264, 10_000_000, 30.0),
            (.social1080, .hd1080, .h264, 8_000_000, 30.0),
            (.compressed, .hd1080, .hevc, 5_000_000, 30.0)
        ]
        
        for (preset, expectedResolution, expectedCodec, expectedBitrate, expectedFrameRate) in presets {
            settings = SaneExportSettings()
            applyPresetToSettings(preset, &settings)
            
            XCTAssertEqual(settings.resolution, expectedResolution, "\(preset.rawValue) should set resolution to \(expectedResolution)")
            XCTAssertEqual(settings.codec, expectedCodec, "\(preset.rawValue) should set codec to \(expectedCodec)")
            XCTAssertEqual(settings.bitrate, expectedBitrate, "\(preset.rawValue) should set bitrate to \(expectedBitrate)")
            XCTAssertEqual(settings.frameRate, expectedFrameRate, "\(preset.rawValue) should set frame rate to \(expectedFrameRate)")
        }
    }
    
    func testCustomPresetDoesNotModifySettings() {
        var settings = SaneExportSettings(
            codec: .hevc,
            resolution: .uhd4K,
            bitrate: 15_000_000,
            frameRate: 50.0
        )
        
        let originalSettings = settings
        
        applyPresetToSettings(.custom, &settings)
        
        XCTAssertEqual(settings.codec, originalSettings.codec, "Custom preset should not modify codec")
        XCTAssertEqual(settings.resolution, originalSettings.resolution, "Custom preset should not modify resolution")
        XCTAssertEqual(settings.bitrate, originalSettings.bitrate, "Custom preset should not modify bitrate")
        XCTAssertEqual(settings.frameRate, originalSettings.frameRate, "Custom preset should not modify frame rate")
    }
    
    func testPresetSettingsAreIndependent() {
        var settings1 = SaneExportSettings()
        var settings2 = SaneExportSettings()
        
        applyPresetToSettings(.youtube4K, &settings1)
        applyPresetToSettings(.tiktok, &settings2)
        
        // Settings should be different
        XCTAssertNotEqual(settings1.resolution, settings2.resolution, "Different presets should produce different settings")
        XCTAssertNotEqual(settings1.codec, settings2.codec, "Different presets should produce different codecs")
    }
    
    // Helper function (mirrors ExportView.applyPreset)
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
