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
        guard currentProject != nil else { return }

        // CRITICAL FIX: Use transaction system instead of direct isProcessing flag
        // This allows visual effects to be applied during processing
        let transactionId = beginTransaction()
        defer { endTransaction(transactionId) }

        // ENHANCEMENT: Group all undo operations for Magic Fix into a single undo action
        beginUndoGroup("Magic Fix")
        defer { endUndoGroup() }

        // Create cancellable task
        let task = Task { @MainActor [weak self] in
            guard let self = self else { return }

            self.updateTransactionProgress(transactionId, progress: 0.0)
            self.processingStatus = "✨ Starting Magic Fix..."

            // Start performance tracking
            let startTime = Date()
            let performanceMetrics = ServiceContainer.shared.performanceMetrics

            AppLogger.project.info("✨ Magic Fix: Starting for clip \(clip.id) (\(clip.url.lastPathComponent))")
            ServiceContainer.shared.toastManager.show("✨ Starting Magic Fix...")

            defer {
                // Record performance metrics
                let duration = Date().timeIntervalSince(startTime)
                let optionsDescription = "\(options.removeSilence ? "silence " : "")\(options.removeFillers ? "fillers " : "")\(options.autoEnhance ? "enhance" : "")"
                performanceMetrics.recordOperation(
                    name: "Magic Fix",
                    duration: duration,
                    metadata: [
                        "clipDuration": String(format: "%.1f", clip.duration.seconds),
                        "options": optionsDescription.isEmpty ? "none" : optionsDescription
                    ]
                )
                AppLogger.project.info("✨ Magic Fix: Finished processing for clip \(clip.id)")
                self.processingStatus = nil
                self.updateTransactionProgress(transactionId, progress: 1.0)
            }

            // Check for cancellation before starting
            try Task.checkCancellation()

            // 0. Start Concurrent Vision Analysis (Unified Pipeline)
            // Note: Vision task runs detached, cancellation handled via Task cancellation
        // Run with .utility priority to avoid starving the Audio enhancement (Primary UI task)
        // ROBUSTNESS: Add timeout to prevent hangs
        async let visionTask: VisionAnalysisResult? = await Task.detached(priority: .utility) {
            let config = VisionAnalysisConfig(
                detectText: options.scanForText,
                detectFaces: options.autoFraming, // Only if autoFraming enabled
                detectSaliency: options.smartCrop, // Only if smartCrop enabled
                detectPrivacy: options.scanForText // Reuse text scan for privacy
            )

            // Only run if at least one vision feature is enabled
            if config.detectText || config.detectFaces || config.detectSaliency {
                AppLogger.vision.info("👁️ Magic Fix: Starting Vision Orchestrator (Unified Pipeline)...")
                do {
                    // ROBUSTNESS: Add timeout (5 minutes max for vision analysis)
                    return try await withTimeout(seconds: 300.0) {
                        try await ServiceContainer.shared.visionOrchestrator.analyze(videoURL: clip.url, config: config)
                    }
                } catch {
                    AppLogger.vision.error("Vision pipeline failed: \(error)")
                    return nil
                }
            }
            return nil
        }.value

        // 1. Audio Enhancement (Primary Priority)
        // Enhance audio FIRST so that transcription and silence detection use clean audio
        if options.enhanceAudio {
            try Task.checkCancellation()
            processingStatus = "🎙️ Enhancing audio first..."
            await enhanceAudioFirst(for: clip)
            updateTransactionProgress(transactionId, progress: 0.2)
        }

        // Ensure Text Scan finishes before moving to visuals/metrics if needed,
        // or just let it finish. But to be safe and "Beating Industry Standard" implies robust + fast.
        // We'll await it before completing visual effects later, or just let it run DETACHED if it's truly independent?
        // Let's await it at the end of the function to ensure "Magic Fix Completed" actually means it's done.

        // Refresh clip state after potential audio enhancement
        guard let enhancedClipId = Optional(clip.id), let preAnalysisClip = getClip(by: enhancedClipId) else { return }

        // 2. Generate Captions if needed (Using enhanced audio if available)
        if (options.generateCaptions || options.removeFillers || options.autoEnhance) && preAnalysisClip.captions.isEmpty {
             try Task.checkCancellation()
             processingStatus = "🎤 Transcribing audio..."
             do {
                 // ROBUSTNESS: Add timeout (10 minutes max for transcription)
                 // CRITICAL FIX: Pass transaction ID so caption generation doesn't create duplicate transaction
                 _ = try await withTimeout(seconds: 600.0) {
                     try await self.generateCaptions(for: preAnalysisClip, transactionId: transactionId)
                 }
             } catch is CancellationError {
                 throw CancellationError()
             } catch {
                 AppLogger.project.warning("Magic Fix: Caption generation failed (timeout or error): \(error.localizedDescription). Some features like Filler Removal may be skipped.")
             }
        }
        updateTransactionProgress(transactionId, progress: 0.4)

        // Refresh clip again for analysis
        guard let readyForCutsClip = getClip(by: preAnalysisClip.id) else { return }

        do {
            // 3. Analyis and Cuts (Silence & Fillers)
            // Now runs on clean audio + accurate captions
            try Task.checkCancellation()
            processingStatus = "✂️ Analyzing for cuts (Silence & Fillers)..."
            try await processCutsAndSmoothing(for: readyForCutsClip, options: options, transactionId: transactionId)
            updateTransactionProgress(transactionId, progress: 0.6)

            // Refresh clip for final steps
            guard let visualClip = getClip(by: readyForCutsClip.id) else { return }

            // Await concurrent vision analysis (Unified Pipeline)
            let visionResult = await visionTask

            // 4. Visual Enhancements
            // CRITICAL FIX: Pass transaction ID so visual effects can bypass guards
            try Task.checkCancellation()
            try await applyVisualEffects(to: visualClip, options: options, visionResult: visionResult, transactionId: transactionId)

            // 5. AI & Generative Features
            // ROBUSTNESS: Add timeout for AI operations (2 minutes max)
            // CRITICAL FIX: Pass transaction ID
            try Task.checkCancellation()
            try await withTimeout(seconds: 120.0) {
                try await self.applyAIGenerativeFeatures(to: visualClip, options: options, transactionId: transactionId)
            }

            // Wait for background analysis - Already awaited above

            updateTransactionProgress(transactionId, progress: 1.0)
            processingStatus = "✅ Magic Fix Completed"
            ServiceContainer.shared.toastManager.show("✨ Magic Fix Completed", type: .info)
            AppLogger.project.info("✨ Magic Fix: One-click flow finished successfully")
        } catch is CancellationError {
            AppLogger.project.info("✨ Magic Fix: Cancelled by user")
            // Transaction will be ended by defer block
            self.processingStatus = nil
            self.updateTransactionProgress(transactionId, progress: 0.0)
        } catch {
            AppLogger.project.error("❌ Magic Fix CRITICAL FAILURE: \(error)")
            processingStatus = "❌ Failed"
            ServiceContainer.shared.toastManager.show("Magic Fix failed: \(error.localizedDescription)", type: .error)
            AppLogger.project.error("✨ Magic Fix: Error during orchestration: \(error)")
        }
    }

        // Store task for cancellation
        setProcessingTask(task)

        // Await task completion (errors are handled inside the task)
        do {
            try await task.value
        } catch {
            // Task errors are already handled in the task's catch block
            AppLogger.project.info("✨ Magic Fix: Task completed with error: \(error)")
        }
    }

    // MARK: - Magic Fix Modular Helpers

    private func processCutsAndSmoothing(for clip: VideoClip, options: MagicFixOptions, transactionId: UUID) async throws {
        AppLogger.project.info("✨ Magic Fix: Calling MagicFixService.applyMagicFix for cuts...")
        let keepRanges = try await MagicFixService.applyMagicFix(
            to: clip,
            options: options,
            progressHandler: { progressPercent, _ in
                let subProgress = Double(progressPercent) / 100.0
                Task { @MainActor in
                    self.updateTransactionProgress(transactionId, progress: 0.3 + (subProgress * 0.3)) // 30% -> 60%
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

    private func applyVisualEffects(to clip: VideoClip, options: MagicFixOptions, visionResult: VisionAnalysisResult? = nil, transactionId: UUID) async throws {
        // 1. Apply Vision Results (if available)
        if let result = visionResult {
             // A. Privacy (Text)
             // CRITICAL FIX: Pass transaction ID so privacy regions can be updated during processing
             if !result.privacyRegions.isEmpty {
                 await MainActor.run {
                     self.updateClipPrivacyRegions(clipId: clip.id, regions: result.privacyRegions, transactionId: transactionId)
                     ServiceContainer.shared.toastManager.show("🔒 Applied \(result.privacyRegions.count) privacy blurs (Unified)")
                 }
             }

             // B. Geometry (Smart Crop / Auto Frame)
             // CRITICAL FIX: Pass transaction ID so these operations can bypass guards
             if options.smartCrop && !result.saliency.isEmpty {
                 await applySmartCropFromAnalysis(clip: clip, analysis: result.saliency, transactionId: transactionId)
             } else if options.autoFraming && !result.faces.isEmpty {
                 await applyAutoFramingFromAnalysis(clip: clip, analysis: result.faces, transactionId: transactionId)
             }
        } else {
             // Fallback to legacy serial execution if orchestrator failed or wasn't used
             // (Logic moved from here previously)
             // ... actually I removed text scan.
             // But Smart Crop / Auto Framing legacy calls:
             // CRITICAL FIX: Pass transaction ID
             if options.smartCrop {
                 await applySmartCrop(to: clip, transactionId: transactionId)
             } else if options.autoFraming {
                 await applyAutoFraming(to: clip, transactionId: transactionId)
             }
        }

        updateTransactionProgress(transactionId, progress: 0.8)

        // 3. Color (Correction -> Grading)
        // ... (Rest of function)

        // Auto Enhance (Correction/White Balance)
        // Validated Order: Correct the image FIRST to remove casts, then apply stylistic grading.
        // CRITICAL FIX: Pass transaction ID so effect can be applied during processing
        if options.autoEnhance {
            processingStatus = "🪄 Enhancing visuals..."
            self.applyEffect(to: clip, effect: VideoEffect(type: .autoEnhance), transactionId: transactionId)
        }

        // Color Grade (Styling/Mood)
        // CRITICAL FIX: Pass transaction ID
        if options.analyzeMood {
            processingStatus = "🎨 Grading colors..."
            await applySmartColorGrade(to: clip, transactionId: transactionId)
        }
        updateTransactionProgress(transactionId, progress: 0.9)
    }

    private func applyAIGenerativeFeatures(to clip: VideoClip, options: MagicFixOptions, transactionId: UUID) async throws {
        if options.magicRemovePeople || options.generativeStyle {
            processingStatus = "🤖 Running AI Generative models..."
            // CRITICAL FIX: Pass transaction ID to AI features
            if options.magicRemovePeople { await applyMagicRemove(to: clip, transactionId: transactionId) }
            if options.generativeStyle { await applyCinematicStyle(to: clip, transactionId: transactionId) }
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
