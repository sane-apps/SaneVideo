//
//  ProjectState+Timeline.swift
//  SaneVideo
//
//  Created by SaneVideo Refactor
//

import AVFoundation
import Foundation
import SwiftUI

extension ProjectState {

    // MARK: - Timeline Processing

    func recalculateStartTimes(in timeline: inout Timeline) {
        // Only close gaps if Magnetic Timeline is enabled
        @AppStorage("magneticTimeline") var magneticTimeline = true

        // Recalculate for ALL tracks
        for (trackIndex, track) in timeline.tracks.enumerated() {
            var mutableTrack = track

            // CRITICAL FIX: Sort clips by startTime before recalculating
            // This ensures correct order even if clips were added out of order
            mutableTrack.clips.sort { $0.startTime < $1.startTime }

            if magneticTimeline {
                // Close gaps: sequential clips with no spacing
                var cumulativeTime = CMTime.zero
                for clipIndex in 0 ..< mutableTrack.clips.count {
                    mutableTrack.clips[clipIndex].startTime = cumulativeTime
                    cumulativeTime = CMTimeAdd(cumulativeTime, mutableTrack.clips[clipIndex].effectiveDuration)
                }
            } else {
                // Preserve gaps: only recalculate if clips overlap
                // If clips don't overlap, keep their startTimes
                for clipIndex in 1 ..< mutableTrack.clips.count {
                    let prevClip = mutableTrack.clips[clipIndex - 1]
                    let prevEnd = CMTimeAdd(prevClip.startTime, prevClip.effectiveDuration)
                    let currentClip = mutableTrack.clips[clipIndex]

                    // If current clip starts before previous ends, fix overlap
                    if currentClip.startTime < prevEnd {
                        mutableTrack.clips[clipIndex].startTime = prevEnd
                    }
                    // Otherwise, preserve the gap
                }
            }
            timeline.tracks[trackIndex] = mutableTrack
        }

        // CRITICAL FIX: Update timeline duration after recalculating startTimes
        timeline.updateDuration()
    }

    /// CRITICAL FIX: Validate timeline state for consistency
    /// Checks for overlaps, invalid startTimes, duplicate IDs, etc.
    func validateTimelineState(_ timeline: Timeline) -> Bool {
        // Check for duplicate clip IDs
        var seenIDs = Set<UUID>()
        for track in timeline.tracks {
            for clip in track.clips {
                if seenIDs.contains(clip.id) {
                    AppLogger.project.error("Duplicate clip ID found: \(clip.id)")
                    return false
                }
                seenIDs.insert(clip.id)

                // Validate clip properties
                if clip.startTime.seconds < 0 {
                    AppLogger.project.error("Clip has negative startTime: \(clip.id)")
                    return false
                }

                if clip.effectiveDuration.seconds <= 0 {
                    AppLogger.project.error("Clip has zero or negative duration: \(clip.id)")
                    return false
                }

                // Check for overlaps within same track
                let sortedClips = track.clips.sorted { $0.startTime < $1.startTime }
                for i in 1 ..< sortedClips.count {
                    let prevClip = sortedClips[i - 1]
                    let currentClip = sortedClips[i]
                    let prevEnd = CMTimeAdd(prevClip.startTime, prevClip.effectiveDuration)

                    if currentClip.startTime < prevEnd {
                        AppLogger.project.error("Clips overlap in track: \(prevClip.id) and \(currentClip.id)")
                        return false
                    }
                }
            }
        }

        return true
    }
}
