//
//  ProjectState+AudioServices.swift
//  SaneVideo
//

import AVFoundation
import Foundation

extension ProjectState {
    // MARK: - Silence Removal

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
                            ServiceContainer.shared.toastManager.show("🔇 Analyzing audio... \(Int(percent * 100))%") 
                        }
                    }
                }

                if silentRanges.isEmpty {
                    await MainActor.run { ServiceContainer.shared.toastManager.show("No silence detected") }
                    return
                }

                await MainActor.run {
                    self.applySilenceRemoval(to: clip, silentRanges: silentRanges)
                    ServiceContainer.shared.toastManager.show("✅ Removed \(silentRanges.count) silent segments")
                }
            } catch {
                await MainActor.run {
                    ServiceContainer.shared.toastManager.show("Silence detection failed", type: .error)
                    ServiceContainer.shared.errorPresenter.present(AppError.unknown(error))
                }
            }
        }
    }

    // MARK: - Filler Word Removal

    func removeFillerWords(from clip: VideoClip) {
        guard currentProject != nil else { return }
        guard currentProject?.timeline.tracks.contains(where: { $0.clips.contains(where: { $0.id == clip.id }) }) == true else { return }

        if clip.captions.isEmpty {
            ServiceContainer.shared.toastManager.show("Transcribing audio...")
            Task {
                do {
                    _ = try await generateCaptions(for: clip)
                    if let project = currentProject,
                       let track = project.timeline.tracks.first(where: { $0.clips.contains(where: { $0.id == clip.id }) }),
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
                trackIndex = tIdx; clipIndex = cIdx; break
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

    // MARK: - Audio Enhancement

    func enhanceAudio(for clip: VideoClip) async {
        guard var project = currentProject,
              let index = project.timeline.tracks.firstIndex(where: { $0.clips.contains(where: { $0.id == clip.id }) }),
              let clipIndex = project.timeline.tracks[index].clips.firstIndex(where: { $0.id == clip.id })
        else { return }

        do {
            let enhancedURL = try await ServiceContainer.shared.audioEnhancementService.enhanceAudio(from: clip.url) { progress in
                self.processingProgress = progress
                self.processingStatus = "🎙️ Enhancing audio... \(Int(progress * 100))%"
            }
            
            await MainActor.run {
                registerUndo("Enhance Audio")
                project.timeline.tracks[index].clips[clipIndex].enhancedAudioURL = enhancedURL
                currentProject = project
                saveProject(project)
                ServiceContainer.shared.toastManager.show("🎙️ Audio Enhanced!")
                // Reset progress (unless MagicFix uses it for next step)
                // In Magic Fix flow, the orchestrator overrides this anyway
            }
        } catch {
            AppLogger.recording.error("❌ enhanceAudio failed: \(error)")
            await MainActor.run { 
                ServiceContainer.shared.toastManager.show("Audio enhancement failed: \(error.localizedDescription)")
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
        
        // Parallel Processing for efficiency (Industry Standard)
        // Limit concurrency to avoid OOM/Throttling (e.g., 4 concurrent tracks)
        await withTaskGroup(of: Void.self) { group in
            let maxConcurrent = 4
            var activeTasks = 0
            
            for (index, clip) in allClips.enumerated() {
                if activeTasks >= maxConcurrent {
                    await group.next()
                    activeTasks -= 1
                }
                
                group.addTask {
                    // Update status (MainActor) - throttled could be better but this is fine for now
                    await MainActor.run {
                        self.processingStatus = "🧹 Cleaning audio (\(index + 1)/\(allClips.count)): \(clip.url.lastPathComponent)"
                        self.processingProgress = Double(index) / total
                    }

                    // 1. Remove Silence
                    await self.removeSilenceInternal(for: clip)
                    
                    // 2. Remove Fillers (requires captions) which is actor-isolated so safe to call, 
                    // but we need to be careful about clip state freshness.
                    // Ideally we'd operate on local copies and merge, but ProjectState updates are atomic-ish on MainActor.
                    // For now, simpler parallel execution of the heavy lifting.
                    
                    // Note: generateCaptions updates state. removeFillerWordsInternal updates state.
                    // Concurrent updates to DIFFERENT clips is safe if the State functions handle index lookups dynamically.
                    // Our applies usually look up by ID.
                    
                    if clip.captions.isEmpty {
                        _ = try? await self.generateCaptions(for: clip)
                    }
                    
                    // Re-fetch clip to get latest captions
                    if let updatedClip = await self.getClip(by: clip.id) {
                        await self.removeFillerWordsInternal(from: updatedClip)
                    }
                }
                activeTasks += 1
            }
            // Wait for remaining
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
