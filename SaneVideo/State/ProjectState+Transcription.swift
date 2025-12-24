//
//  ProjectState+Transcription.swift
//  SaneVideo
//

import AVFoundation
import Foundation

extension ProjectState {
    // MARK: - Captions & Transcription

    func generateCaptions(for clip: VideoClip) async throws -> Int {
        guard currentProject != nil else { return 0 }

        self.isProcessing = true
        self.processingStatus = "🎤 Transcribing audio..."
        self.processingProgress = 0.0
        ServiceContainer.shared.toastManager.show("🎤 Transcribing audio...")

        defer { 
            Task { @MainActor in 
                self.isProcessing = false 
                self.processingStatus = nil
                self.processingProgress = 0.0
            } 
        }

        AppLogger.project.info("🎤 ProjectState: Requesting caption generation for clip \(clip.id)")
        let tracker = ProgressTracker(interval: 3.0)
        let coordinator = ServiceContainer.shared.transcriptionCoordinator
        
        // Check if we should suggest WhisperKit
        if coordinator.shouldSuggestWhisperKit && coordinator.selectedEngine == .apple {
            await MainActor.run {
                ServiceContainer.shared.toastManager.show(
                    "💡 Tip: Try WhisperKit for better accuracy with accents or noisy audio",
                    type: .info
                )
            }
        }
        
        do {
            let captions = try await coordinator.generateCaptions(for: clip.url) { chunk, total, eta in
                if tracker.shouldUpdate() || chunk == 1 || chunk == total {
                    Task { @MainActor in
                        let percent = Double(chunk) / Double(total)
                        self.processingProgress = percent
                        
                        if chunk == total {
                            self.processingStatus = "🎤 Finishing transcription..."
                            ServiceContainer.shared.toastManager.show("🎤 Finishing transcription...")
                        } else {
                            let etaText = eta > 60 ? "\(eta / 60)m \(eta % 60)s" : "\(eta)s"
                            self.processingStatus = "🎤 Transcribing... \(chunk)/\(total)"
                            ServiceContainer.shared.toastManager.show("🎤 Transcribing... \(chunk)/\(total) (~\(etaText) remaining)")
                        }
                    }
                }
            }

            await MainActor.run {
                AppLogger.project.info("🎤 ProjectState: Received \(captions.count) captions. Applying to clip...")
                self.applyCaptions(to: clip, captions: captions)
                ServiceContainer.shared.toastManager.show("✅ Generated \(captions.count) captions!")
            }
            return captions.count
        } catch {
            AppLogger.project.error("❌ ProjectState: Caption generation failed: \(error.localizedDescription)")
            await MainActor.run {
                ServiceContainer.shared.toastManager.show("❌ Caption generation failed", type: .error)
            }
            throw error
        }
    }

    func applyCaptions(to clip: VideoClip, captions: [Caption]) {
        guard var project = currentProject else { 
            AppLogger.project.error("❌ ProjectState: applyCaptions failed - currentProject is nil")
            return 
        }

        for (tIdx, track) in project.timeline.tracks.enumerated() {
            if let cIdx = track.clips.firstIndex(where: { $0.id == clip.id }) {
                AppLogger.project.info("🎤 ProjectState: Found clip in track \(tIdx) at index \(cIdx). Setting \(captions.count) captions.")
                var updatedClip = track.clips[cIdx]
                updatedClip.captions = captions
                registerUndo("Update Captions")
                project.timeline.tracks[tIdx].clips[cIdx] = updatedClip
                currentProject = project
                saveProject(project)
                return
            }
        }
        AppLogger.project.warning("⚠️ ProjectState: applyCaptions could not find clip \(clip.id) in any track")
    }

    func updateCaptions(for clip: VideoClip, newCaptions: [Caption]) {
        applyCaptions(to: clip, captions: newCaptions)
    }
}
