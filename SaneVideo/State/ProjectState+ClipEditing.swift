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

        // CRITICAL FIX: Prevent concurrent timeline operations
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

        // 3. Create two new clips using copy method to ensure all properties are preserved
        var firstPart = clip
        firstPart.trimEnd = splitAssetTime

        // Use copy method to ensure all properties are preserved (removedRanges, overlays, etc.)
        var secondPart = clip.copy(trimStart: splitAssetTime, trimEnd: clip.trimEnd)
        
        // CRITICAL FIX: Set secondPart.startTime to prevent overlap
        // Second part should start where first part ends
        let firstPartEffectiveDuration = firstPart.effectiveDuration
        secondPart.startTime = CMTimeAdd(clip.startTime, firstPartEffectiveDuration)

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
            // CRITICAL FIX: Recalculate startTimes to ensure consistency
            // This handles edge cases and ensures no gaps/overlaps
            recalculateStartTimes(in: &timeline)
            
            // CRITICAL FIX: Validate timeline state after split
            if !validateTimelineState(timeline) {
                AppLogger.project.error("Timeline state invalid after split, rolling back")
                ServiceContainer.shared.toastManager.show("Split failed: Timeline state invalid", type: .error)
                return
            }

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

                // Update trim values with validation
                let newStart = trimStart ?? clip.trimStart
                let newEnd = trimEnd ?? clip.trimEnd
                
                // Validate trim range before applying
                guard newStart < newEnd else {
                    AppLogger.project.warning("Invalid trim: start (\(newStart.seconds)s) >= end (\(newEnd.seconds)s)")
                    ServiceContainer.shared.toastManager.show("Invalid trim range", type: .error)
                    return
                }
                
                guard newStart >= .zero, newEnd <= clip.duration else {
                    AppLogger.project.warning("Trim range outside clip duration (duration: \(clip.duration.seconds)s)")
                    ServiceContainer.shared.toastManager.show("Trim range exceeds clip duration", type: .error)
                    return
                }
                
                // CRITICAL FIX: Validate trim range doesn't conflict with removedRanges
                let trimRange = CMTimeRange(start: newStart, duration: CMTimeSubtract(newEnd, newStart))
                for removedRange in clip.removedRanges {
                    // Check if ranges overlap: (start1 < end2) && (start2 < end1)
                    let trimEnd = CMTimeAdd(trimRange.start, trimRange.duration)
                    let removedEnd = CMTimeAdd(removedRange.timeRange.start, removedRange.timeRange.duration)
                    if trimRange.start < removedEnd && removedRange.timeRange.start < trimEnd {
                        AppLogger.project.warning("Trim range conflicts with removed range: \(removedRange.timeRange.start.seconds)s-\(removedEnd.seconds)s")
                        ServiceContainer.shared.toastManager.show("Trim range conflicts with removed section", type: .error)
                        return
                    }
                }
                
                // setTrimRange will clamp values, but we've validated above for better error messages
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
            
            // CRITICAL FIX: Update timeline duration after trim
            timeline.updateDuration()
            
            // CRITICAL FIX: Validate timeline state after trim
            if !validateTimelineState(timeline) {
                AppLogger.project.error("Timeline state invalid after trim, rolling back")
                ServiceContainer.shared.toastManager.show("Trim failed: Timeline state invalid", type: .error)
                return
            }
            
            project.timeline = timeline
            currentProject = project
            saveProject(project)
            AppLogger.project.info("Updated trim for clip \(clipId)")
            ServiceContainer.shared.toastManager.show("Trimmed Clip")
        }
    }

    // MARK: - Rotation

    /// Rotate clip clockwise by 90 degrees
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

    /// Set clip rotation to a specific angle
    func setClipRotation(_ clip: VideoClip, to rotation: VideoClip.Rotation) {
        guard !isProcessing else { return }
        guard var project = currentProject else { return }

        // Skip if already at target rotation
        guard clip.rotation != rotation else { return }

        var timeline = project.timeline
        var clipFound = false

        for (trackIndex, track) in timeline.tracks.enumerated() {
            if let index = track.clips.firstIndex(where: { $0.id == clip.id }) {
                registerUndo("Set Rotation")

                var mutableTrack = track
                var mutableClip = track.clips[index]
                mutableClip.rotation = rotation

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

            AppLogger.project.info("Set clip \(clip.id) rotation to \(rotation.displayName)")
            ServiceContainer.shared.toastManager.show("Rotated \(rotation.displayName)")
        }
    }
}
