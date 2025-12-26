//
//  ProjectState+Audio.swift
//  SaneVideo
//
//  Created by SaneVideo Refactor
//

import AVFoundation
import Foundation
import SwiftUI

extension ProjectState {

    // MARK: - Volume

    /// Update clip volume
    func updateClipVolume(clipId: UUID, volume: Float, transactionId: UUID? = nil) {
        guard !shouldBlockOperation(transactionId: transactionId) else { return }
        guard var project = currentProject else { return }

        var timeline = project.timeline
        var clipFound = false

        for (trackIndex, track) in timeline.tracks.enumerated() {
            if let index = track.clips.firstIndex(where: { $0.id == clipId }) {
                // Check lock
                if track.isLocked {
                    ServiceContainer.shared.toastManager.show("Track is locked", type: .error)
                    return
                }

                registerUndo("Change Volume")

                var mutableTrack = track
                mutableTrack.clips[index].volume = volume
                timeline.tracks[trackIndex] = mutableTrack
                clipFound = true
                break
            }
        }

        if clipFound {
            project.timeline = timeline
            currentProject = project
            saveProject(project)

            AppLogger.project.info("Updated clip volume to \(Int(volume * 100))%")

            // INSTANT PREVIEW: Update real-time audio processor immediately
            if let clip = getClip(by: clipId) {
                Task {
                    do {
                        try await ServiceContainer.shared.realTimeAudioProcessor.updateEffects(for: clip)
                    } catch {
                        AppLogger.audio.warning(
                            "Failed to update real-time audio volume: \(error.localizedDescription)")
                    }
                }
            }
        }
    }

    // MARK: - AI Audio

    func updateClipVoiceIsolation(clipId: UUID, enabled: Bool, transactionId: UUID? = nil) {
        guard !shouldBlockOperation(transactionId: transactionId) else { return }
        guard var project = currentProject else { return }

        var timeline = project.timeline
        var clipFound = false

        for (trackIndex, track) in timeline.tracks.enumerated() {
            if let index = track.clips.firstIndex(where: { $0.id == clipId }) {
                if track.isLocked {
                    ServiceContainer.shared.toastManager.show("Track is locked", type: .error)
                    return
                }

                registerUndo("Toggle Voice Isolation")

                var mutableTrack = track
                mutableTrack.clips[index].isVoiceIsolationEnabled = enabled
                timeline.tracks[trackIndex] = mutableTrack
                clipFound = true
                break
            }
        }

        if clipFound {
            project.timeline = timeline
            currentProject = project
            saveProject(project)

            AppLogger.project.info("Updated clip voice isolation to \(enabled)")
            ServiceContainer.shared.toastManager.show("Voice Isolation: \(enabled ? "On" : "Off")")

            // INSTANT PREVIEW: Update real-time audio processor immediately
            if let clip = getClip(by: clipId) {
                Task {
                    do {
                        try await ServiceContainer.shared.realTimeAudioProcessor.updateEffects(for: clip)
                        AppLogger.audio.info("Real-time audio effects updated instantly")
                    } catch {
                        AppLogger.audio.warning(
                            "Failed to update real-time audio effects: \(error.localizedDescription)")
                    }
                }
            }

            // Trigger background enhancement for export (but preview is instant)
            if enabled {
                Task {
                    await triggerAudioEnhancement(for: clipId)
                }
            }
        }
    }

    private func triggerAudioEnhancement(for clipId: UUID) async {
        guard let project = currentProject else { return }

        // Find the clip again in the latest state
        let timeline = project.timeline
        var clipToUpdate: VideoClip?
        var trackIdx: Int = -1
        for (tIdx, track) in timeline.tracks.enumerated()
        where track.clips.contains(where: { $0.id == clipId }) {
            clipToUpdate = track.clips.first { $0.id == clipId }
            trackIdx = tIdx
            break
        }

        guard let clip = clipToUpdate, clip.enhancedAudioURL == nil else { return }

        AppLogger.audio.info("Starting background audio enhancement for clip \(clipId)")

        do {
            let enhancedURL = try await ServiceContainer.shared.audioEnhancementService.enhanceAudio(
                from: clip.url)

            // Re-fetch project to ensure we don't overwrite other concurrent changes
            if var latestProject = currentProject {
                if let latestCIdx = latestProject.timeline.tracks[trackIdx].clips.firstIndex(where: {
                    $0.id == clipId
                }) {
                    latestProject.timeline.tracks[trackIdx].clips[latestCIdx].enhancedAudioURL = enhancedURL
                    currentProject = latestProject
                    saveProject(latestProject)
                    AppLogger.audio.info("Audio enhancement complete for clip \(clipId)")
                    ServiceContainer.shared.toastManager.show("Voice Isolation Ready", type: .success)
                }
            }
        } catch {
            AppLogger.audio.error("Audio enhancement failed: \(error.localizedDescription)")
            ServiceContainer.shared.toastManager.show("Enhancement Failed", type: .error)
        }
    }

    func updateClipGating(clipId: UUID, enabled: Bool, transactionId: UUID? = nil) {
        guard !shouldBlockOperation(transactionId: transactionId) else { return }
        guard var project = currentProject else { return }

        var timeline = project.timeline
        var clipFound = false

        for (trackIndex, track) in timeline.tracks.enumerated() {
            if let index = track.clips.firstIndex(where: { $0.id == clipId }) {
                if track.isLocked {
                    ServiceContainer.shared.toastManager.show("Track is locked", type: .error)
                    return
                }

                registerUndo("Toggle AI Gating")

                var mutableTrack = track
                mutableTrack.clips[index].isGatingEnabled = enabled
                timeline.tracks[trackIndex] = mutableTrack
                clipFound = true
                break
            }
        }

        if clipFound {
            project.timeline = timeline
            currentProject = project
            saveProject(project)

            AppLogger.project.info("Updated clip AI gating to \(enabled)")
            ServiceContainer.shared.toastManager.show("AI Gating: \(enabled ? "On" : "Off")")

            // INSTANT PREVIEW: Update real-time audio processor immediately
            if let clip = getClip(by: clipId) {
                Task {
                    do {
                        try await ServiceContainer.shared.realTimeAudioProcessor.updateEffects(for: clip)
                    } catch {
                        AppLogger.audio.warning(
                            "Failed to update real-time audio gating: \(error.localizedDescription)")
                    }
                }
            }
        }
    }
}
