//
//  ProjectState+ClipProperties.swift
//  SaneVideo
//
//  Created by SaneVideo Refactor
//

import AppKit
import Foundation
import SwiftUI

extension ProjectState {
    
    // MARK: - Transform

    func updateClipTransform(_ clip: VideoClip, transform: VideoClip.Transform) {
        guard !isProcessing else { return }
        guard var project = currentProject else { return }

        var timeline = project.timeline
        var clipFound = false

        for (trackIndex, track) in timeline.tracks.enumerated() {
            if let index = track.clips.firstIndex(where: { $0.id == clip.id }) {
                if track.isLocked { return }

                var mutableTrack = track
                mutableTrack.clips[index].transform = transform
                timeline.tracks[trackIndex] = mutableTrack
                clipFound = true
                break
            }
        }

        if clipFound {
            project.timeline = timeline
            currentProject = project
            // Note: For high-frequency updates (drag), we might want to debounce saving.
            // But for safety, we queue it.
            saveProject(project)
        }
    }

    // MARK: - Speed

    /// Update clip playback speed
    func updateClipSpeed(clipId: UUID, speed: Double) {
        guard !isProcessing else { return }
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

                registerUndo("Change Speed")

                var mutableTrack = track
                mutableTrack.clips[index].speed = speed
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

            AppLogger.project.info("Updated clip speed to \(speed)x")
            ServiceContainer.shared.toastManager.show(String(format: "Speed: %.2fx", speed))
        }
    }

    // MARK: - Volume

    /// Update clip volume
    func updateClipVolume(clipId: UUID, volume: Float) {
        guard !isProcessing else { return }
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
        }
    }

    // MARK: - Effects

    /// Update clip effects
    func updateClipEffects(clipId: UUID, effects: [VideoEffect]) {
        guard !isProcessing else { return }
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

                registerUndo("Update Effects")

                var mutableTrack = track
                mutableTrack.clips[index].effects = effects
                timeline.tracks[trackIndex] = mutableTrack
                clipFound = true
                break
            }
        }

        if clipFound {
            project.timeline = timeline
            currentProject = project
            saveProject(project)

            AppLogger.project.info("Updated clip effects: \(effects.count) effects applied")
        }
    }
    
    /// Update clip background effect (person segmentation)
    func updateClipBackgroundEffect(clipId: UUID, effect: BackgroundEffect?) {
        guard !isProcessing else { return }
        guard var project = currentProject else { return }

        var timeline = project.timeline
        var clipFound = false

        for (trackIndex, track) in timeline.tracks.enumerated() {
            if let index = track.clips.firstIndex(where: { $0.id == clipId }) {
                if track.isLocked {
                    ServiceContainer.shared.toastManager.show("Track is locked", type: .error)
                    return
                }

                registerUndo("Update Background")

                var mutableTrack = track
                mutableTrack.clips[index].backgroundEffect = effect
                timeline.tracks[trackIndex] = mutableTrack
                clipFound = true
                break
            }
        }

        if clipFound {
            project.timeline = timeline
            currentProject = project
            saveProject(project)

            let effectName = effect?.displayName ?? "None"
            AppLogger.project.info("Updated clip background effect: \(effectName)")
            ServiceContainer.shared.toastManager.show("Background: \(effectName)")
        }
    }

    /// Apply a single effect to a clip (replaces existing effects of same type)
    func applyEffect(to clip: VideoClip, effect: VideoEffect) {
        // Replace any existing effect of the same type, or add new
        var newEffects = clip.effects.filter { $0.type != effect.type }
        newEffects.append(effect)
        updateClipEffects(clipId: clip.id, effects: newEffects)
    }

    /// Clear all effects from a clip
    func clearEffects(from clip: VideoClip) {
        updateClipEffects(clipId: clip.id, effects: [])
    }

    // MARK: - Transitions

    /// Set transition for a clip (transition INTO this clip from previous)
    func setClipTransition(clipId: UUID, transitionType: TransitionType) {
        guard !isProcessing else { return }
        guard var project = currentProject else { return }

        var timeline = project.timeline
        var clipFound = false

        for (trackIndex, track) in timeline.tracks.enumerated() {
            if let index = track.clips.firstIndex(where: { $0.id == clipId }) {
                if track.isLocked {
                    ServiceContainer.shared.toastManager.show("Track is locked", type: .error)
                    return
                }

                registerUndo("Set Transition")

                var mutableTrack = track
                if transitionType == .none {
                    mutableTrack.clips[index].transition = nil
                } else {
                    mutableTrack.clips[index].transition = VideoTransition(type: transitionType)
                }
                timeline.tracks[trackIndex] = mutableTrack
                clipFound = true
                break
            }
        }

        if clipFound {
            project.timeline = timeline
            currentProject = project
            saveProject(project)

            if transitionType == .none {
                ServiceContainer.shared.toastManager.show("Removed transition")
            } else {
                ServiceContainer.shared.toastManager.show("Added \(transitionType.displayName) transition")
            }
            AppLogger.project.info("Set transition \(transitionType.rawValue) for clip \(clipId)")
        }
    }

    // MARK: - Overlay Management

    func updateClipOverlay(clipId: UUID, overlay: VideoClip.VideoOverlay) {
        guard !isProcessing else { return }
        guard var project = currentProject else { return }

        var timeline = project.timeline
        var clipFound = false

        for (trackIndex, track) in timeline.tracks.enumerated() {
            if let index = track.clips.firstIndex(where: { $0.id == clipId }) {
                if track.isLocked { return }

                var mutableTrack = track
                var clip = mutableTrack.clips[index]

                if let overlayIndex = clip.overlays.firstIndex(where: { $0.id == overlay.id }) {
                    // Update existing
                    clip.overlays[overlayIndex] = overlay
                } else {
                    // Add new (safeguard)
                    clip.overlays.append(overlay)
                }

                mutableTrack.clips[index] = clip
                timeline.tracks[trackIndex] = mutableTrack
                clipFound = true
                break
            }
        }

        if clipFound {
            project.timeline = timeline
            currentProject = project
            // Queue save
            saveProject(project)
        }
    }

    // MARK: - Cursor Enhancements

    func updateClipCursorHighlight(_ clip: VideoClip, show: Bool) {
        guard !isProcessing else { return }
        guard var project = currentProject else { return }

        var timeline = project.timeline
        var clipFound = false

        for (trackIndex, track) in timeline.tracks.enumerated() {
            if let index = track.clips.firstIndex(where: { $0.id == clip.id }) {
                if track.isLocked {
                    ServiceContainer.shared.toastManager.show("Track is locked", type: .error)
                    return
                }

                registerUndo("Toggle Cursor Highlight")

                var mutableTrack = track
                mutableTrack.clips[index].showCursorHighlight = show
                timeline.tracks[trackIndex] = mutableTrack
                clipFound = true
                break
            }
        }

        if clipFound {
            project.timeline = timeline
            currentProject = project
            saveProject(project)

            AppLogger.project.info("Updated clip cursor highlight to \(show)")
        }
    }

    // MARK: - AI Audio

    func updateClipVoiceIsolation(clipId: UUID, enabled: Bool) {
        guard !isProcessing else { return }
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
            
            // Trigger enhancement if enabled and not already done
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
        for (tIdx, track) in timeline.tracks.enumerated() where track.clips.contains(where: { $0.id == clipId }) {
            clipToUpdate = track.clips.first { $0.id == clipId }
            trackIdx = tIdx
            break
        }
        
        guard let clip = clipToUpdate, clip.enhancedAudioURL == nil else { return }
        
        AppLogger.audio.info("Starting background audio enhancement for clip \(clipId)")
        
        do {
            let enhancedURL = try await ServiceContainer.shared.audioEnhancementService.enhanceAudio(from: clip.url)
            
            // Re-fetch project to ensure we don't overwrite other concurrent changes
            if var latestProject = currentProject {
                if let latestCIdx = latestProject.timeline.tracks[trackIdx].clips.firstIndex(where: { $0.id == clipId }) {
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

    func updateClipGating(clipId: UUID, enabled: Bool) {
        guard !isProcessing else { return }
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
        }
    }
}
