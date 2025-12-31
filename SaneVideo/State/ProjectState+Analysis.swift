//
//  ProjectState+Analysis.swift
//  SaneVideo
//
//  Extracted from SmartFeatures: Gesture detection, Privacy blur, Audio analysis, Captions
//

import AVFoundation
import CoreMedia
import Foundation

// MARK: - Gesture Detection

extension ProjectState {

    func findGestures(in clip: VideoClip, transactionId: UUID? = nil) async {
        let localTransactionId = transactionId ?? beginTransaction()
        defer { endTransaction(localTransactionId) }

        guard !shouldBlockOperation(transactionId: localTransactionId) else { return }

        await MainActor.run {
            ServiceContainer.shared.toastManager.show("Scanning for gestures...")
        }

        defer {
            Task { @MainActor in self.isProcessing = false }
        }

        do {
            let bodyService = ServiceContainer.shared.bodyPoseService

            let gestures = try await bodyService.detectGestures(
                in: clip.url,
                gestures: BodyGesture.allCases,
                sampleInterval: 0.5
            )

            if gestures.isEmpty {
                await MainActor.run {
                    ServiceContainer.shared.toastManager.show("No gestures detected", type: .info)
                }
                return
            }

            var gestureCount: [BodyGesture: Int] = [:]
            for (gesture, _) in gestures {
                gestureCount[gesture, default: 0] += 1
            }

            let summary = gestureCount.map { "\($0.key.rawValue): \($0.value)" }.joined(separator: ", ")

            AppLogger.vision.info("Found gestures: \(summary)")
            for (gesture, time) in gestures {
                AppLogger.vision.debug("  \(gesture.rawValue) at \(time.seconds)s")
            }

            await MainActor.run {
                ServiceContainer.shared.toastManager.show("Found \(gestures.count) gestures: \(summary)")
            }

        } catch {
            AppLogger.project.error("Gesture detection failed: \(error)")
            await MainActor.run {
                ServiceContainer.shared.toastManager.show("Gesture detection failed", type: .error)
            }
        }
    }
}

// MARK: - Privacy Blur

extension ProjectState {

    func applyPrivacyBlur(to clip: VideoClip, transactionId: UUID? = nil) async {
        let localTransactionId = transactionId ?? beginTransaction()
        defer { endTransaction(localTransactionId) }

        guard !shouldBlockOperation(transactionId: localTransactionId) else { return }

        await MainActor.run {
            ServiceContainer.shared.toastManager.show("Detecting sensitive text...")
        }

        defer {
            Task { @MainActor in self.isProcessing = false }
        }

        do {
            let textService = ServiceContainer.shared.textRecognitionService

            let allText = try await textService.scanVideoForText(
                videoURL: clip.url,
                sampleInterval: 1.0
            )

            let sensitiveCount = allText.filter { text in
                let content = text.text
                return content.contains("@") || content.filter { $0.isNumber }.count >= 7
                    || content.contains("http")
            }.count

            if sensitiveCount == 0 {
                await MainActor.run {
                    ServiceContainer.shared.toastManager.show("No sensitive text found", type: .info)
                }
                return
            }

            AppLogger.vision.info("Found \(sensitiveCount) sensitive text regions")

            await MainActor.run {
                var privacyRegions: [PrivacyRegion] = []

                for item in allText {
                    let content = item.text
                    let isSensitive =
                        content.contains("@") || content.filter { $0.isNumber }.count >= 7
                        || content.contains("http")

                    if isSensitive {
                        let region = PrivacyRegion(
                            timeRange: CMTimeRange(
                                start: item.time, duration: CMTime(seconds: 1.0, preferredTimescale: 600)),
                            frame: item.boundingBox
                        )
                        privacyRegions.append(region)
                    }
                }

                self.updateClipPrivacyRegions(clipId: clip.id, regions: privacyRegions)
                ServiceContainer.shared.toastManager.show(
                    "Applied \(privacyRegions.count) privacy blurs")
            }

        } catch {
            AppLogger.project.error("Privacy blur failed: \(error)")
            await MainActor.run {
                ServiceContainer.shared.toastManager.show("Text detection failed", type: .error)
            }
        }
    }

    func updateClipPrivacyRegions(clipId: UUID, regions: [PrivacyRegion], transactionId: UUID? = nil) {
        guard var project = currentProject else { return }
        guard !shouldBlockOperation(transactionId: transactionId) else { return }

        for (tIdx, track) in project.timeline.tracks.enumerated() {
            if let cIdx = track.clips.firstIndex(where: { $0.id == clipId }) {
                var updatedClip = track.clips[cIdx]
                updatedClip.privacyRegions = regions

                project.timeline.tracks[tIdx].clips[cIdx] = updatedClip
                currentProject = project
                return
            }
        }
    }
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
        ServiceContainer.shared.toastManager.show("Transcribing audio...")

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
                            ServiceContainer.shared.toastManager.show("Finishing transcription...")
                        } else {
                            let etaText = eta > 60 ? "\(eta / 60)m \(eta % 60)s" : "\(eta)s"
                            self.processingStatus = "Transcribing... \(chunk)/\(total)"
                            ServiceContainer.shared.toastManager.show(
                                "Transcribing... \(chunk)/\(total) (~\(etaText) remaining)")
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
}
