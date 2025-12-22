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
            let enhancedURL = try await ServiceContainer.shared.audioEnhancementService.enhanceAudio(from: clip.url)
            await MainActor.run {
                registerUndo("Enhance Audio")
                project.timeline.tracks[index].clips[clipIndex].enhancedAudioURL = enhancedURL
                currentProject = project
                saveProject(project)
                ServiceContainer.shared.toastManager.show("🎙️ Audio Enhanced!")
            }
        } catch {
            await MainActor.run { ServiceContainer.shared.toastManager.show("Audio enhancement failed") }
        }
    }
}
