//
//  ProjectState+BatchOperations.swift
//  SaneVideo
//
//  Batch operations using BatchCoordinator for parallel processing
//  Moves business logic out of View layer
//

import Foundation

extension ProjectState {
    // MARK: - Batch Operations

    /// Perform Magic Fix on all clips in the current project (parallelized)
    /// - Parameter options: Magic Fix options to apply
    /// - Returns: Results for each clip (success/failure)
    func performMagicFixAll(options: MagicFixOptions) async -> [BatchItemResult<VideoClip>] {
        guard let project = currentProject else { return [] }

        // Collect all clips
        let allClips = project.timeline.tracks.flatMap { $0.clips }
        guard !allClips.isEmpty else { return [] }

        // Use transaction for the entire batch operation
        let batchTransactionId = beginTransaction()
        defer { endTransaction(batchTransactionId) }

        processingStatus = "✨ Magic Fix All: Processing \(allClips.count) clips..."
        processingProgress = 0.0

        // Execute batch operation with parallel processing
        let results = await BatchCoordinator.execute(
            items: allClips,
            config: .default, // 4 concurrent workers
            operation: { clip, index in
                // Update progress
                await MainActor.run {
                    self.processingStatus = "✨ Magic Fix (\(index + 1)/\(allClips.count)): \(clip.url.lastPathComponent)"
                    self.processingProgress = Double(index) / Double(allClips.count)
                }

                // Perform Magic Fix (it will create its own transaction, which is fine)
                // The batch transaction ensures the UI shows processing state
                await self.performMagicFix(for: clip, options: options)
            },
            progressHandler: { @Sendable completed, total in
                Task { @MainActor in
                    self.processingProgress = Double(completed) / Double(total)
                }
            }
        )

        // Summary
        let successCount = results.filter { $0.success }.count
        let failureCount = results.filter { !$0.success }.count

        processingStatus = "✅ Magic Fix All: \(successCount) succeeded, \(failureCount) failed"
        processingProgress = 1.0

        if failureCount > 0 {
            ServiceContainer.shared.toastManager.show(
                "Magic Fix All: \(successCount) succeeded, \(failureCount) failed",
                type: failureCount == allClips.count ? .error : .info
            )
        } else {
            ServiceContainer.shared.toastManager.show(
                "✅ Magic Fix All: All \(successCount) clips processed",
                type: .success
            )
        }

        return results
    }

    /// Generate captions for all clips in the current project (parallelized)
    /// - Returns: Results for each clip (success/failure)
    func generateCaptionsAll() async -> [BatchItemResult<VideoClip>] {
        guard let project = currentProject else { return [] }

        // Collect all clips
        let allClips = project.timeline.tracks.flatMap { $0.clips }
        guard !allClips.isEmpty else { return [] }

        // Use transaction for the entire batch operation
        let batchTransactionId = beginTransaction()
        defer { endTransaction(batchTransactionId) }

        processingStatus = "🎤 Generating Captions: Processing \(allClips.count) clips..."
        processingProgress = 0.0

        // Execute batch operation with parallel processing
        let results = await BatchCoordinator.execute(
            items: allClips,
            config: .default, // 4 concurrent workers
            operation: { clip, index in
                // Update progress
                await MainActor.run {
                    self.processingStatus = "🎤 Generating Captions (\(index + 1)/\(allClips.count)): \(clip.url.lastPathComponent)"
                    self.processingProgress = Double(index) / Double(allClips.count)
                }

                // Generate captions
                // Pass nil transactionId so generateCaptions creates its own
                // (batch transaction is for UI state, individual operations have their own)
                do {
                    _ = try await self.generateCaptions(for: clip, transactionId: nil)
                } catch {
                    AppLogger.project.error("Generate All Captions: Failed for clip \(clip.id): \(error)")
                    throw error
                }
            },
            progressHandler: { @Sendable completed, total in
                Task { @MainActor in
                    self.processingProgress = Double(completed) / Double(total)
                }
            }
        )

        // Summary
        let successCount = results.filter { $0.success }.count
        let failureCount = results.filter { !$0.success }.count

        processingStatus = "✅ Captions Generated: \(successCount) succeeded, \(failureCount) failed"
        processingProgress = 1.0

        if failureCount > 0 {
            ServiceContainer.shared.toastManager.show(
                "Generate All Captions: \(successCount) succeeded, \(failureCount) failed",
                type: failureCount == allClips.count ? .error : .info
            )
        } else {
            ServiceContainer.shared.toastManager.show(
                "✅ Generated captions for all \(successCount) clips",
                type: .success
            )
        }

        return results
    }
}
