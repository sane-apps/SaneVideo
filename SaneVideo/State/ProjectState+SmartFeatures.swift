//
//  ProjectState+SmartFeatures.swift
//  SaneVideo
//
//  Consolidated from MagicFix, Analysis, and Transcription
//

import AVFoundation
import Foundation

// MARK: - Magic Fix

extension ProjectState {

    // MARK: - Reset Magic Fix

    /// Resets all Magic Fix results for a clip and optionally regenerates with current options
    /// - Parameters:
    ///   - clip: The clip to reset
    ///   - regenerate: If true, automatically runs Magic Fix again with current options after clearing
    @MainActor func resetMagicFix(for clip: VideoClip, regenerate: Bool = true) async {
        guard var project = currentProject else { return }

        registerUndo("Reset Magic Fix")

        // Find clip in timeline
        guard let trackIndex = project.timeline.tracks.firstIndex(where: {
            $0.clips.contains(where: { $0.id == clip.id })
        }),
        let clipIndex = project.timeline.tracks[trackIndex].clips.firstIndex(where: {
            $0.id == clip.id
        }) else {
            AppLogger.project.warning("⚠️ Reset Magic Fix: Clip not found in timeline")
            return
        }

        var updatedClip = project.timeline.tracks[trackIndex].clips[clipIndex]

        // Reset all Magic Fix modifications
        updatedClip.removedRanges = [] // Clear silence/filler cuts
        updatedClip.useSmoothCutForRemovals = false
        updatedClip.captions = [] // Clear generated captions
        updatedClip.enhancedAudioURL = nil // Clear audio enhancement
        updatedClip.isVoiceIsolationEnabled = false // Reset voice isolation
        updatedClip.isGatingEnabled = false // Reset AI gating

        // Remove Magic Fix visual effects (autoEnhance only - smartCrop/autoFraming are transforms, not effects)
        updatedClip.effects.removeAll { effect in
            effect.type == .autoEnhance
        }

        // Clear privacy regions added by Magic Fix
        updatedClip.privacyRegions = []

        // Clear smart crop and auto-framing transforms
        updatedClip.transform = .identity

        project.timeline.tracks[trackIndex].clips[clipIndex] = updatedClip
        currentProject = project
        saveProject(project)

        AppLogger.project.info("✨ Reset Magic Fix for clip \(clip.id)")

        // CRITICAL FIX: If regenerate is true, automatically run Magic Fix with current options
        if regenerate {
            // Get the updated clip after reset
            guard let resetClip = getClip(by: clip.id) else {
                ServiceContainer.shared.toastManager.show("⚠️ Could not find clip after reset", type: .error)
                return
            }

            ServiceContainer.shared.toastManager.show("🔄 Regenerating Magic Fix with current settings...", type: .info)
            await performMagicFix(for: resetClip, options: magicFixOptions)
        } else {
            ServiceContainer.shared.toastManager.show("🔄 Magic Fix results reset", type: .info)
        }
    }

    /// Checks if a clip has any Magic Fix results applied
    func hasMagicFixResults(for clip: VideoClip) -> Bool {
        return !clip.removedRanges.isEmpty ||
               !clip.captions.isEmpty ||
               clip.enhancedAudioURL != nil ||
               clip.isVoiceIsolationEnabled ||
               clip.isGatingEnabled ||
               clip.useSmoothCutForRemovals ||
               clip.effects.contains { $0.type == .autoEnhance } ||
               !clip.privacyRegions.isEmpty ||
               clip.transform != .identity // Smart crop/auto-framing modify transform
    }

    /// Performs Magic Fix on a single clip
    /// - Parameters:
    ///   - clip: The video clip to process
    ///   - options: Magic Fix options
    ///   - isBatchOperation: When true, skips creating undo groups and setting currentProcessingTask
    ///                       (batch caller handles these at the batch level)
    func performMagicFix(for clip: VideoClip, options: MagicFixOptions, isBatchOperation: Bool = false) async {
        guard currentProject != nil else { return }

        let transactionId = beginTransaction()
        defer { endTransaction(transactionId) }

        // Only create undo group for standalone operations, not batch
        // Batch operations use a single "Magic Fix All" undo group at the batch level
        if !isBatchOperation {
            beginUndoGroup("Magic Fix")
        }
        defer {
            if !isBatchOperation {
                endUndoGroup()
            }
        }

        let task = Task { @MainActor [weak self] in
            guard let self = self else { return }

            self.updateTransactionProgress(transactionId, progress: 0.0)
            self.processingStatus = "✨ Starting Magic Fix..."

            let startTime = Date()
            let performanceMetrics = ServiceContainer.shared.performanceMetrics

            AppLogger.project.info(
                "✨ Magic Fix: Starting for clip \(clip.id) (\(clip.url.lastPathComponent))")

            defer {
                let duration = Date().timeIntervalSince(startTime)
                let optionsDescription =
                    "\(options.removeSilence ? "silence " : "")\(options.removeFillers ? "fillers " : "")\(options.autoEnhance ? "enhance" : "")"
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

            try Task.checkCancellation()

            async let visionTask: VisionAnalysisResult? = await Task.detached(priority: .utility) {
                let config = VisionAnalysisConfig(
                    detectText: options.scanForText,
                    detectFaces: options.autoFraming,
                    detectSaliency: options.smartCrop,
                    detectPrivacy: options.scanForText
                )

                if config.detectText || config.detectFaces || config.detectSaliency {
                    AppLogger.vision.info(
                        "👁️ Magic Fix: Starting Vision Orchestrator (Unified Pipeline)...")
                    do {
                        return try await withTimeout(seconds: 300.0) {
                            try await ServiceContainer.shared.visionOrchestrator.analyze(
                                videoURL: clip.url, config: config)
                        }
                    } catch {
                        AppLogger.vision.error("Vision pipeline failed: \(error)")
                        return nil
                    }
                }
                return nil
            }.value

            if options.enhanceAudio {
                try Task.checkCancellation()
                do {
                    // CRITICAL FIX: Add timeout and proper error handling for audio enhancement
                    try await withTimeout(seconds: 600.0) {
                        try await self.enhanceAudioFirst(for: clip)
                    }
                    self.updateTransactionProgress(transactionId, progress: 0.2)
                } catch is CancellationError {
                    throw CancellationError()
                } catch {
                    AppLogger.project.warning("⚠️ Magic Fix: Audio enhancement failed: \(error.localizedDescription)")
                    // Continue execution - do not fail the whole process (graceful degradation)
                    // User can still benefit from other Magic Fix features
                }
            }

            // CRITICAL FIX: Verify clip still exists after audio enhancement
            // Clip might have been deleted during processing
            guard let enhancedClipId = Optional(clip.id),
                  let preAnalysisClip = getClip(by: enhancedClipId)
            else {
                AppLogger.project.warning("⚠️ Magic Fix: Clip \(clip.id) no longer exists, aborting")
                return
            }

            if (options.generateCaptions || options.removeFillers || options.autoEnhance)
                && preAnalysisClip.captions.isEmpty {
                try Task.checkCancellation()
                processingStatus = "🎤 Transcribing audio..."
                do {
                    _ = try await withTimeout(seconds: 600.0) {
                        try await self.generateCaptions(for: preAnalysisClip, transactionId: transactionId)
                    }
                } catch is CancellationError {
                    throw CancellationError()
                } catch {
                    AppLogger.project.warning(
                        "Magic Fix: Caption generation failed: \(error.localizedDescription)")
                }
            }
            updateTransactionProgress(transactionId, progress: 0.4)

            // CRITICAL FIX: Verify clip still exists before processing cuts
            guard let readyForCutsClip = getClip(by: preAnalysisClip.id) else {
                AppLogger.project.warning("⚠️ Magic Fix: Clip \(preAnalysisClip.id) no longer exists before cuts processing")
                return
            }

            do {
                try Task.checkCancellation()
                processingStatus = "✂️ Analyzing for cuts (Silence & Fillers)..."
                try await processCutsAndSmoothing(
                    for: readyForCutsClip, options: options, transactionId: transactionId)
                updateTransactionProgress(transactionId, progress: 0.6)

                // CRITICAL FIX: Verify clip still exists before applying visual effects
                guard let visualClip = getClip(by: readyForCutsClip.id) else {
                    AppLogger.project.warning("⚠️ Magic Fix: Clip \(readyForCutsClip.id) no longer exists before visual effects")
                    return
                }

                let visionResult = await visionTask

                try Task.checkCancellation()
                try await applyVisualEffects(
                    to: visualClip, options: options, visionResult: visionResult,
                    transactionId: transactionId)

                try Task.checkCancellation()
                try await withTimeout(seconds: 120.0) {
                    try await self.applyAIGenerativeFeatures(
                        to: visualClip, options: options, transactionId: transactionId)
                }

                updateTransactionProgress(transactionId, progress: 1.0)
                processingStatus = "✅ Magic Fix Completed"
                ServiceContainer.shared.toastManager.show("✨ Magic Fix Completed", type: .info)
                AppLogger.project.info("✨ Magic Fix: One-click flow finished successfully")

                // CRITICAL FIX (2026-01-01): Force composition reload to apply cuts
                // StateChangePipeline only watches timeline.tracks structure changes,
                // but clip.removedRanges is a property WITHIN a clip. Without this reload,
                // the old composition stays active without the cuts applied.
                if let project = self.currentProject {
                    ServiceContainer.shared.appState.playbackState.loadProject(project, forceReload: true)
                    // Reset playhead to start for better UX - user expects to review from beginning
                    ServiceContainer.shared.appState.playbackState.seek(to: .zero)
                }
            } catch is CancellationError {
                AppLogger.project.info("✨ Magic Fix: Cancelled by user")
                self.processingStatus = nil
                self.updateTransactionProgress(transactionId, progress: 0.0)
            } catch {
                AppLogger.project.error("❌ Magic Fix CRITICAL FAILURE: \(error)")
                processingStatus = "❌ Failed"
                ServiceContainer.shared.toastManager.show(
                    "Magic Fix failed: \(error.localizedDescription)", type: .error)
                AppLogger.project.error("✨ Magic Fix: Error during orchestration: \(error)")
            }
        }

        // Always store the task handle for cancellation support
        // Batch callers can still override via EditorLayoutView.magicFixTask
        setProcessingTask(task)

        do {
            try await task.value
        } catch {
            AppLogger.project.info("✨ Magic Fix: Task completed with error: \(error)")
        }
    }

    private func processCutsAndSmoothing(
        for clip: VideoClip, options: MagicFixOptions, transactionId: UUID
    ) async throws {
        AppLogger.project.info("✨ Magic Fix: Calling MagicFixService.applyMagicFix for cuts...")
        let keepRanges = try await MagicFixService.applyMagicFix(
            to: clip,
            options: options,
            progressHandler: { progressPercent, _ in
                let subProgress = Double(progressPercent) / 100.0
                Task { @MainActor in
                    self.updateTransactionProgress(transactionId, progress: 0.3 + (subProgress * 0.3))
                }
                AppLogger.project.debug("✨ Magic Fix Progress: \(progressPercent)%")
            }
        )
        AppLogger.project.info(
            "✨ Magic Fix: Received \(keepRanges.count) keep ranges from service")

        let removedRanges = MagicFixService.calculateRemovedRanges(
            from: keepRanges, duration: clip.duration)
        let codableRemovals = removedRanges.map { CodableTimeRange($0) }

        if codableRemovals != clip.removedRanges
            || options.smoothJumpCuts != clip.useSmoothCutForRemovals {
            await MainActor.run {
                self.registerUndo("Magic Fix (Cuts & Smoothing)")
                guard var project = self.currentProject else { return }

                if let index = project.timeline.tracks.firstIndex(where: {
                    $0.clips.contains(where: { $0.id == clip.id })
                }),
                    let clipIndex = project.timeline.tracks[index].clips.firstIndex(where: {
                        $0.id == clip.id
                    }) {
                    project.timeline.tracks[index].clips[clipIndex].removedRanges = codableRemovals
                    project.timeline.tracks[index].clips[clipIndex].useSmoothCutForRemovals =
                        options.smoothJumpCuts

                    self.currentProject = project
                    self.saveProject(project)
                }

                let cutCount = codableRemovals.count - clip.removedRanges.count
                if cutCount > 0 {
                    ServiceContainer.shared.toastManager.show(
                        "✅ Magically fixed: Added \(cutCount) cuts")
                }
            }
        }
    }

    private func enhanceAudioFirst(for clip: VideoClip) async throws {
        // CRITICAL FIX: Check for cancellation before starting audio enhancement
        try Task.checkCancellation()

        // Note: processingStatus is updated with progress % in enhanceAudio's callback
        await enhanceAudio(for: clip)

        // CRITICAL FIX: Verify enhancement succeeded by checking if enhancedAudioURL was set
        // enhanceAudio doesn't throw, so we need to check the result
        guard let updatedClip = getClip(by: clip.id),
              updatedClip.enhancedAudioURL != nil else {
            // If enhancement failed silently, throw to indicate failure
            throw NSError(
                domain: "ProjectState",
                code: -1,
                userInfo: [NSLocalizedDescriptionKey: "Audio enhancement completed but enhanced URL was not set"]
            )
        }
    }

    private func applyVisualEffects(
        to clip: VideoClip, options: MagicFixOptions, visionResult: VisionAnalysisResult? = nil,
        transactionId: UUID
    ) async throws {
        if let result = visionResult {
            if !result.privacyRegions.isEmpty {
                await MainActor.run {
                    self.updateClipPrivacyRegions(
                        clipId: clip.id, regions: result.privacyRegions, transactionId: transactionId)
                    ServiceContainer.shared.toastManager.show(
                        "🔒 Applied \(result.privacyRegions.count) privacy blurs (Unified)")
                }
            }

            if options.smartCrop && !result.saliency.isEmpty {
                await applySmartCropFromAnalysis(
                    clip: clip, analysis: result.saliency, transactionId: transactionId)
            } else if options.autoFraming && !result.faces.isEmpty {
                await applyAutoFramingFromAnalysis(
                    clip: clip, analysis: result.faces, transactionId: transactionId)
            }
        } else {
            if options.smartCrop {
                await applySmartCrop(to: clip, transactionId: transactionId)
            } else if options.autoFraming {
                await applyAutoFraming(to: clip, transactionId: transactionId)
            }
        }

        updateTransactionProgress(transactionId, progress: 0.8)

        if options.autoEnhance {
            processingStatus = "🪄 Enhancing visuals..."
            self.applyEffect(to: clip, effect: VideoEffect(type: .autoEnhance), transactionId: transactionId)
        }

        if options.analyzeMood {
            processingStatus = "🎨 Grading colors..."
            await applySmartColorGrade(to: clip, transactionId: transactionId)
        }
        updateTransactionProgress(transactionId, progress: 0.9)
    }

    private func applyAIGenerativeFeatures(
        to clip: VideoClip, options: MagicFixOptions, transactionId: UUID
    ) async throws {
        if options.magicRemovePeople || options.generativeStyle {
            processingStatus = "🤖 Running AI Generative models..."
            if options.magicRemovePeople {
                await applyMagicRemove(to: clip, transactionId: transactionId)
            }
            if options.generativeStyle {
                await applyCinematicStyle(to: clip, transactionId: transactionId)
            }
        }
    }

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
