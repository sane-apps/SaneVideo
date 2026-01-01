//
//  ProjectState+Audio.swift
//  SaneVideo
//
//  Consolidated from ProjectState+Audio.swift and ProjectState+AudioServices.swift
//

import AVFoundation
import CoreMedia
import Foundation
import SwiftUI

// MARK: - Volume & AI Audio Effects

extension ProjectState {

    /// Update clip volume
    func updateClipVolume(clipId: UUID, volume: Float, transactionId: UUID? = nil) {
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

            if enabled {
                Task {
                    await triggerAudioEnhancement(for: clipId)
                }
            }
        }
    }

    private func triggerAudioEnhancement(for clipId: UUID) async {
        guard let project = currentProject else { return }

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

// MARK: - Silence & Filler Word Removal

extension ProjectState {

    func removeSilence(from clip: VideoClip) {
        guard currentProject != nil else { return }

        let silenceDetector = ServiceContainer.shared.silenceDetector
        self.isProcessing = true
        self.processingStatus = "🔇 Analyzing audio..."
        self.processingProgress = 0.0
        ServiceContainer.shared.toastManager.show("Detecting silence...")

        Task {
            defer {
                Task { @MainActor in
                    self.isProcessing = false
                    self.processingStatus = nil
                    self.processingProgress = 0.0
                }
            }
            do {
                let tracker = ProgressTracker(interval: 3.0)
                let silentRanges = try await silenceDetector.detectSilence(in: clip) { processed, total in
                    if tracker.shouldUpdate() {
                        let percent = processed / total
                        Task { @MainActor in
                            self.processingProgress = percent
                            self.processingStatus = "🔇 Analyzing audio... \(Int(percent * 100))%"
                            ServiceContainer.shared.toastManager.show(
                                "🔇 Analyzing audio... \(Int(percent * 100))%")
                        }
                    }
                }

                if silentRanges.isEmpty {
                    await MainActor.run { ServiceContainer.shared.toastManager.show("No silence detected") }
                    return
                }

                await MainActor.run {
                    self.applySilenceRemoval(to: clip, silentRanges: silentRanges)
                    ServiceContainer.shared.toastManager.show(
                        "✅ Removed \(silentRanges.count) silent segments")
                }
            } catch {
                await MainActor.run {
                    ServiceContainer.shared.toastManager.show("Silence detection failed", type: .error)
                    ServiceContainer.shared.errorPresenter.present(AppError.unknown(error))
                }
            }
        }
    }

    func removeFillerWords(from clip: VideoClip) {
        guard currentProject != nil else { return }
        guard currentProject?.timeline.tracks.contains(where: {
            $0.clips.contains(where: { $0.id == clip.id })
        }) == true else { return }

        if clip.captions.isEmpty {
            // NOTE: generateCaptions handles its own status updates
            Task {
                do {
                    _ = try await generateCaptions(for: clip)
                    if let project = currentProject,
                       let track = project.timeline.tracks.first(where: {
                           $0.clips.contains(where: { $0.id == clip.id })
                       }),
                       let updatedClip = track.clips.first(where: { $0.id == clip.id }) {
                        await removeFillerWordsInternal(from: updatedClip)
                    }
                } catch {
                    ServiceContainer.shared.toastManager.show("Caption generation failed", type: .error)
                    isProcessing = false
                }
            }
            return
        }
        Task { await removeFillerWordsInternal(from: clip) }
    }

    func removeFillerWordsInternal(from clip: VideoClip) async {
        isProcessing = true
        processingStatus = "🧼 Removing fillers..."
        processingProgress = 0.0
        defer {
            isProcessing = false
            processingStatus = nil
            processingProgress = 0.0
        }

        let fillerRanges = await MagicFixService.detectFillerWords(in: clip)
        if fillerRanges.isEmpty {
            ServiceContainer.shared.toastManager.show("No filler words detected")
            return
        }

        ServiceContainer.shared.toastManager.show("Removing \(fillerRanges.count) filler words...")
        applySilenceRemoval(to: clip, silentRanges: fillerRanges)
        ServiceContainer.shared.toastManager.show("✅ Removed \(fillerRanges.count) filler words")
    }

    func applySilenceRemoval(to clip: VideoClip, silentRanges: [CMTimeRange]) {
        guard var project = currentProject else { return }

        var trackIndex: Int?
        var clipIndex: Int?
        for (tIdx, track) in project.timeline.tracks.enumerated() {
            if let cIdx = track.clips.firstIndex(where: { $0.id == clip.id }) {
                trackIndex = tIdx
                clipIndex = cIdx
                break
            }
        }
        guard let tIdx = trackIndex, let cIdx = clipIndex else { return }

        let intersectingSilence = MagicFixService.filterRangesToTrimWindow(ranges: silentRanges, clip: clip)
        if intersectingSilence.isEmpty { return }

        ServiceContainer.shared.toastManager.show("Removing \(intersectingSilence.count) Silent Segments...")

        var modifiedClip = clip
        for silence in intersectingSilence {
            let activeRange = CMTimeRange(start: clip.trimStart, end: clip.trimEnd)
            let effectiveSilence = silence.intersection(activeRange)
            if effectiveSilence.duration.seconds > 0.1 {
                modifiedClip.addRemovedRange(effectiveSilence)
            }
        }

        registerUndo("Trim Silence")
        project.timeline.tracks[tIdx].clips[cIdx] = modifiedClip
        currentProject = project
        saveProject(project)
    }
}

// MARK: - Audio Enhancement & Batch Operations

extension ProjectState {

    func enhanceAudio(for clip: VideoClip) async {
        guard var project = currentProject,
              let index = project.timeline.tracks.firstIndex(where: {
                  $0.clips.contains(where: { $0.id == clip.id })
              }),
              let clipIndex = project.timeline.tracks[index].clips.firstIndex(where: {
                  $0.id == clip.id
              })
        else { return }

        do {
            let enhancedURL = try await ServiceContainer.shared.audioEnhancementService
                .enhanceAudio(from: clip.url) { [weak self] progress in
                    Task { @MainActor in
                        self?.processingProgress = progress
                        self?.processingStatus = "🎙️ Enhancing audio... \(Int(progress * 100))%"
                    }
                }

            await MainActor.run {
                registerUndo("Enhance Audio")
                project.timeline.tracks[index].clips[clipIndex].enhancedAudioURL = enhancedURL
                currentProject = project
                saveProject(project)
                ServiceContainer.shared.toastManager.show("🎙️ Audio Enhanced!")
            }
        } catch {
            AppLogger.recording.error("❌ enhanceAudio failed: \(error)")
            await MainActor.run {
                ServiceContainer.shared.toastManager.show(
                    "Audio enhancement failed: \(error.localizedDescription)")
            }
        }
    }

    /// Cleans audio for the entire project (Batch)
    func cleanProjectAudio() async {
        guard let project = currentProject else { return }

        isProcessing = true
        processingProgress = 0.0
        processingStatus = "🧹 Starting Global Audio Cleanup..."
        ServiceContainer.shared.toastManager.show("🧹 Starting Global Audio Cleanup...")

        defer {
            isProcessing = false
            processingStatus = nil
            processingProgress = 0.0
        }

        let allClips = project.timeline.tracks.flatMap { $0.clips }
        let total = Double(allClips.count)

        await withTaskGroup(of: Void.self) { group in
            let maxConcurrent = 4
            var activeTasks = 0

            for (index, clip) in allClips.enumerated() {
                if activeTasks >= maxConcurrent {
                    await group.next()
                    activeTasks -= 1
                }

                group.addTask {
                    await MainActor.run {
                        self.processingStatus =
                            "🧹 Cleaning audio (\(index + 1)/\(allClips.count)): \(clip.url.lastPathComponent)"
                        self.processingProgress = Double(index) / total
                    }

                    await self.removeSilenceInternal(for: clip)

                    if clip.captions.isEmpty {
                        _ = try? await self.generateCaptions(for: clip)
                    }

                    if let updatedClip = await self.getClip(by: clip.id) {
                        await self.removeFillerWordsInternal(from: updatedClip)
                    }
                }
                activeTasks += 1
            }
            await group.waitForAll()
        }

        processingProgress = 1.0
        ServiceContainer.shared.toastManager.show("✅ Project Audio Cleaned (Parallelized)!")
    }

    private func removeSilenceInternal(for clip: VideoClip) async {
        let silenceDetector = ServiceContainer.shared.silenceDetector
        do {
            let silentRanges = try await silenceDetector.detectSilence(in: clip) { _, _ in }
            if !silentRanges.isEmpty {
                await MainActor.run {
                    self.applySilenceRemoval(to: clip, silentRanges: silentRanges)
                }
            }
        } catch {
            AppLogger.audio.error("Batch Audio: Silence removal failed for \(clip.id): \(error)")
        }
    }
}
