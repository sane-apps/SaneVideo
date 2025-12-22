//
//  ProjectState+MagicFix.swift
//  SaneVideo
//
//

import AVFoundation
import Foundation

extension ProjectState {
    // MARK: - Magic Fix

    func performMagicFix(for clip: VideoClip, options: MagicFixOptions) async {
        guard !isProcessing, currentProject != nil else { return }
        isProcessing = true
        processingProgress = 0.0
        processingStatus = "✨ Starting Magic Fix..."
        
        AppLogger.project.info("✨ Magic Fix: Starting for clip \(clip.id) (\(clip.url.lastPathComponent))")
        ServiceContainer.shared.toastManager.show("✨ Starting Magic Fix...")
        
        defer { 
            AppLogger.project.info("✨ Magic Fix: Finished processing for clip \(clip.id)")
            Task { @MainActor in 
                self.isProcessing = false 
                self.processingStatus = nil
                self.processingProgress = 1.0
            } 
        }

        // 1. Audio Enhancement (Primary Priority)
        // Enhance audio FIRST so that transcription and silence detection use clean audio
        if options.enhanceAudio {
            processingStatus = "🎙️ Enhancing audio first..."
            await enhanceAudioFirst(for: clip)
            processingProgress = 0.2
        }
        
        // Refresh clip state after potential audio enhancement
        guard let enhancedClipId = Optional(clip.id), let preAnalysisClip = getClip(by: enhancedClipId) else { return }

        // 2. Generate Captions if needed (Using enhanced audio if available)
        if (options.generateCaptions || options.removeFillers || options.autoEnhance) && preAnalysisClip.captions.isEmpty {
             processingStatus = "🎤 Transcribing audio..."
             do { 
                 _ = try await generateCaptions(for: preAnalysisClip) 
             } catch {
                 AppLogger.project.warning("Magic Fix: Caption generation failed, some features like Filler Removal may be skipped.")
             }
        }
        processingProgress = 0.4
        
        // Refresh clip again for analysis
        guard let readyForCutsClip = getClip(by: preAnalysisClip.id) else { return }

        do {
            // 3. Analyis and Cuts (Silence & Fillers)
            // Now runs on clean audio + accurate captions
            processingStatus = "✂️ Analyzing for cuts (Silence & Fillers)..."
            try await processCutsAndSmoothing(for: readyForCutsClip, options: options)
            processingProgress = 0.6

            // Refresh clip for final steps
            guard let visualClip = getClip(by: readyForCutsClip.id) else { return }

            // 4. Visual Enhancements
            try await applyVisualEffects(to: visualClip, options: options)
            
            // 5. AI & Generative Features
            try await applyAIGenerativeFeatures(to: visualClip, options: options)

            processingProgress = 1.0
            processingStatus = "✅ Magic Fix Completed"
            ServiceContainer.shared.toastManager.show("✨ Magic Fix Completed", type: .info)
            AppLogger.project.info("✨ Magic Fix: One-click flow finished successfully")
        } catch {
            processingStatus = "❌ Failed"
            ServiceContainer.shared.toastManager.show("Magic Fix failed: \(error.localizedDescription)", type: .error) 
            AppLogger.project.error("✨ Magic Fix: Error during orchestration: \(error)")
        }
    }
    
    // MARK: - Magic Fix Modular Helpers

    private func processCutsAndSmoothing(for clip: VideoClip, options: MagicFixOptions) async throws {
        AppLogger.project.info("✨ Magic Fix: Calling MagicFixService.applyMagicFix for cuts...")
        let keepRanges = try await MagicFixService.applyMagicFix(
            to: clip,
            options: options,
            progressHandler: { progressPercent, _ in 
                let subProgress = Double(progressPercent) / 100.0
                Task { @MainActor in
                    self.processingProgress = 0.3 + (subProgress * 0.3) // 30% -> 60%
                }
                AppLogger.project.debug("✨ Magic Fix Progress: \(progressPercent)%")
            }
        )
        AppLogger.project.info("✨ Magic Fix: Received \(keepRanges.count) keep ranges from service")
        
        let removedRanges = MagicFixService.calculateRemovedRanges(from: keepRanges, duration: clip.duration)
        let codableRemovals = removedRanges.map { CodableTimeRange($0) }
        
        if codableRemovals != clip.removedRanges || options.smoothJumpCuts != clip.useSmoothCutForRemovals {
            await MainActor.run {
                self.registerUndo("Magic Fix (Cuts & Smoothing)")
                guard var project = self.currentProject else { return }
                
                if let index = project.timeline.tracks.firstIndex(where: { $0.clips.contains(where: { $0.id == clip.id }) }),
                   let clipIndex = project.timeline.tracks[index].clips.firstIndex(where: { $0.id == clip.id }) {
                    project.timeline.tracks[index].clips[clipIndex].removedRanges = codableRemovals
                    project.timeline.tracks[index].clips[clipIndex].useSmoothCutForRemovals = options.smoothJumpCuts
                    
                    self.currentProject = project
                    self.saveProject(project)
                }
                
                let cutCount = codableRemovals.count - clip.removedRanges.count
                if cutCount > 0 {
                    ServiceContainer.shared.toastManager.show("✅ Magically fixed: Added \(cutCount) cuts")
                }
            }
        }
    }

    private func enhanceAudioFirst(for clip: VideoClip) async {
        // Wrapper for internal enhance call, ensuring UI updates
        processingStatus = "🎙️ Enhancing audio..."
        await enhanceAudio(for: clip)
    }

    private func applyVisualEffects(to clip: VideoClip, options: MagicFixOptions) async throws {
        // 1. Text Scan (Analysis - Independent)
        // Run first as it's purely analytical and non-destructive
        if options.scanForText {
            processingStatus = "🔍 Scanning for text..."
            do {
                _ = try await ServiceContainer.shared.textRecognitionService.scanVideoForText(videoURL: clip.url)
            } catch {
                AppLogger.vision.error("Magic Fix: OCR scan failed: \(error)")
            }
            processingProgress = 0.7
        }

        // 2. Geometry (Mutually Exclusive)
        // Smart Crop supersedes Auto Framing because it enforces a specific aspect ratio (9:16)
        // AND includes its own saliency-based tracking.
        if options.smartCrop {
            processingStatus = "📐 Auto-reframing to 9:16..."
            await applySmartCrop(to: clip, targetAspectRatio: 9.0/16.0)
        } else if options.autoFraming {
            processingStatus = "🎯 Tracking subjects..."
            await applyAutoFraming(to: clip)
        }
        processingProgress = 0.8

        // 3. Color (Correction -> Grading)
        
        // Auto Enhance (Correction/White Balance)
        // Validated Order: Correct the image FIRST to remove casts, then apply stylistic grading.
        if options.autoEnhance {
            processingStatus = "🪄 Enhancing visuals..."
            self.applyEffect(to: clip, effect: VideoEffect(type: .autoEnhance))
        }

        // Color Grade (Styling/Mood)
        if options.analyzeMood {
            processingStatus = "🎨 Grading colors..."
            await applySmartColorGrade(to: clip)
        }
        processingProgress = 0.9
    }

    private func applyAIGenerativeFeatures(to clip: VideoClip, options: MagicFixOptions) async throws {
        if options.magicRemovePeople || options.generativeStyle {
            processingStatus = "🤖 Running AI Generative models..."
            if options.magicRemovePeople { await applyMagicRemove(to: clip) }
            if options.generativeStyle { await applyCinematicStyle(to: clip) }
        }
    }

    // Helper to update clip removals
    private func updateClipRemovals(clipId: UUID, removedRanges: [CodableTimeRange]) {
        guard var project = currentProject else { return }
        for (tIdx, track) in project.timeline.tracks.enumerated() {
            if let cIdx = track.clips.firstIndex(where: { $0.id == clipId }) {
                var clip = track.clips[cIdx]
                clip.removedRanges = removedRanges
                registerUndo("Magic Fix")
                project.timeline.tracks[tIdx].clips[cIdx] = clip
                currentProject = project
                saveProject(project)
                return
            }
        }
    }

    func getClip(by id: UUID) -> VideoClip? {
        guard let project = currentProject else { return nil }
        for track in project.timeline.tracks {
            if let clip = track.clips.first(where: { $0.id == id }) {
                return clip
            }
        }
        return nil
    }
}
