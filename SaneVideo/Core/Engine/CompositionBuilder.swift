import AVFoundation
import CoreMedia

/// Centralizes logic for non-destructive cuts (removedRanges) and track arrangement.
enum CompositionBuilder {

    struct CompositionResult {
        let composition: AVMutableComposition
        let videoComposition: AVVideoComposition?
        let audioMix: AVAudioMix
    }

    /// Builds a composition and returns it along with the video composition and audio mix for playback
    /// - Parameters:
    ///   - renderSize: Target render size for transforms. Defaults to 1080p for playback. Export should pass actual export resolution.
    @MainActor
    static func build(from project: VideoProject, renderSize: CGSize = CGSize(width: 1920, height: 1080)) async throws -> CompositionResult {
        let timeline = project.timeline

        // AVAssetReaderVideoCompositionOutput asserts "[videoTracks count] >= 1" (Signal 10) on a timeline with no video, so check first.
        let hasVideoContent = timeline.tracks.contains { track in
            (track.type == .video || track.type == .overlay) && !track.clips.isEmpty
        }

        guard hasVideoContent else {
            throw AppError.compositionFailed(NSError(
                domain: "CompositionBuilder",
                code: -1,
                userInfo: [NSLocalizedDescriptionKey: "Cannot build composition: Project has no video content. Please add video clips to the timeline."]
            ))
        }

        let composition = AVMutableComposition()

        var missingFiles: [String] = []
        for track in timeline.tracks {
            for clip in track.clips {
                if !FileManager.default.fileExists(atPath: clip.url.path) {
                    missingFiles.append(clip.url.lastPathComponent)
                    AppLogger.export.error("❌ Source file missing: \(clip.url.lastPathComponent)")
                } else {
                    let isAccessing = clip.url.startAccessingSecurityScopedResource()
                    defer {
                        if isAccessing {
                            clip.url.stopAccessingSecurityScopedResource()
                        }
                    }

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

        // Cache assets so a video used by several clips loads once.
        var assetCache: [URL: AVURLAsset] = [:]

        let sortedTracks = timeline.tracks.sorted { $0.zIndex > $1.zIndex } // Top z-index first
        let visualTimelineTracks = sortedTracks.filter { $0.type == .video || $0.type == .overlay }
        let audioTimelineTracks = sortedTracks.filter { $0.type == .audio }

        let videoResult = try await VideoTrackBuilder.build(
            from: visualTimelineTracks,
            into: composition,
            assetCache: &assetCache,
            renderSize: renderSize
        )

        let textLayers = TextLayerBuilder.build(from: visualTimelineTracks, project: project)
        let interactionLayers = TextLayerBuilder.buildInteractionLayers(from: visualTimelineTracks)

        var audioMixParams: [AVMutableAudioMixInputParameters] = []

        let visualAudioParams = try await AudioTrackBuilder.buildVisualAudio(
            from: visualTimelineTracks,
            into: composition,
            assetCache: &assetCache
        )
        audioMixParams.append(contentsOf: visualAudioParams)

        let dedicatedAudioParams = try await AudioTrackBuilder.buildDedicatedAudio(
            from: audioTimelineTracks,
            into: composition,
            assetCache: &assetCache
        )
        audioMixParams.append(contentsOf: dedicatedAudioParams)

        let audioMix = AVMutableAudioMix()
        audioMix.inputParameters = audioMixParams

        // The audio limiter (MTAudioProcessingTap) is bypassed: it may silence AVPlayer playback, though it works for export.
        let limitedAudioMix = audioMix
        AppLogger.timeline.info("🔊 CompositionBuilder: Using audioMix WITHOUT limiter (limiter bypassed for debugging)")

        // Catches A/V drift bugs early.
        validateClipTimingInvariants(in: timeline)

        let totalDuration = timeline.duration
        var videoComposition: AVVideoComposition?

        if totalDuration > .zero, !videoResult.compositionVideoTracks.isEmpty {

            // A video composition with empty tracks can crash with Signal 10.
            guard !videoResult.compositionVideoTracks.isEmpty else {
                 AppLogger.export.warning("⚠️ No video tracks in composition - skipping video composition generation")
                 return CompositionResult(
                     composition: composition,
                     videoComposition: nil,
                     audioMix: limitedAudioMix
                 )
            }

            let timeRange = CMTimeRange(start: .zero, duration: totalDuration)

            let saneInstruction = SaneVideoCompositionInstruction(
                timeRange: timeRange,
                layerInstructions: videoResult.layerInstructions,
                trackEffects: videoResult.trackEffects,
                trackKeyframes: videoResult.trackKeyframes,
                trackBackgroundEffects: videoResult.trackBackgroundEffects,
                trackPrivacyRegions: videoResult.trackPrivacyRegions,
                activeTransitions: videoResult.activeTransitions,
                textLayers: textLayers,
                interactionLayers: interactionLayers,
                visionService: ServiceContainer.shared.personSegmentationService
            )

            if #available(macOS 26.0, *) {
#if compiler(>=6.2)
                // Newer compilers expose the AVVideoComposition configuration API directly.
                var config = AVVideoComposition.Configuration()
                config.renderSize = renderSize
                config.frameDuration = CMTime(value: 1, timescale: 30)
                config.customVideoCompositorClass = SaneVideoCompositor.self
                config.instructions = [saneInstruction]
                videoComposition = AVVideoComposition(configuration: config)
#else
                videoComposition = makeMutableVideoComposition(
                    renderSize: renderSize,
                    frameDuration: CMTime(value: 1, timescale: 30),
                    customVideoCompositorClass: SaneVideoCompositor.self,
                    instructions: [saneInstruction]
                )
#endif
            } else {
                videoComposition = makeMutableVideoComposition(
                    renderSize: renderSize,
                    frameDuration: CMTime(value: 1, timescale: 30),
                    customVideoCompositorClass: SaneVideoCompositor.self,
                    instructions: [saneInstruction]
                )
            }
        }

        return CompositionResult(
            composition: composition,
            videoComposition: videoComposition,
            audioMix: limitedAudioMix
        )
    }

    private static func validateClipTimingInvariants(in timeline: Timeline) {
        // Keep this lightweight: no asset I/O; rely on clip.duration + trim info.
        let tolerance = CMTime(seconds: 0.02, preferredTimescale: 600)

        for track in timeline.tracks {
            for clip in track.clips {
                guard clip.speed > 0 else {
                    AppLogger.timeline.warning("⚠️ Timing invariant: clip has invalid speed (\(clip.speed)) \(clip.url.lastPathComponent)")
                    continue
                }

                let sourceDuration = CMTimeSubtract(min(clip.trimEnd, clip.duration), clip.trimStart)
                guard sourceDuration > .zero else { continue }

                let segments = VideoTrackBuilder.computeValidSegments(clip: clip, sourceDuration: sourceDuration)
                let totalSource = segments.reduce(CMTime.zero) { CMTimeAdd($0, $1.duration) }
                let expectedPlayed = CMTimeMultiplyByFloat64(totalSource, multiplier: 1.0 / clip.speed)

                if abs(expectedPlayed.seconds - clip.effectiveDuration.seconds) > tolerance.seconds {
                    AppLogger.timeline.warning(
                        "⚠️ Timing invariant mismatch for \(clip.url.lastPathComponent): " +
                            "expectedPlayed=\(expectedPlayed.seconds)s effective=\(clip.effectiveDuration.seconds)s " +
                            "speed=\(clip.speed) removals=\(clip.removedRanges.count)"
                    )
                }
            }
        }
    }

    private static func makeMutableVideoComposition(
        renderSize: CGSize,
        frameDuration: CMTime,
        customVideoCompositorClass: AVVideoCompositing.Type,
        instructions: [AVVideoCompositionInstructionProtocol]
    ) -> AVMutableVideoComposition {
        let mutableVideoComposition = AVMutableVideoComposition()
        mutableVideoComposition.renderSize = renderSize
        mutableVideoComposition.frameDuration = frameDuration
        mutableVideoComposition.customVideoCompositorClass = customVideoCompositorClass
        mutableVideoComposition.instructions = instructions
        return mutableVideoComposition
    }
}
