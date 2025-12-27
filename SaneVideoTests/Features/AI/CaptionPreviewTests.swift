//
//  CaptionPreviewTests.swift
//  SaneVideoTests
//
//  Tests for caption preview functionality
//

import XCTest
import AVFoundation
@testable import SaneVideo

final class CaptionPreviewTests: XCTestCase {
    
    func testCaptionStylePropertiesForPreview() {
        let style = CaptionStyle.classic
        
        // Verify style has required properties for preview rendering
        XCTAssertFalse(style.fontName.isEmpty, "Style should have font name")
        XCTAssertGreaterThan(style.fontSize, 0, "Style should have positive font size")
        XCTAssertFalse(style.textColor.isEmpty, "Style should have text color")
    }
    
    func testCaptionStylesHaveValidProperties() {
        let styles: [CaptionStyle] = [.classic, .bold, .tikTok, .instagram, .youtube]
        
        for style in styles {
            XCTAssertFalse(style.fontName.isEmpty, "\(style.name) should have font name")
            XCTAssertGreaterThan(style.fontSize, 0, "\(style.name) should have positive font size")
            XCTAssertFalse(style.textColor.isEmpty, "\(style.name) should have text color")
        }
    }
    
    func testCaptionStyleIsCodable() {
        let style = CaptionStyle.classic
        
        // Test that style can be encoded/decoded (required for persistence)
        do {
            let encoder = JSONEncoder()
            let data = try encoder.encode(style)
            
            let decoder = JSONDecoder()
            let decoded = try decoder.decode(CaptionStyle.self, from: data)
            
            XCTAssertEqual(style.id, decoded.id, "Decoded style should match original")
            XCTAssertEqual(style.name, decoded.name, "Decoded style name should match")
            XCTAssertEqual(style.fontName, decoded.fontName, "Decoded font name should match")
        } catch {
            XCTFail("CaptionStyle should be Codable: \(error)")
        }
    }
    
    func testCaptionStyleEquality() {
        let style1 = CaptionStyle.classic
        let style2 = CaptionStyle.classic
        
        // Same preset should be equal
        XCTAssertEqual(style1.id, style2.id, "Same preset styles should have same ID")
    }
    
    func testCaptionStyleHashable() {
        let style1 = CaptionStyle.classic
        let style2 = CaptionStyle.bold
        
        var set = Set<CaptionStyle>()
        set.insert(style1)
        set.insert(style2)
        
        XCTAssertEqual(set.count, 2, "Different styles should be distinct in Set")
        XCTAssertTrue(set.contains(style1), "Set should contain style1")
        XCTAssertTrue(set.contains(style2), "Set should contain style2")
    }
}
