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
    func createComposition(from project: VideoProject) async throws -> CompositionBuilder.CompositionResult {
        return try await CompositionBuilder.build(from: project)
    }

    func createVideoComposition(
        for _: AVComposition,
        baseVideoComposition: AVVideoComposition,
        settings: SaneExportSettings
    ) async throws -> AVVideoComposition {
        // We already have a video composition from CompositionBuilder,
        // but we need to ensure it matches export settings (frame rate, resolution).

        // Create a configuration from the base composition properties
        var config = AVVideoComposition.Configuration()
        
        // Configuration in macOS 26.2 is properly initialized from properties
        config.instructions = baseVideoComposition.instructions
        config.renderSize = settings.resolution.size
        config.frameDuration = CMTime(value: 1, timescale: CMTimeScale(settings.frameRate))
        config.sourceTrackIDForFrameTiming = baseVideoComposition.sourceTrackIDForFrameTiming
        config.animationTool = baseVideoComposition.animationTool

        return AVVideoComposition(configuration: config)
    }
}
