//
//  ProjectState+ClipRemoval.swift
//  SaneVideo
//
//  Created by SaneVideo Refactor
//

import AppKit
import Foundation
import SwiftUI

extension ProjectState {

    // MARK: - Removal

    func deleteClip(_ clip: VideoClip, transactionId: UUID? = nil) {
        guard !shouldBlockOperation(transactionId: transactionId) else { return }
        guard var project = currentProject else { return }

        // Phase 2: Check if track is locked
        if isTrackLocked(for: clip) {
            ServiceContainer.shared.toastManager.show("Track is locked", type: .error)
            return
        }

        registerUndo("Delete Clip")

        // Remove from timeline (iterate all tracks)
        var timeline = project.timeline
        var clipFound = false

        for (trackIndex, track) in timeline.tracks.enumerated()
        where track.clips.contains(where: { $0.id == clip.id }) {
            var mutableTrack = track
            mutableTrack.clips.removeAll { $0.id == clip.id }
            timeline.tracks[trackIndex] = mutableTrack
            clipFound = true
            break
        }

        if clipFound {
            // CRITICAL FIX: Recalculate startTimes to ensure consistency
            recalculateStartTimes(in: &timeline)

            // CRITICAL FIX: Update timeline duration after deletion
            timeline.updateDuration()

            // CRITICAL FIX: Validate timeline state after deletion
            if !validateTimelineState(timeline) {
                AppLogger.project.error("Timeline state invalid after deletion, rolling back")
                ServiceContainer.shared.toastManager.show("Delete failed: Timeline state invalid", type: .error)
                return
            }

            project.timeline = timeline
            currentProject = project
            saveProject(project)

            AppLogger.project.info("Removed clip from timeline: \(clip.url.lastPathComponent)")
            ServiceContainer.shared.toastManager.show("Deleted Clip")
        }
    }

    /// destructively delete the file from disk (Move to Trash) and remove from project
    func deleteClipFile(_ clip: VideoClip) {
        // CRITICAL FIX: Mark clip as missing before deletion to prevent operations on missing file
        guard var project = currentProject else { return }
        var timeline = project.timeline

        // Mark clip as missing in timeline
        for (trackIndex, track) in timeline.tracks.enumerated() {
            if let clipIndex = track.clips.firstIndex(where: { $0.id == clip.id }) {
                var mutableTrack = track
                var mutableClip = track.clips[clipIndex]
                mutableClip.isMissing = true
                mutableTrack.clips[clipIndex] = mutableClip
                timeline.tracks[trackIndex] = mutableTrack
                project.timeline = timeline
                currentProject = project
                break
            }
        }

        // 1. Remove from timeline
        deleteClip(clip)

        Task {
            do {
                try await ServiceContainer.shared.projectFileManager.deleteFile(at: clip.url)
                AppLogger.project.info("Moved file to Trash: \(clip.url.lastPathComponent)")
            } catch {
                AppLogger.project.error("Failed to move file to Trash: \(error)")
                await MainActor.run {
                    ServiceContainer.shared.errorPresenter.present(AppError.unknown(error))
                }
            }
        }
    }
}
