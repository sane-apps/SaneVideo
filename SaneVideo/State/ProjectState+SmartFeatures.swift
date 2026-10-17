import AVFoundation
import Foundation

// MARK: - Magic Fix

extension ProjectState {

    // MARK: - Reset Magic Fix

    /// Resets all Magic Fix results for a clip and optionally regenerates with current options
    /// - Parameters:
    ///   - regenerate: If true, automatically runs Magic Fix again with current options after clearing
    @MainActor func resetMagicFix(for clip: VideoClip, regenerate: Bool = true) async {
        guard var project = currentProject else { return }

        registerUndo("Reset Clean Up")

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

        updatedClip.removedRanges = [] // Clear silence/filler cuts
        updatedClip.useSmoothCutForRemovals = false
        updatedClip.captions = []
        updatedClip.enhancedAudioURL = nil
        updatedClip.isVoiceIsolationEnabled = false
        updatedClip.isGatingEnabled = false

        project.timeline.tracks[trackIndex].clips[clipIndex] = updatedClip
        currentProject = project
        saveProject(project)

        AppLogger.project.info("✨ Reset Magic Fix for clip \(clip.id)")

        if regenerate {
            guard let resetClip = getClip(by: clip.id) else {
                ServiceContainer.shared.toastManager.show("⚠️ Could not find clip after reset", type: .error)
                return
            }

            ServiceContainer.shared.toastManager.show("Running Clean Up again with these settings...", type: .info)
            await performMagicFix(for: resetClip, options: magicFixOptions)
        } else {
            ServiceContainer.shared.toastManager.show("Clean Up undone", type: .info)
        }
    }

    func hasMagicFixResults(for clip: VideoClip) -> Bool {
        return !clip.removedRanges.isEmpty ||
               !clip.captions.isEmpty ||
               clip.enhancedAudioURL != nil ||
               clip.isVoiceIsolationEnabled ||
               clip.isGatingEnabled ||
               clip.useSmoothCutForRemovals
    }

    /// - Parameters:
    ///   - isBatchOperation: When true, skips creating undo groups and setting currentProcessingTask
    ///                       (batch caller handles these at the batch level)
    func performMagicFix(for clip: VideoClip, options: MagicFixOptions, isBatchOperation: Bool = false) async {
        guard currentProject != nil else { return }

        let transactionId = beginTransaction()
        defer { endTransaction(transactionId) }

        // Standalone runs get their own undo group; batches use one "Magic Fix All" group.
        if !isBatchOperation {
            beginUndoGroup("Clean Up")
        }
        defer {
            if !isBatchOperation {
                endUndoGroup()
            }
        }

        let task = Task { @MainActor [weak self] in
            guard let self = self else { return }

            self.updateTransactionProgress(transactionId, progress: 0.0)
            self.processingStatus = "Cleaning up..."

            let startTime = Date()
            let performanceMetrics = ServiceContainer.shared.performanceMetrics

            AppLogger.project.info(
                "✨ Magic Fix: Starting for clip \(clip.id) (\(clip.url.lastPathComponent))")

            defer {
                let duration = Date().timeIntervalSince(startTime)
                let optionsDescription =
                    "\(options.removeSilence ? "silence " : "")\(options.removeFillers ? "fillers" : "")"
                performanceMetrics.recordOperation(
                    name: "Clean Up",
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

            if await MagicFixService.shouldAttemptAudioEnhancement(for: clip, options: options) {
                try Task.checkCancellation()
                do {
                    try await withTimeout(seconds: 600.0) {
                        try await self.enhanceAudioFirst(for: clip)
                    }
                    self.updateTransactionProgress(transactionId, progress: 0.2)
                } catch is CancellationError {
                    throw CancellationError()
                } catch {
                    AppLogger.project.warning("⚠️ Magic Fix: Audio enhancement failed: \(error.localizedDescription)")
                    // Keep going: the other Magic Fix steps still help without enhanced audio.
                }
            } else if options.enhanceAudio {
                AppLogger.project.info("✨ Magic Fix: Skipping audio enhancement — no audio track")
            }

            // The clip may have been deleted during processing.
            guard let enhancedClipId = Optional(clip.id),
                  let preAnalysisClip = getClip(by: enhancedClipId)
            else {
                AppLogger.project.warning("⚠️ Magic Fix: Clip \(clip.id) no longer exists, aborting")
                return
            }

            if (options.generateCaptions || options.removeFillers)
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

                updateTransactionProgress(transactionId, progress: 1.0)
                processingStatus = "Clean Up done"
                ServiceContainer.shared.toastManager.show("Clean Up done", type: .info)
                AppLogger.project.info("✨ Magic Fix: One-click flow finished successfully")

                // Reload the composition: StateChangePipeline watches only track structure, not clip.removedRanges, so the cuts would not show.
                if let project = self.currentProject {
                    ServiceContainer.shared.appState.playbackState.loadProject(project, forceReload: true)
                    // Start from the beginning so the user can review the cuts.
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
                    "Clean Up failed: \(error.localizedDescription)", type: .error)
                AppLogger.project.error("✨ Magic Fix: Error during orchestration: \(error)")
            }
        }

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
                self.registerUndo("Clean Up")
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
                        "Clean Up made \(cutCount) cut\(cutCount == 1 ? "" : "s")")
                }
            }
        }
    }

    private func enhanceAudioFirst(for clip: VideoClip) async throws {
        try Task.checkCancellation()

        // Note: processingStatus is updated with progress % in enhanceAudio's callback
        await enhanceAudio(for: clip)

        // enhanceAudio does not throw, so check that enhancedAudioURL was set.
        guard let updatedClip = getClip(by: clip.id),
              updatedClip.enhancedAudioURL != nil else {
            throw NSError(
                domain: "ProjectState",
                code: -1,
                userInfo: [NSLocalizedDescriptionKey: "Audio enhancement completed but enhanced URL was not set"]
            )
        }
    }

    private func updateClipRemovals(clipId: UUID, removedRanges: [CodableTimeRange]) {
        guard var project = currentProject else { return }
        for (tIdx, track) in project.timeline.tracks.enumerated() {
            if let cIdx = track.clips.firstIndex(where: { $0.id == clipId }) {
                var clip = track.clips[cIdx]
                clip.removedRanges = removedRanges
                registerUndo("Clean Up")
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
