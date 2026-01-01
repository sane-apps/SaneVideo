//
//  ProjectState+Timeline.swift
//  SaneVideo
//
//  Consolidated from Timeline, TrackManagement, and BatchOperations
//

import AVFoundation
import Foundation
import SwiftUI

// MARK: - Timeline Processing

extension ProjectState {

    func recalculateStartTimes(in timeline: inout Timeline) {
        // Use UserDefaults directly instead of @AppStorage (property wrapper not valid inside functions)
        let magneticTimeline = UserDefaults.standard.object(forKey: "magneticTimeline") as? Bool ?? true

        for (trackIndex, track) in timeline.tracks.enumerated() {
            var mutableTrack = track

            mutableTrack.clips.sort { $0.startTime < $1.startTime }

            if magneticTimeline {
                var cumulativeTime = CMTime.zero
                for clipIndex in 0..<mutableTrack.clips.count {
                    mutableTrack.clips[clipIndex].startTime = cumulativeTime

                    // DEBUG: Catch negative timestamps at creation point
                    #if DEBUG
                    if cumulativeTime.seconds < 0 {
                        AppLogger.project.error("🚨 DEBUG: Negative cumulativeTime \(cumulativeTime.seconds)s at clip \(clipIndex)")
                        assertionFailure("Negative timestamp detected in recalculateStartTimes - investigate source")
                    }
                    #endif

                    cumulativeTime = CMTimeAdd(
                        cumulativeTime, mutableTrack.clips[clipIndex].effectiveDuration)
                }
            } else {
                // CRITICAL FIX: Guard against empty or single-clip tracks
                // Range 1..<0 causes "Fatal error: Range requires lowerBound <= upperBound"
                if mutableTrack.clips.count > 1 {
                    for clipIndex in 1..<mutableTrack.clips.count {
                        let prevClip = mutableTrack.clips[clipIndex - 1]
                        let prevEnd = CMTimeAdd(prevClip.startTime, prevClip.effectiveDuration)
                        let currentClip = mutableTrack.clips[clipIndex]

                        if currentClip.startTime < prevEnd {
                            mutableTrack.clips[clipIndex].startTime = prevEnd
                        }
                    }
                }
            }
            timeline.tracks[trackIndex] = mutableTrack
        }

        timeline.updateDuration()
    }

    func validateTimelineState(_ timeline: Timeline) -> Bool {
        var seenIDs = Set<UUID>()
        for track in timeline.tracks {
            for clip in track.clips {
                if seenIDs.contains(clip.id) {
                    AppLogger.project.error("Duplicate clip ID found: \(clip.id)")
                    return false
                }
                seenIDs.insert(clip.id)

                if clip.startTime.seconds < 0 {
                    AppLogger.project.error("Clip has negative startTime: \(clip.id)")
                    #if DEBUG
                    assertionFailure("Clip has negative startTime \(clip.startTime.seconds)s - investigate timeline operations")
                    #endif
                    return false
                }

                if clip.effectiveDuration.seconds <= 0 {
                    AppLogger.project.error("Clip has zero or negative duration: \(clip.id)")
                    return false
                }

                let sortedClips = track.clips.sorted { $0.startTime < $1.startTime }
                for i in 1..<sortedClips.count {
                    let prevClip = sortedClips[i - 1]
                    let currentClip = sortedClips[i]
                    let prevEnd = CMTimeAdd(prevClip.startTime, prevClip.effectiveDuration)

                    if currentClip.startTime < prevEnd {
                        AppLogger.project.error(
                            "Clips overlap in track: \(prevClip.id) and \(currentClip.id)")
                        return false
                    }
                }
            }
        }

        return true
    }
}

// MARK: - Track Management

extension ProjectState {

    func addTrack(type: TrackType, name: String? = nil) {
        guard var project = currentProject else { return }

        registerUndo("Add Track")

        var timeline = project.timeline

        let trackName: String
        if let name = name {
            trackName = name
        } else {
            let existingCount = timeline.tracks.filter { $0.type == type }.count
            switch type {
            case .video:
                trackName = "Video \(existingCount + 1)"
            case .audio:
                trackName = "Audio \(existingCount + 1)"
            case .overlay:
                trackName = "Overlay \(existingCount + 1)"
            }
        }

        let maxZIndex = timeline.tracks.map(\.zIndex).max() ?? -1
        let newTrack = Track(name: trackName, type: type, zIndex: maxZIndex + 1)

        timeline.addTrack(newTrack)
        project.timeline = timeline
        currentProject = project
        saveProject(project)

        AppLogger.project.info("Added track: \(trackName)")
        ServiceContainer.shared.toastManager.show("Added \(trackName)")
    }

    func deleteTrack(_ track: Track) {
        guard var project = currentProject else { return }
        guard project.timeline.tracks.count > 1 else {
            ServiceContainer.shared.toastManager.show("Cannot delete the last track", type: .error)
            return
        }

        registerUndo("Delete Track")

        var timeline = project.timeline
        timeline.tracks.removeAll { $0.id == track.id }
        project.timeline = timeline
        currentProject = project
        saveProject(project)

        AppLogger.project.info("Deleted track: \(track.name)")
        ServiceContainer.shared.toastManager.show("Deleted \(track.name)")
    }

    func toggleTrackMute(_ track: Track) {
        guard var project = currentProject else { return }
        guard let index = project.timeline.tracks.firstIndex(where: { $0.id == track.id })
        else { return }

        registerUndo("Toggle Mute")

        var timeline = project.timeline
        timeline.tracks[index].isMuted.toggle()
        let isMuted = timeline.tracks[index].isMuted

        project.timeline = timeline
        currentProject = project
        saveProject(project)

        AppLogger.project.info("Track \(track.name) muted: \(isMuted)")
        ServiceContainer.shared.toastManager.show(
            isMuted ? "Muted \(track.name)" : "Unmuted \(track.name)")
    }

    func toggleTrackLock(_ track: Track) {
        guard var project = currentProject else { return }
        guard let index = project.timeline.tracks.firstIndex(where: { $0.id == track.id })
        else { return }

        registerUndo("Toggle Lock")

        var timeline = project.timeline
        timeline.tracks[index].isLocked.toggle()
        let isLocked = timeline.tracks[index].isLocked

        project.timeline = timeline
        currentProject = project
        saveProject(project)

        AppLogger.project.info("Track \(track.name) locked: \(isLocked)")
        ServiceContainer.shared.toastManager.show(
            isLocked ? "Locked \(track.name)" : "Unlocked \(track.name)")
    }
}

// MARK: - Batch Operations

extension ProjectState {

    func performMagicFixAll(options: MagicFixOptions) async -> [BatchItemResult<VideoClip>] {
        guard let project = currentProject else { return [] }

        let allClips = project.timeline.tracks.flatMap { $0.clips }
        guard !allClips.isEmpty else { return [] }

        let batchTransactionId = beginTransaction()
        defer { endTransaction(batchTransactionId) }

        // BATCH FIX: Use a single undo group for the entire batch operation
        // This allows user to undo/redo all changes from Magic Fix All with one action
        beginUndoGroup("Magic Fix All")
        defer { endUndoGroup() }

        processingStatus = "✨ Magic Fix All: Processing \(allClips.count) clips..."
        processingProgress = 0.0

        let results = await BatchCoordinator.execute(
            items: allClips,
            config: .default,
            operation: { clip, index in
                await MainActor.run {
                    self.processingStatus =
                        "✨ Magic Fix (\(index + 1)/\(allClips.count)): \(clip.url.lastPathComponent)"
                    self.processingProgress = Double(index) / Double(allClips.count)
                }

                // BATCH FIX: Pass isBatchOperation=true to skip nested undo groups
                // and avoid overwriting currentProcessingTask
                await self.performMagicFix(for: clip, options: options, isBatchOperation: true)
            },
            progressHandler: { @Sendable completed, total in
                Task { @MainActor in
                    self.processingProgress = Double(completed) / Double(total)
                }
            }
        )

        let successCount = results.filter { $0.success }.count
        let failureCount = results.filter { !$0.success }.count

        processingStatus = "✅ Magic Fix All: \(successCount) succeeded, \(failureCount) failed"
        processingProgress = 1.0

        if failureCount > 0 {
            ServiceContainer.shared.toastManager.show(
                "Magic Fix All: \(successCount) succeeded, \(failureCount) failed",
                type: failureCount == allClips.count ? .error : .info
            )
        } else {
            ServiceContainer.shared.toastManager.show(
                "✅ Magic Fix All: All \(successCount) clips processed",
                type: .success
            )
        }

        return results
    }

    func generateCaptionsAll() async -> [BatchItemResult<VideoClip>] {
        guard let project = currentProject else { return [] }

        let allClips = project.timeline.tracks.flatMap { $0.clips }
        guard !allClips.isEmpty else { return [] }

        let batchTransactionId = beginTransaction()
        defer { endTransaction(batchTransactionId) }

        processingStatus = "🎤 Generating Captions: Processing \(allClips.count) clips..."
        processingProgress = 0.0

        let results = await BatchCoordinator.execute(
            items: allClips,
            config: .default,
            operation: { clip, index in
                await MainActor.run {
                    self.processingStatus =
                        "🎤 Generating Captions (\(index + 1)/\(allClips.count)): \(clip.url.lastPathComponent)"
                    self.processingProgress = Double(index) / Double(allClips.count)
                }

                do {
                    _ = try await self.generateCaptions(for: clip, transactionId: nil)
                } catch {
                    AppLogger.project.error(
                        "Generate All Captions: Failed for clip \(clip.id): \(error)")
                    throw error
                }
            },
            progressHandler: { @Sendable completed, total in
                Task { @MainActor in
                    self.processingProgress = Double(completed) / Double(total)
                }
            }
        )

        let successCount = results.filter { $0.success }.count
        let failureCount = results.filter { !$0.success }.count

        processingStatus = "✅ Captions Generated: \(successCount) succeeded, \(failureCount) failed"
        processingProgress = 1.0

        if failureCount > 0 {
            ServiceContainer.shared.toastManager.show(
                "Generate All Captions: \(successCount) succeeded, \(failureCount) failed",
                type: failureCount == allClips.count ? .error : .info
            )
        } else {
            ServiceContainer.shared.toastManager.show(
                "✅ Generated captions for all \(successCount) clips",
                type: .success
            )
        }

        return results
    }
}
