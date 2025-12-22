//
//  ProjectTemplateTests.swift
//  SaneVideoTests
//
//  Tests for project template functionality
//

import XCTest
import AVFoundation
@testable import SaneVideo

final class ProjectTemplateTests: XCTestCase {
    
    func testAllTemplatesExist() {
        let templates = ProjectTemplate.allTemplates
        XCTAssertEqual(templates.count, 4, "Should have 4 templates: YouTube, TikTok, Instagram, Custom")
        
        let templateNames = Set(templates.map { $0.name })
        XCTAssertTrue(templateNames.contains("YouTube"), "Should have YouTube template")
        XCTAssertTrue(templateNames.contains("TikTok"), "Should have TikTok template")
        XCTAssertTrue(templateNames.contains("Instagram"), "Should have Instagram template")
        XCTAssertTrue(templateNames.contains("Custom"), "Should have Custom template")
    }
    
    func testYouTubeTemplateSettings() {
        let template = ProjectTemplate.youtube
        
        XCTAssertEqual(template.aspectRatio.width, 16, "YouTube should be 16:9")
        XCTAssertEqual(template.aspectRatio.height, 9, "YouTube should be 16:9")
        XCTAssertEqual(template.defaultExportSettings.resolution, .uhd4K, "YouTube should default to 4K")
        XCTAssertEqual(template.defaultExportSettings.codec, .hevc, "YouTube should use HEVC")
        XCTAssertEqual(template.defaultCaptionStyle, "YouTube", "YouTube should have YouTube caption style")
    }
    
    func testTikTokTemplateSettings() {
        let template = ProjectTemplate.tiktok
        
        XCTAssertEqual(template.aspectRatio.width, 9, "TikTok should be 9:16")
        XCTAssertEqual(template.aspectRatio.height, 16, "TikTok should be 9:16")
        XCTAssertEqual(template.defaultExportSettings.resolution, .hd1080, "TikTok should default to 1080p")
        XCTAssertEqual(template.defaultExportSettings.codec, .h264, "TikTok should use H.264")
        XCTAssertEqual(template.defaultCaptionStyle, "TikTok", "TikTok should have TikTok caption style")
    }
    
    func testInstagramTemplateSettings() {
        let template = ProjectTemplate.instagram
        
        XCTAssertEqual(template.aspectRatio.width, 1, "Instagram should be 1:1")
        XCTAssertEqual(template.aspectRatio.height, 1, "Instagram should be 1:1")
        XCTAssertEqual(template.defaultExportSettings.resolution, .hd1080, "Instagram should default to 1080p")
        XCTAssertEqual(template.defaultExportSettings.codec, .h264, "Instagram should use H.264")
        XCTAssertEqual(template.defaultCaptionStyle, "Instagram", "Instagram should have Instagram caption style")
    }
    
    func testCustomTemplateSettings() {
        let template = ProjectTemplate.custom
        
        XCTAssertEqual(template.aspectRatio.width, 16, "Custom should default to 16:9")
        XCTAssertEqual(template.aspectRatio.height, 9, "Custom should default to 16:9")
        XCTAssertEqual(template.defaultCaptionStyle, "Classic", "Custom should have Classic caption style")
    }
    
    func testTemplateIdentifiable() {
        let templates = ProjectTemplate.allTemplates
        let ids = templates.map { $0.id }
        let uniqueIds = Set(ids)
        
        XCTAssertEqual(ids.count, uniqueIds.count, "All template IDs should be unique")
    }
}
