//
//  TimelineEngine.swift
//  SaneVideo
//
//  Created by SaneVideo Refactor
//

import AVFoundation
import CoreImage
import Foundation
import Metal

/// A service responsible for composing multiple VideoClips into a single playable asset.
/// Inspired by the "Cabbage" library concept of a timeline composition.
class TimelineEngine {

    // Default transition duration (reserved for future use)
    private let transitionDuration = CMTime(seconds: 0.5, preferredTimescale: 600)

    /// Composes a project's timeline into a single AVPlayerItem with transitions and overlays.
    /// - Parameter project: The project containing the timeline to compose.
    /// - Returns: An AVPlayerItem ready for playback.
    @MainActor
    func composePlayerItem(for project: VideoProject) async throws -> AVPlayerItem {
        // Guard: Empty timeline (no tracks or no clips in tracks)
        let hasClips = project.timeline.tracks.contains { !$0.clips.isEmpty }

        guard hasClips else {
            AppLogger.playback.warning("Cannot compose empty timeline")
            throw AppError.compositionFailed(NSError(domain: "TimelineEngine", code: -2, userInfo: [NSLocalizedDescriptionKey: "Timeline has no clips"]))
        }

        let totalClips = project.timeline.tracks.reduce(0) { $0 + $1.clips.count }
        AppLogger.playback.debug("Composing timeline with \(totalClips) clips across \(project.timeline.tracks.count) tracks")

        // 1. Build Composition (New Shared Builder)
        // CompositionBuilder now handles all track layering and transforms
        let result = try await CompositionBuilder.build(from: project)

        let playerItem = AVPlayerItem(asset: result.composition)
        if let vc = result.videoComposition {
            playerItem.videoComposition = vc
        }
        playerItem.audioMix = result.audioMix

        AppLogger.playback.debug("Created player item with multi-track composition")

        return playerItem
    }
}
