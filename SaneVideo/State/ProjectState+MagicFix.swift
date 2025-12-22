//
//  ProjectState+MagicFix.swift
//  SaneVideo
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

        // 1. Generate Captions if needed (for Fillers/Enhance)
        if (options.generateCaptions || options.removeFillers || options.autoEnhance) && clip.captions.isEmpty {
             processingStatus = "🎤 Transcribing audio..."
             do { 
                 _ = try await generateCaptions(for: clip) 
             } catch {
                 AppLogger.project.warning("Magic Fix: Caption generation failed, some features like Filler Removal may be skipped.")
             }
        }
        processingProgress = 0.3
        
        // Reload clip to get fresh state (captions)
        guard let currentClipId = Optional(clip.id), let updatedClip = getClip(by: currentClipId) else { return }

        do {
            processingStatus = "✂️ Analyzing for cuts (Silence & Fillers)..."
            AppLogger.project.info("✨ Magic Fix: Calling MagicFixService.applyMagicFix for cuts...")
            let keepRanges = try await MagicFixService.applyMagicFix(
                to: updatedClip,
                options: options,
                progressHandler: { p, _ in 
                    let subProgress = Double(p) / 100.0
                    Task { @MainActor in
                        self.processingProgress = 0.3 + (subProgress * 0.3) // 30% -> 60%
                    }
                    AppLogger.project.debug("✨ Magic Fix Progress: \(p)%")
                }
            )
            AppLogger.project.info("✨ Magic Fix: Received \(keepRanges.count) keep ranges from service")
            
            // 3. Convert Keep Ranges -> Removed Ranges (Inversion)
            let removedRanges = MagicFixService.calculateRemovedRanges(from: keepRanges, duration: updatedClip.duration)
            let codableRemovals = removedRanges.map { CodableTimeRange($0) }
            
            // 4. Update Clip Removals (If changed)
            if codableRemovals != updatedClip.removedRanges || options.smoothJumpCuts != updatedClip.useSmoothCutForRemovals {
                await MainActor.run {
                    self.registerUndo("Magic Fix (Cuts & Smoothing)")
                    guard var project = self.currentProject else { return }
                    
                    if let index = project.timeline.tracks.firstIndex(where: { $0.clips.contains(where: { $0.id == updatedClip.id }) }),
                       let clipIndex = project.timeline.tracks[index].clips.firstIndex(where: { $0.id == updatedClip.id }) {
                        project.timeline.tracks[index].clips[clipIndex].removedRanges = codableRemovals
                        project.timeline.tracks[index].clips[clipIndex].useSmoothCutForRemovals = options.smoothJumpCuts
                        
                        self.currentProject = project
                        self.saveProject(project)
                    }
                    
                    let cutCount = codableRemovals.count - updatedClip.removedRanges.count
                    AppLogger.project.info("✨ Magic Fix: Applied \(codableRemovals.count) removals (\(cutCount) new cuts). Smooth: \(options.smoothJumpCuts)")
                    if cutCount > 0 {
                        ServiceContainer.shared.toastManager.show("✅ Magically fixed: Added \(cutCount) cuts")
                    }
                }
            }
            
            processingProgress = 0.6

            // Refresh clip for subsequent steps
            guard let refreshedClip = getClip(by: updatedClip.id) else { return }

            // 5. Smart Crop (Video Reframing)
            if options.smartCrop {
                processingStatus = "📐 Auto-reframing to 9:16..."
                ServiceContainer.shared.toastManager.show("📐 Auto-reframing to 9:16...") 
                await applySmartCrop(to: refreshedClip, targetAspectRatio: 9.0/16.0)
            }
            processingProgress = 0.7
            
            // 6. Auto Framing (Face Tracking)
            if options.autoFraming {
                processingStatus = "🎯 Tracking subjects..."
                await applyAutoFraming(to: refreshedClip)
            }
            processingProgress = 0.75
            
            // 7. Mood-Based Color Grading
            if options.analyzeMood {
                processingStatus = "🎨 Grading colors..."
                await applySmartColorGrade(to: refreshedClip)
            }
            processingProgress = 0.8
            
            // 8. Auto Enhance (Visuals)
            if options.autoEnhance {
                processingStatus = "🪄 Enhancing visuals..."
                self.applyEffect(to: refreshedClip, effect: VideoEffect(type: .autoEnhance))
                ServiceContainer.shared.toastManager.show("🪄 Visuals auto-enhanced")
            }
            processingProgress = 0.85
            
            // 9. Scan for Text (OCR)
            if options.scanForText {
                processingStatus = "🔍 Scanning for text..."
                ServiceContainer.shared.toastManager.show("🔍 Scanning for text...") 
                do {
                    _ = try await ServiceContainer.shared.textRecognitionService.scanVideoForText(videoURL: refreshedClip.url)
                } catch {
                    AppLogger.vision.error("Magic Fix: OCR scan failed: \(error)")
                }
            }
            processingProgress = 0.9
            
            // 11. Audio Enhancement (Studio Sound)
            if options.enhanceAudio {
                processingStatus = "🎙️ Enhancing audio..."
                await enhanceAudio(for: refreshedClip)
            }
            processingProgress = 0.95
            
            // 13. Magic Remove / Cinematic Style (AI)
            if options.magicRemovePeople || options.generativeStyle {
                processingStatus = "🤖 Running AI Generative models..."
                if options.magicRemovePeople { await applyMagicRemove(to: refreshedClip) }
                if options.generativeStyle { await applyCinematicStyle(to: refreshedClip) }
            }

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
