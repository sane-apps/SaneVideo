//
//  ProjectState+ClipEditing.swift
//  SaneVideo
//
//  Created by SaneVideo Refactor
//

import CoreMedia
import Foundation
import SwiftUI

extension ProjectState {
    
    // MARK: - Splitting

    func splitClip(_ clip: VideoClip, atTimelineTime globalTime: CMTime) {
        guard var project = currentProject else { return }

        // 0. Concurrency Check
        guard !isProcessing else {
            AppLogger.project.warning("Ignored splitClip request (Processing busy)")
            return
        }

        // Phase 2: Check if track is locked
        if isTrackLocked(for: clip) {
            ServiceContainer.shared.toastManager.show("Track is locked", type: .error)
            return
        }

        // 1. Calculate Asset Time
        // Global Time -> Local Offset -> Asset Time
        // Asset Time = (Global - Start) + TrimStart

        // Ensure time is within clip's timeline range
        guard globalTime > clip.startTime, globalTime < (clip.startTime + clip.effectiveDuration) else {
            AppLogger.project.warning("Split time \(globalTime.seconds)s is outside clip range")
            return
        }

        let localOffset = CMTimeSubtract(globalTime, clip.startTime)
        let splitAssetTime = CMTimeAdd(clip.trimStart, localOffset)

        // 2. Validate Asset Time bounds
        // Must be between TrimStart and TrimEnd (implicitly handled by global checking above, but good specific check)
        guard splitAssetTime > clip.trimStart, splitAssetTime < clip.trimEnd else {
            AppLogger.project.warning("Calculated split time \(splitAssetTime.seconds)s invalid for clip bounds")
            return
        }

        // 3. Create two new clips
        var firstPart = clip
        firstPart.trimEnd = splitAssetTime

        var secondPart = clip
        // Re-generate ID
        secondPart = VideoClip(
            url: clip.url,
            duration: clip.duration
        )
        // Helper copy stats if VideoClip doesn't have clone init
        secondPart.volume = clip.volume
        secondPart.speed = clip.speed
        secondPart.isMuted = clip.isMuted
        secondPart.rotation = clip.rotation
        secondPart.captions = clip.captions
        secondPart.transform = clip.transform // Phase 3: Copy transform
        // Should we copy effects? Yes.
        secondPart.effects = clip.effects

        secondPart.trimStart = splitAssetTime
        secondPart.trimEnd = clip.trimEnd

        // 4. Update track
        var timeline = project.timeline

        var splitDone = false
        for (trackIndex, track) in timeline.tracks.enumerated() {
            if let index = track.clips.firstIndex(where: { $0.id == clip.id }) {
                // CRITICAL FIX: Register undo right before mutation
                registerUndo("Split Clip")

                var mutableTrack = track
                mutableTrack.clips[index] = firstPart
                mutableTrack.clips.insert(secondPart, at: index + 1)
                timeline.tracks[trackIndex] = mutableTrack

                splitDone = true
                break
            }
        }

        if splitDone {
            recalculateStartTimes(in: &timeline)

            project.timeline = timeline
            currentProject = project
            saveProject(project)
            AppLogger.project.info("Split clip \(clip.id) at timeline \(globalTime.seconds)s (Asset: \(splitAssetTime.seconds)s)")
            ServiceContainer.shared.toastManager.show("Split Clip")
        }
    }

    // MARK: - Trimming

    func updateClipTrim(clipId: UUID, trimStart: CMTime?, trimEnd: CMTime?, startTime _: CMTime? = nil) {
        guard !isProcessing else { return }
        guard var project = currentProject else { return }

        var timeline = project.timeline
        var clipFound = false

        for (trackIndex, track) in timeline.tracks.enumerated() {
            if let index = track.clips.firstIndex(where: { $0.id == clipId }) {
                var clip = track.clips[index]

                // Update trim values
                // Update trim values safely
                let newStart = trimStart ?? clip.trimStart
                let newEnd = trimEnd ?? clip.trimEnd
                clip.setTrimRange(start: newStart, end: newEnd)

                registerUndo("Trim Clip")

                var mutableTrack = track
                mutableTrack.clips[index] = clip
                timeline.tracks[trackIndex] = mutableTrack
                clipFound = true
                break
            }
        }

        if clipFound {
            recalculateStartTimes(in: &timeline)
            project.timeline = timeline
            currentProject = project
            saveProject(project)
            AppLogger.project.info("Updated trim for clip \(clipId)")
            ServiceContainer.shared.toastManager.show("Trimmed Clip")
        }
    }

    // MARK: - Rotation

    func rotateClip(_ clip: VideoClip) {
        guard !isProcessing else { return }
        guard var project = currentProject else { return }

        var timeline = project.timeline
        var clipFound = false
        var newRotationName = ""

        for (trackIndex, track) in timeline.tracks.enumerated() {
            if let index = track.clips.firstIndex(where: { $0.id == clip.id }) {
                registerUndo("Rotate Clip")

                var mutableTrack = track
                var mutableClip = track.clips[index]
                mutableClip.rotateClockwise()
                newRotationName = mutableClip.rotation.displayName

                mutableTrack.clips[index] = mutableClip
                timeline.tracks[trackIndex] = mutableTrack
                clipFound = true
                break
            }
        }

        if clipFound {
            project.timeline = timeline
            currentProject = project
            saveProject(project)

            AppLogger.project.info("Rotated clip \(clip.id) to \(newRotationName)")
            ServiceContainer.shared.toastManager.show("Rotated \(newRotationName)")
        }
    }
}
