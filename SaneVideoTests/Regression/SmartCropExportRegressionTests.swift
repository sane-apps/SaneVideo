// Smart crop export: a disabled crop analysis returns the centered default without
// analyzing frames, and injecting crop keyframes keeps the instruction's
// click/keystroke overlay layers.

import AVFoundation
import CoreMedia
import Foundation
@testable import SaneVideo
import Testing

@Suite("Smart Crop Export Regression Tests")
struct SmartCropExportRegressionTests {
    @Test("Disabled smart crop returns the centered default crop and no keyframes")
    func disabledSmartCropReturnsDefault() async throws {
        let assetURL = TestEnvironment.mockAssetURL
        try #require(FileManager.default.fileExists(atPath: assetURL.path), "Missing fixture \(assetURL.path)")
        var settings = SmartCropSettings()
        settings.enabled = false

        let result = try await SmartCropService().analyzeVideo(sourceURL: assetURL, settings: settings)

        let assetDuration = try await AVURLAsset(url: assetURL).load(.duration)
        #expect(result.keyframes.isEmpty)
        #expect(result.defaultCrop == .default)
        #expect(abs(result.duration.seconds - assetDuration.seconds) < 0.01)
    }

    @Test("Injecting smart crop keyframes keeps interaction overlay layers")
    @MainActor
    func injectSmartCropPreservesInteractionLayers() async throws {
        let interactionLayer = InteractionLayerItem(
            clipID: UUID(),
            timeRange: CMTimeRange(start: .zero, duration: CMTime(seconds: 2, preferredTimescale: 600)),
            clicks: [InteractionClickItem(time: .zero, x: 0.4, y: 0.3, button: 0)],
            cursorPath: [InteractionCursorItem(time: .zero, x: 0.4, y: 0.3, isDown: false)],
            keystrokes: [InteractionKeystrokeItem(id: UUID(), time: .zero, text: "Command + K")],
            style: InteractionOverlayStyle()
        )

        let baseInstruction = SaneVideoCompositionInstruction(
            timeRange: CMTimeRange(start: .zero, duration: CMTime(seconds: 2, preferredTimescale: 600)),
            layerInstructions: [],
            interactionLayers: [interactionLayer]
        )

        let baseVideoComposition = AVMutableVideoComposition()
        baseVideoComposition.instructions = [baseInstruction]

        let keyframes: [CMTime: SuggestedCrop] = [
            .zero: SuggestedCrop(centerX: 0.5, centerY: 0.5, scale: 1.0)
        ]

        let updatedVideoComposition = try await ExportCompositor().createVideoComposition(
            for: AVMutableComposition(),
            baseVideoComposition: baseVideoComposition,
            settings: SaneExportSettings(),
            smartCropKeyframes: keyframes
        )

        let updatedInstruction = try #require(
            updatedVideoComposition?.instructions.first as? SaneVideoCompositionInstruction
        )
        #expect(updatedInstruction.smartCropKeyframes?.count == 1)
        #expect(updatedInstruction.interactionLayers.count == 1)
        #expect(updatedInstruction.interactionLayers.first?.keystrokes.first?.text == "Command + K")
    }
}
