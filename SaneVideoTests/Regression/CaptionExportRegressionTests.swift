//
//  CaptionExportRegressionTests.swift
//  SaneVideoTests
//
//  Regression tests for caption burn-in export (2026-01-01)
//
//  Bug: Captions not burned into exported video
//  Fix: Added style and words fields to TextLayerItem,
//       updated TextLayerBuilder to pass caption data,
//       updated TextLayerRenderer to use CaptionStyle
//

import AppKit
import CoreMedia
import Testing

@testable import SaneVideo

/// Regression tests for caption export styling and karaoke highlighting
@Suite("Caption Export Regression Tests")
struct CaptionExportRegressionTests {

    // MARK: - TextLayerItem Tests

    /// Verifies TextLayerItem can carry CaptionStyle
    @Test("TextLayerItem carries style property")
    func testTextLayerItemHasStyle() async throws {
        let style = CaptionStyle.tikTok

        let item = TextLayerItem(
            id: UUID(),
            text: "Test caption",
            frame: CGRect(x: 0.1, y: 0.8, width: 0.8, height: 0.15),
            timeRange: CMTimeRange(start: .zero, duration: CMTime(seconds: 5, preferredTimescale: 600)),
            isCaption: true,
            style: style,
            words: nil
        )

        #expect(item.style != nil, "TextLayerItem should carry style")
        #expect(item.style?.name == "TikTok", "Style should be TikTok preset")
        #expect(item.style?.fontName == "Futura", "TikTok style uses Futura font")
    }

    /// Verifies TextLayerItem can carry word-level timing
    @Test("TextLayerItem carries words for karaoke")
    func testTextLayerItemHasWords() async throws {
        let words = [
            CaptionWord(text: "Hello", start: 0.0, end: 0.5, probability: 0.95),
            CaptionWord(text: "World", start: 0.5, end: 1.0, probability: 0.92)
        ]

        let item = TextLayerItem(
            id: UUID(),
            text: "Hello World",
            frame: CGRect(x: 0.1, y: 0.8, width: 0.8, height: 0.15),
            timeRange: CMTimeRange(start: .zero, duration: CMTime(seconds: 1, preferredTimescale: 600)),
            isCaption: true,
            style: .karaoke,
            words: words
        )

        #expect(item.words != nil, "TextLayerItem should carry words")
        #expect(item.words?.count == 2, "Should have 2 words")
        #expect(item.words?.first?.text == "Hello", "First word should be Hello")
    }

    // MARK: - CaptionStyle Tests

    /// Verifies CaptionStyle presets have expected properties
    @Test("CaptionStyle presets are correctly defined")
    func testCaptionStylePresets() async throws {
        // TikTok preset
        let tikTok = CaptionStyle.tikTok
        let expectedFontSize: CGFloat = 56
        #expect(tikTok.fontName == "Futura")
        #expect(tikTok.fontSize == expectedFontSize)
        #expect(tikTok.isBold == true)
        #expect(tikTok.strokeWidth == 4)

        // Karaoke preset
        let karaoke = CaptionStyle.karaoke
        #expect(karaoke.highlightStyle == .pop)
        #expect(karaoke.activeTextColor == "#FFD700") // Gold
    }

    /// Verifies karaoke highlight styles exist
    @Test("CaptionStyle has karaoke highlight styles")
    func testKaraokeHighlightStyles() async throws {
        let styles: [CaptionStyle.HighlightStyle] = [.none, .pop, .glow, .underline, .background]

        for style in styles {
            // Ensure each style is valid enum case
            #expect(style.rawValue.isEmpty == false || style == .none)
        }

        #expect(CaptionStyle.HighlightStyle.pop.rawValue == "pop")
        #expect(CaptionStyle.HighlightStyle.glow.rawValue == "glow")
        #expect(CaptionStyle.HighlightStyle.underline.rawValue == "underline")
        #expect(CaptionStyle.HighlightStyle.background.rawValue == "background")
    }

    // MARK: - Word Timing Tests

    /// Verifies CaptionWord timing calculations
    @Test("CaptionWord timeRange is correct")
    func testCaptionWordTimeRange() async throws {
        let word = CaptionWord(text: "Test", start: 1.5, end: 2.0, probability: 0.98)

        let range = word.timeRange
        #expect(abs(range.start.seconds - 1.5) < 0.001, "Start should be 1.5 seconds")
        #expect(abs(range.duration.seconds - 0.5) < 0.001, "Duration should be 0.5 seconds")
    }

    /// Verifies word lookup at specific time
    @Test("Active word found at composition time")
    func testActiveWordAtTime() async throws {
        let words = [
            CaptionWord(text: "Hello", start: 0.0, end: 0.5, probability: 0.95),
            CaptionWord(text: "World", start: 0.5, end: 1.0, probability: 0.92)
        ]

        let time1 = 0.25 // Should match "Hello"
        let time2 = 0.75 // Should match "World"
        let time3 = 1.5  // Should match nothing

        let activeWord1 = words.first { time1 >= $0.start && time1 < $0.end }
        let activeWord2 = words.first { time2 >= $0.start && time2 < $0.end }
        let activeWord3 = words.first { time3 >= $0.start && time3 < $0.end }

        #expect(activeWord1?.text == "Hello", "At 0.25s, 'Hello' should be active")
        #expect(activeWord2?.text == "World", "At 0.75s, 'World' should be active")
        #expect(activeWord3 == nil, "At 1.5s, no word should be active")
    }

    // MARK: - NSColor Hex Extension Tests

    /// Verifies NSColor hex initialization works
    @Test("NSColor hex extension parses colors correctly")
    func testNSColorHexExtension() async throws {
        // Test 6-digit hex
        let white = NSColor(hex: "#FFFFFF")
        #expect(white != nil, "White hex should parse")

        // Test without hash
        let red = NSColor(hex: "FF0000")
        #expect(red != nil, "Red hex without hash should parse")

        // Test 8-digit hex with alpha
        let semiTransparent = NSColor(hex: "#80FFFFFF")
        #expect(semiTransparent != nil, "ARGB hex should parse")

        // Test invalid hex
        let invalid = NSColor(hex: "invalid")
        #expect(invalid == nil, "Invalid hex should return nil")
    }
}
