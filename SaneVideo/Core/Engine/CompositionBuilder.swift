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
        let videoComposition: AVVideoComposition?
        let audioMix: AVAudioMix
    }

    /// Builds a composition and returns it along with the video composition and audio mix for playback
    /// - Parameters:
    ///   - project: The video project to build composition from
    ///   - renderSize: Target render size for transforms. Defaults to 1080p for playback. Export should pass actual export resolution.
    @MainActor
    static func build(from project: VideoProject, renderSize: CGSize = CGSize(width: 1920, height: 1080)) async throws -> CompositionResult {
        let timeline = project.timeline

        // CRITICAL: Early validation for empty timeline to prevent Signal 10 crash
        // AVAssetReaderVideoCompositionOutput crashes with "[videoTracks count] >= 1" assertion
        // We must check if there are any enabled video tracks with content
        let hasVideoContent = timeline.tracks.contains { track in
            (track.type == .video || track.type == .overlay) && !track.clips.isEmpty
        }

        guard hasVideoContent else {
            // CRITICAL FIX: Throw specific error rather than letting it crash later
            throw AppError.compositionFailed(NSError(
                domain: "CompositionBuilder",
                code: -1,
                userInfo: [NSLocalizedDescriptionKey: "Cannot build composition: Project has no video content. Please add video clips to the timeline."]
            ))
        }

        let composition = AVMutableComposition()

        // CRITICAL FIX: Validate all source files exist before composition
        var missingFiles: [String] = []
        for track in timeline.tracks {
            for clip in track.clips {
                // Check if file exists and is accessible
                if !FileManager.default.fileExists(atPath: clip.url.path) {
                    missingFiles.append(clip.url.lastPathComponent)
                    AppLogger.export.error("❌ Source file missing: \(clip.url.lastPathComponent)")
                } else {
                    // Try to access file to ensure it's readable
                    let isAccessing = clip.url.startAccessingSecurityScopedResource()
                    defer {
                        if isAccessing {
                            clip.url.stopAccessingSecurityScopedResource()
                        }
                    }

                    // Check if file is readable
                    if !FileManager.default.isReadableFile(atPath: clip.url.path) {
                        missingFiles.append(clip.url.lastPathComponent)
                        AppLogger.export.error("❌ Source file not readable: \(clip.url.lastPathComponent)")
                    }
                }
            }
        }

        if !missingFiles.isEmpty {
            let fileList = missingFiles.prefix(3).joined(separator: ", ")
            let moreCount = missingFiles.count > 3 ? " and \(missingFiles.count - 3) more" : ""
            throw AppError.compositionFailed(NSError(
                domain: "CompositionBuilder",
                code: -1,
                userInfo: [NSLocalizedDescriptionKey: "Cannot export: Missing or inaccessible source files: \(fileList)\(moreCount). Please check that all video files are available."]
            ))
        }

        // MEMORY OPTIMIZATION: Cache assets to avoid loading the same video multiple times
        var assetCache: [URL: AVURLAsset] = [:]

        // renderSize is now a parameter - transforms will be computed for the target resolution

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

        // 4c. Apply audio limiter to prevent clipping when tracks are mixed
        // This uses MTAudioProcessingTap to apply soft-knee limiting
        // FIX (2025-12-31): BYPASS limiter for now - MTAudioProcessingTap may cause silent audio
        // The tap may not be compatible with AVPlayer playback (works for export only)
        // TODO: Investigate if limiter should only be applied during export, not playback
        let limitedAudioMix = audioMix  // AudioLimiter.applyLimiter(to: audioMix)
        AppLogger.timeline.info("🔊 CompositionBuilder: Using audioMix WITHOUT limiter (limiter bypassed for debugging)")

        // 5. Build Video Composition
        let totalDuration = timeline.duration
        var videoComposition: AVVideoComposition?

        if totalDuration > .zero, !videoResult.compositionVideoTracks.isEmpty {

            // CRITICAL CHECK: Ensure we have actual video content
            // Creating a video composition with empty tracks can cause Signal 10
            guard !videoResult.compositionVideoTracks.isEmpty else {
                 AppLogger.export.warning("⚠️ No video tracks in composition - skipping video composition generation")
                 return CompositionResult(
                     composition: composition,
                     videoComposition: nil,
                     audioMix: limitedAudioMix
                 )
            }

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
                visionService: ServiceContainer.shared.personSegmentationService
            )

            if #available(macOS 26.0, *) {
                // macOS 26+: Use modern Configuration API
                var config = AVVideoComposition.Configuration()
                config.renderSize = renderSize
                config.frameDuration = CMTime(value: 1, timescale: 30)
                config.customVideoCompositorClass = SaneVideoCompositor.self
                config.instructions = [saneInstruction]
                videoComposition = AVVideoComposition(configuration: config)
            } else {
                // macOS 15-25: Use mutable video composition
                let mutableVideoComposition = AVMutableVideoComposition()
                mutableVideoComposition.renderSize = renderSize
                mutableVideoComposition.frameDuration = CMTime(value: 1, timescale: 30)
                mutableVideoComposition.customVideoCompositorClass = SaneVideoCompositor.self
                mutableVideoComposition.instructions = [saneInstruction]
                videoComposition = mutableVideoComposition
            }
        }

        return CompositionResult(
            composition: composition,
            videoComposition: videoComposition,
            audioMix: limitedAudioMix
        )
    }
}
