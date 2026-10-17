//
//  CaptionExportRegressionTests.swift
//  SaneVideoTests
//
//  Caption burn-in inputs: word time ranges for karaoke highlighting, and the
//  hex colors caption styles are stored as.
//

import AppKit
import CoreMedia
@testable import SaneVideo
import Testing

@Suite("Caption Export Regression Tests")
struct CaptionExportRegressionTests {
    @Test("CaptionWord timeRange starts at start and lasts end - start")
    func captionWordTimeRange() {
        let word = CaptionWord(text: "Test", start: 1.5, end: 2.0, probability: 0.98)

        #expect(abs(word.timeRange.start.seconds - 1.5) < 0.001)
        #expect(abs(word.timeRange.duration.seconds - 0.5) < 0.001)
    }

    @Test(
        "NSColor(hex:) parses RGB, RGB without hash, short RGB and ARGB",
        arguments: [
            ("#FFFFFF", 1.0, 1.0, 1.0, 1.0),
            ("FF0000", 1.0, 0.0, 0.0, 1.0),
            ("#0F0", 0.0, 1.0, 0.0, 1.0),
            ("#80FFD700", 1.0, 215.0 / 255.0, 0.0, 128.0 / 255.0)
        ]
    )
    func hexParsesComponents(hex: String, red: Double, green: Double, blue: Double, alpha: Double) throws {
        let color = try #require(NSColor(hex: hex))

        #expect(abs(Double(color.redComponent) - red) < 0.002)
        #expect(abs(Double(color.greenComponent) - green) < 0.002)
        #expect(abs(Double(color.blueComponent) - blue) < 0.002)
        #expect(abs(Double(color.alphaComponent) - alpha) < 0.002)
    }

    @Test("NSColor(hex:) rejects strings that are not 3, 6 or 8 hex digits")
    func hexRejectsInvalid() {
        #expect(NSColor(hex: "invalid") == nil)
        #expect(NSColor(hex: "#12345") == nil)
    }
}
