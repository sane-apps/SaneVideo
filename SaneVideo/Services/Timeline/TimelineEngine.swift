@preconcurrency import AVFoundation
import CoreImage
import Foundation
import Metal

/// A service responsible for composing multiple VideoClips into a single playable asset.
/// Inspired by the "Cabbage" library concept of a timeline composition.
@MainActor
class TimelineEngine {

    // Default transition duration (reserved for future use)
    private let transitionDuration = CMTime(seconds: 0.5, preferredTimescale: 600)

    /// Composes a project's timeline into a single AVPlayerItem with transitions and overlays.
    func composePlayerItem(for project: VideoProject) async throws -> AVPlayerItem {
        let hasClips = project.timeline.tracks.contains { !$0.clips.isEmpty }

        guard hasClips else {
            AppLogger.playback.warning("Cannot compose empty timeline")
            throw AppError.compositionFailed(NSError(domain: "TimelineEngine", code: -2, userInfo: [NSLocalizedDescriptionKey: "Timeline has no clips"]))
        }

        let totalClips = project.timeline.tracks.reduce(0) { $0 + $1.clips.count }
        AppLogger.playback.debug("Composing timeline with \(totalClips) clips across \(project.timeline.tracks.count) tracks")

        let result = try await CompositionBuilder.build(from: project)

        let playerItem = AVPlayerItem(asset: result.composition)
        if let vc = result.videoComposition {
            playerItem.videoComposition = vc
        }
        playerItem.audioMix = result.audioMix

        let audioMix = result.audioMix
        let paramCount = audioMix.inputParameters.count
        NSLog("🔍 TimelineEngine: audioMix has \(paramCount) input parameter(s)")
        AppLogger.playback.info("🔍 TimelineEngine: audioMix has \(paramCount) input parameter(s)")
        if paramCount == 0 {
            NSLog("⚠️ TimelineEngine: audioMix has NO input parameters - audio will be silent!")
            AppLogger.playback.warning("⚠️ TimelineEngine: audioMix has NO input parameters - audio will be silent!")
        }

        let audioTracks = result.composition.tracks(withMediaType: .audio)
        let videoTracks = result.composition.tracks(withMediaType: .video)

        // Use NSLog for visibility (AppLogger may be filtered)
        NSLog("🔍 TimelineEngine DIAGNOSTIC: Composition has \(videoTracks.count) video track(s), \(audioTracks.count) audio track(s)")
        AppLogger.playback.info("🔍 TimelineEngine DIAGNOSTIC: Composition has \(videoTracks.count) video track(s), \(audioTracks.count) audio track(s)")

        if audioTracks.isEmpty {
            NSLog("⚠️ TimelineEngine: Composition has NO audio tracks - playback will be silent!")
            AppLogger.playback.warning("⚠️ TimelineEngine: Composition has NO audio tracks - playback will be silent!")

            for track in project.timeline.tracks {
                for clip in track.clips {
                    let asset = AVURLAsset(url: clip.url)
                    let assetAudioTracks = try? await asset.loadTracks(withMediaType: .audio)
                    let count = assetAudioTracks?.count ?? 0
                    NSLog("  Clip \(clip.url.lastPathComponent): \(count) audio track(s) in source file")
                    AppLogger.playback.warning("  Clip \(clip.url.lastPathComponent): \(count) audio track(s) in source file")
                }
            }
        } else {
            NSLog("✅ TimelineEngine: Composition has \(audioTracks.count) audio track(s)")
            AppLogger.playback.info("✅ TimelineEngine: Composition has \(audioTracks.count) audio track(s)")
            for (index, track) in audioTracks.enumerated() {
                let duration = track.timeRange.duration.seconds
                let enabled = track.isEnabled
                let segments = track.segments.count
                NSLog("  Audio track \(index): duration=\(duration)s, enabled=\(enabled), segments=\(segments)")
                AppLogger.playback.info("  Audio track \(index): duration=\(duration)s, enabled=\(enabled), segments=\(segments)")
            }
        }

        AppLogger.playback.debug("Created player item with multi-track composition")

        return playerItem
    }
}
