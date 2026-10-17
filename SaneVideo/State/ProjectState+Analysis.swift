// Extracted from SmartFeatures: Gesture detection, Privacy blur, Audio analysis, Captions

import AVFoundation
import CoreMedia
import Foundation

// MARK: - Gesture Detection

extension ProjectState {

}

// MARK: - Privacy Blur

extension ProjectState {

}

// MARK: - Audio Analysis (Highlights)

extension ProjectState {

    func findHighlights(in clip: VideoClip, transactionId: UUID? = nil) async {
        let localTransactionId = transactionId ?? beginTransaction()
        defer { endTransaction(localTransactionId) }

        guard !shouldBlockOperation(transactionId: localTransactionId) else { return }

        await MainActor.run {
            ServiceContainer.shared.toastManager.show("Scanning audio for highlights...")
        }

        defer {
            Task { @MainActor in self.isProcessing = false }
        }

        do {
            let soundService = ServiceContainer.shared.soundAnalysisService

            let highlights = try await soundService.findHighlights(in: clip.url)

            if highlights.isEmpty {
                await MainActor.run {
                    ServiceContainer.shared.toastManager.show(
                        "No highlights found (applause, laughter)", type: .info)
                }
                return
            }

            var typeCount: [AudioLabel: Int] = [:]
            for highlight in highlights {
                typeCount[highlight.label, default: 0] += 1
            }

            let summary = typeCount.map { "\($0.key.displayName): \($0.value)" }.joined(separator: ", ")

            AppLogger.audio.info("Found highlights: \(summary)")
            for highlight in highlights {
                AppLogger.audio.debug(
                    "  \(highlight.label.displayName) at \(highlight.timeRange.start.seconds)s")
            }

            await MainActor.run {
                ServiceContainer.shared.toastManager.show(
                    "Found \(highlights.count) highlights: \(summary)")
            }

        } catch {
            AppLogger.project.error("Highlight detection failed: \(error)")
            await MainActor.run {
                ServiceContainer.shared.toastManager.show("Audio analysis failed", type: .error)
            }
        }
    }
}

// MARK: - Captions & Transcription

extension ProjectState {

    func generateCaptions(for clip: VideoClip, transactionId: UUID? = nil) async throws -> Int {
        guard currentProject != nil else { return 0 }

        let localTransactionId = transactionId ?? beginTransaction()
        defer { endTransaction(localTransactionId) }

        self.processingStatus = "Transcribing audio..."
        self.processingProgress = 0.0
        // Only use processingStatus for progress - no toast for start (reduces notification spam)

        AppLogger.project.info(
            "ProjectState: Requesting caption generation for clip \(clip.id)")
        let tracker = ProgressTracker(interval: 3.0)
        let coordinator = ServiceContainer.shared.transcriptionCoordinator

        do {
            let captions = try await coordinator.generateCaptions(for: clip.url) { chunk, total, eta in
                if tracker.shouldUpdate() || chunk == 1 || chunk == total {
                    Task { @MainActor in
                        let percent = Double(chunk) / Double(total)
                        self.processingProgress = percent

                        if chunk == total {
                            self.processingStatus = "Finishing transcription..."
                            // No toast for progress - use processingStatus only
                        } else {
                            let etaText = eta > 60 ? "\(eta / 60)m \(eta % 60)s" : "\(eta)s"
                            self.processingStatus = "Transcribing... \(chunk)/\(total) (~\(etaText) remaining)"
                            // No toast for progress - use processingStatus only
                        }
                    }
                }
            }

            await MainActor.run {
                AppLogger.project.info(
                    "ProjectState: Received \(captions.count) captions. Applying to clip...")
                self.applyCaptions(to: clip, captions: captions)
                ServiceContainer.shared.toastManager.show("Generated \(captions.count) captions!")
            }
            return captions.count
        } catch {
            AppLogger.project.error(
                "ProjectState: Caption generation failed: \(error.localizedDescription)")
            await MainActor.run {
                ServiceContainer.shared.toastManager.show("Caption generation failed", type: .error)
            }
            throw error
        }
    }

    func applyCaptions(to clip: VideoClip, captions: [Caption]) {
        guard var project = currentProject else {
            AppLogger.project.error("ProjectState: applyCaptions failed - currentProject is nil")
            return
        }

        for (tIdx, track) in project.timeline.tracks.enumerated() {
            if let cIdx = track.clips.firstIndex(where: { $0.id == clip.id }) {
                AppLogger.project.info(
                    "ProjectState: Found clip in track \(tIdx) at index \(cIdx). Setting \(captions.count) captions.")
                var updatedClip = track.clips[cIdx]
                updatedClip.captions = captions
                registerUndo("Update Captions")
                project.timeline.tracks[tIdx].clips[cIdx] = updatedClip
                currentProject = project
                saveProject(project)
                return
            }
        }
        AppLogger.project.warning(
            "ProjectState: applyCaptions could not find clip \(clip.id) in any track")
    }

    func updateCaptions(for clip: VideoClip, newCaptions: [Caption]) {
        applyCaptions(to: clip, captions: newCaptions)
    }

    func applyTranscriptCorrections(from url: URL, to clip: VideoClip) throws {
        let payload = try TranscriptImportParser.parseFile(at: url)

        switch payload {
        case let .captions(captions):
            applyCaptions(to: clip, captions: captions)
        case let .timestampedLines(lines):
            let corrected = mergeTimestampedTranscriptLines(lines, into: clip.captions)
            applyCaptions(to: clip, captions: corrected)
        }
    }

    private func mergeTimestampedTranscriptLines(
        _ lines: [TimestampedTranscriptLine],
        into captions: [Caption]
    ) -> [Caption] {
        guard !captions.isEmpty, !lines.isEmpty else { return captions }

        let sortedLines = lines.sorted { $0.startTime < $1.startTime }
        var updatedCaptions = captions
        var lineIndex = 0

        for index in updatedCaptions.indices {
            let captionStart = updatedCaptions[index].startTime.seconds

            while lineIndex + 1 < sortedLines.count {
                let currentDelta = abs(sortedLines[lineIndex].startTime.seconds - captionStart)
                let nextDelta = abs(sortedLines[lineIndex + 1].startTime.seconds - captionStart)
                if nextDelta > currentDelta {
                    break
                }
                lineIndex += 1
            }

            let bestMatch = sortedLines[lineIndex]
            let delta = abs(bestMatch.startTime.seconds - captionStart)
            guard delta <= 1.5 else { continue }

            let cleanedText = bestMatch.text.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !cleanedText.isEmpty else { continue }
            updatedCaptions[index].text = cleanedText
        }

        return updatedCaptions
    }
}
