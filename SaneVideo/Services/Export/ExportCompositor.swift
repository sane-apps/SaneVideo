//
//  ExportCompositor.swift
//  SaneVideo
//
//  Created by SaneVideo Refactor
//  Optimized for Apple Silicon M1+ with Metal-backed rendering

import AVFoundation
import CoreImage
import CoreMedia
import Metal

@MainActor
class ExportCompositor {
    /// Creates composition with transforms computed for the target export resolution
    /// This ensures 4K exports have correctly scaled transforms, not 1080p-baked transforms
    func createComposition(from project: VideoProject, settings: SaneExportSettings) async throws -> CompositionBuilder.CompositionResult {
        return try await CompositionBuilder.build(from: project, renderSize: settings.renderSize)
    }

    func createVideoComposition(
        for _: AVComposition,
        baseVideoComposition: AVVideoComposition?,
        settings: SaneExportSettings,
        smartCropKeyframes: [CMTime: SuggestedCrop]? = nil
    ) async throws -> AVVideoComposition? {
        // We already have a video composition from CompositionBuilder,
        // but we need to ensure it matches export settings (frame rate, resolution).

        guard let base = baseVideoComposition else { return nil }

        // Get the custom compositor class, defaulting to SaneVideoCompositor
        let customClass = base.customVideoCompositorClass ?? SaneVideoCompositor.self
        if base.customVideoCompositorClass == nil {
            AppLogger.export.warning("⚠️ Base video composition had no customVideoCompositorClass. Forced SaneVideoCompositor.")
        }

        // Inject smart crop keyframes into instructions if provided
        let instructions: [AVVideoCompositionInstructionProtocol]
        if let keyframes = smartCropKeyframes, !keyframes.isEmpty {
            instructions = injectSmartCropKeyframes(keyframes, into: base.instructions)
        } else {
            instructions = base.instructions
        }

        if #available(macOS 26.0, *) {
#if compiler(>=6.2)
            // Newer compilers expose the AVVideoComposition configuration API directly.
            var config = AVVideoComposition.Configuration()
            config.instructions = instructions
            config.renderSize = settings.renderSize
            config.frameDuration = CMTime(value: 1, timescale: CMTimeScale(settings.frameRate))
            config.sourceTrackIDForFrameTiming = base.sourceTrackIDForFrameTiming
            config.animationTool = base.animationTool
            config.customVideoCompositorClass = customClass
            return AVVideoComposition(configuration: config)
#else
            return makeMutableVideoComposition(
                instructions: instructions,
                renderSize: settings.renderSize,
                frameRate: settings.frameRate,
                sourceTrackIDForFrameTiming: base.sourceTrackIDForFrameTiming,
                animationTool: base.animationTool,
                customVideoCompositorClass: customClass
            )
#endif
        } else {
            return makeMutableVideoComposition(
                instructions: instructions,
                renderSize: settings.renderSize,
                frameRate: settings.frameRate,
                sourceTrackIDForFrameTiming: base.sourceTrackIDForFrameTiming,
                animationTool: base.animationTool,
                customVideoCompositorClass: customClass
            )
        }
    }

    /// Injects smart crop keyframes into existing instructions
    private func injectSmartCropKeyframes(
        _ keyframes: [CMTime: SuggestedCrop],
        into instructions: [AVVideoCompositionInstructionProtocol]
    ) -> [AVVideoCompositionInstructionProtocol] {
        return instructions.map { instruction in
            guard let saneInstruction = instruction as? SaneVideoCompositionInstruction else {
                return instruction
            }

            // Create a new instruction with the keyframes added
            return SaneVideoCompositionInstruction(
                timeRange: saneInstruction.timeRange,
                layerInstructions: saneInstruction.layerInstructions,
                trackEffects: saneInstruction.trackEffects,
                trackKeyframes: saneInstruction.trackKeyframes,
                trackBackgroundEffects: saneInstruction.trackBackgroundEffects,
                trackPrivacyRegions: saneInstruction.trackPrivacyRegions,
                activeTransitions: saneInstruction.activeTransitions,
                textLayers: saneInstruction.textLayers,
                interactionLayers: saneInstruction.interactionLayers,
                visionService: saneInstruction.visionService,
                smartCropKeyframes: keyframes
            )
        }
    }

    private func makeMutableVideoComposition(
        instructions: [AVVideoCompositionInstructionProtocol],
        renderSize: CGSize,
        frameRate: Double,
        sourceTrackIDForFrameTiming: CMPersistentTrackID,
        animationTool: AVVideoCompositionCoreAnimationTool?,
        customVideoCompositorClass: AVVideoCompositing.Type
    ) -> AVMutableVideoComposition {
        let mutableVideoComposition = AVMutableVideoComposition()
        mutableVideoComposition.instructions = instructions
        mutableVideoComposition.renderSize = renderSize
        mutableVideoComposition.frameDuration = CMTime(value: 1, timescale: CMTimeScale(frameRate))
        mutableVideoComposition.sourceTrackIDForFrameTiming = sourceTrackIDForFrameTiming
        mutableVideoComposition.animationTool = animationTool
        mutableVideoComposition.customVideoCompositorClass = customVideoCompositorClass
        return mutableVideoComposition
    }
}
