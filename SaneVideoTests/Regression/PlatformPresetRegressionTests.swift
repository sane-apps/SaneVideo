//
//  PlatformPresetRegressionTests.swift
//  SaneVideoTests
//
//  Export render size for vertical/square/portrait platform presets, and even
//  encoder-safe dimensions for Shorts.
//

import CoreGraphics
import Foundation
@testable import SaneVideo
import Testing

@Suite("Platform Preset Regression Tests")
struct PlatformPresetRegressionTests {
    @Test(
        "renderSize follows the aspect ratio override, or the resolution when there is none",
        arguments: [
            (nil, SaneExportSettings.ExportResolution.hd1080, CGSize(width: 1920, height: 1080)),
            (nil, .uhd4K, CGSize(width: 3840, height: 2160)),
            (ShortAspectRatio.vertical9x16, .hd1080, CGSize(width: 1080, height: 1920)),
            (.vertical9x16, .uhd4K, CGSize(width: 2160, height: 3840)),
            (.square1x1, .hd1080, CGSize(width: 1080, height: 1080)),
            (.portrait4x5, .hd1080, CGSize(width: 864, height: 1080))
        ] as [(ShortAspectRatio?, SaneExportSettings.ExportResolution, CGSize)]
    )
    func renderSize(aspect: ShortAspectRatio?, resolution: SaneExportSettings.ExportResolution, expected: CGSize) {
        var settings = SaneExportSettings()
        settings.aspectRatio = aspect
        settings.resolution = resolution

        #expect(abs(settings.renderSize.width - expected.width) < 0.5)
        #expect(abs(settings.renderSize.height - expected.height) < 0.5)
    }

    @Test(
        "Shorts dimensions keep the ratio and round down to even numbers for the encoder",
        arguments: [
            (ShortAspectRatio.vertical9x16, 1080, 606, 1080),
            (.vertical9x16, 1920, 1080, 1920),
            (.square1x1, 1081, 1080, 1080),
            (.portrait4x5, 1080, 864, 1080)
        ]
    )
    func shortDimensions(aspect: ShortAspectRatio, height: Int, expectedWidth: Int, expectedHeight: Int) {
        let dims = aspect.dimensions(forHeight: height)

        #expect(dims.width == expectedWidth)
        #expect(dims.height == expectedHeight)
    }
}
