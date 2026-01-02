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
        settings: SaneExportSettings
    ) async throws -> AVVideoComposition? {
        // We already have a video composition from CompositionBuilder,
        // but we need to ensure it matches export settings (frame rate, resolution).

        guard let base = baseVideoComposition else { return nil }

        // Get the custom compositor class, defaulting to SaneVideoCompositor
        let customClass = base.customVideoCompositorClass ?? SaneVideoCompositor.self
        if base.customVideoCompositorClass == nil {
            AppLogger.export.warning("⚠️ Base video composition had no customVideoCompositorClass. Forced SaneVideoCompositor.")
        }

        if #available(macOS 26.0, *) {
            // macOS 26+: Use modern Configuration API
            var config = AVVideoComposition.Configuration()
            config.instructions = base.instructions
            config.renderSize = settings.renderSize
            config.frameDuration = CMTime(value: 1, timescale: CMTimeScale(settings.frameRate))
            config.sourceTrackIDForFrameTiming = base.sourceTrackIDForFrameTiming
            config.animationTool = base.animationTool
            config.customVideoCompositorClass = customClass
            return AVVideoComposition(configuration: config)
        } else {
            // macOS 15-25: Use mutable video composition
            let mutableVideoComposition = AVMutableVideoComposition()
            mutableVideoComposition.instructions = base.instructions
            mutableVideoComposition.renderSize = settings.renderSize
            mutableVideoComposition.frameDuration = CMTime(value: 1, timescale: CMTimeScale(settings.frameRate))
            mutableVideoComposition.sourceTrackIDForFrameTiming = base.sourceTrackIDForFrameTiming
            mutableVideoComposition.animationTool = base.animationTool
            mutableVideoComposition.customVideoCompositorClass = customClass
            return mutableVideoComposition
        }
    }
}
