//
//  CompositionBuilder.swift
//  SaneVideo
//
//  Created by SaneVideo Refactor
//

import AVFoundation
import CoreMedia

/// A helper struct to build AVMutableComposition from a Timeline.
/// Centralizes logic for non-destructive cuts (removedRanges) and track arrangement.
enum CompositionBuilder {

    struct CompositionResult {
        let composition: AVMutableComposition
        let videoComposition: AVVideoComposition
        let audioMix: AVAudioMix
    }

    /// Builds a composition and returns it along with the video composition and audio mix for playback
    @MainActor
    static func build(from project: VideoProject) async throws -> CompositionResult {
        let timeline = project.timeline
        let composition = AVMutableComposition()

        // MEMORY OPTIMIZATION: Cache assets to avoid loading the same video multiple times
        var assetCache: [URL: AVURLAsset] = [:]

        let renderSize = CGSize(width: 1920, height: 1080)
        
        // 1. Sort tracks by z-index
        let sortedTracks = timeline.tracks.sorted { $0.zIndex > $1.zIndex } // Top z-index first
        let visualTimelineTracks = sortedTracks.filter { $0.type == .video || $0.type == .overlay }
        let audioTimelineTracks = sortedTracks.filter { $0.type == .audio }

        // 2. Build Video Tracks using VideoTrackBuilder
        let videoResult = try await VideoTrackBuilder.build(
            from: visualTimelineTracks,
            into: composition,
            assetCache: &assetCache,
            renderSize: renderSize
        )

        // 3. Build Text Layers (Captions & Overlays) using TextLayerBuilder
        let textLayers = TextLayerBuilder.build(from: visualTimelineTracks, project: project)

        // 4. Build Audio Tracks using AudioTrackBuilder
        var audioMixParams: [AVMutableAudioMixInputParameters] = []
        
        // 4a. Visual tracks audio (A/B roll)
        let visualAudioParams = try await AudioTrackBuilder.buildVisualAudio(
            from: visualTimelineTracks,
            into: composition,
            assetCache: &assetCache
        )
        audioMixParams.append(contentsOf: visualAudioParams)
        
        // 4b. Dedicated audio tracks
        let dedicatedAudioParams = try await AudioTrackBuilder.buildDedicatedAudio(
            from: audioTimelineTracks,
            into: composition,
            assetCache: &assetCache
        )
        audioMixParams.append(contentsOf: dedicatedAudioParams)

        let audioMix = AVMutableAudioMix()
        audioMix.inputParameters = audioMixParams

        // 5. Build Video Composition
        var config = AVVideoComposition.Configuration()
        config.renderSize = renderSize
        config.frameDuration = CMTime(value: 1, timescale: 30)
        config.customVideoCompositorClass = SaneVideoCompositor.self

        let totalDuration = timeline.duration

        if totalDuration > .zero, !videoResult.compositionVideoTracks.isEmpty {
            let timeRange = CMTimeRange(start: .zero, duration: totalDuration)

            // Create SaneVideoCompositionInstruction
            let saneInstruction = SaneVideoCompositionInstruction(
                timeRange: timeRange,
                layerInstructions: videoResult.layerInstructions,
                trackEffects: videoResult.trackEffects,
                trackKeyframes: videoResult.trackKeyframes,
                trackBackgroundEffects: videoResult.trackBackgroundEffects,
                trackPrivacyRegions: videoResult.trackPrivacyRegions,
                activeTransitions: videoResult.activeTransitions,
                textLayers: textLayers,
                trackCursorData: videoResult.trackCursorData,
                visionService: ServiceContainer.shared.personSegmentationService
            )

            config.instructions = [saneInstruction]
        }

        let videoComposition = AVVideoComposition(configuration: config)

        return CompositionResult(
            composition: composition,
            videoComposition: videoComposition,
            audioMix: audioMix
        )
    }
}
