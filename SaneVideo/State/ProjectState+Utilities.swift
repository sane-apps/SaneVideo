//
//  ProjectState+Utilities.swift
//  SaneVideo
//
//  Consolidated from Transactions, Cancellation, Relinking, and Editing
//

import AVFoundation
import CoreMedia
import Foundation
import SwiftUI

// MARK: - Transaction Management

extension ProjectState {

    @discardableResult
    func beginTransaction() -> UUID {
        let transactionId = UUID()
        let wasProcessing = isProcessing
        processingTransactions.insert(transactionId)
        transactionProgress[transactionId] = 0.0

        if !wasProcessing {
            AppLogger.project.debug(
                "🔄 Transaction started: \(transactionId.uuidString.prefix(8))")
        }

        return transactionId
    }

    func endTransaction(_ transactionId: UUID) {
        let wasProcessing = isProcessing
        processingTransactions.remove(transactionId)
        transactionProgress.removeValue(forKey: transactionId)

        updateOverallProgress()

        if wasProcessing && !isProcessing {
            AppLogger.project.debug("✅ Transaction ended: \(transactionId.uuidString.prefix(8))")
            processingProgress = 1.0
            processingStatus = nil
        }
    }

    func isValidTransaction(_ transactionId: UUID?) -> Bool {
        guard let transactionId = transactionId else { return false }
        return processingTransactions.contains(transactionId)
    }

    func cancelAllTransactions() {
        let count = processingTransactions.count
        let transactionIds = Array(processingTransactions)
        processingTransactions.removeAll()
        transactionProgress.removeAll()
        processingProgress = 0.0
        processingStatus = nil

        if count > 0 {
            AppLogger.project.info("🚫 Cancelled \(count) active transaction(s)")
            for transactionId in transactionIds {
                AppLogger.project.debug(
                    "🚫 Cancelled transaction: \(transactionId.uuidString.prefix(8))")
            }
        }
    }

    func cancelTransaction(_ transactionId: UUID) {
        if processingTransactions.remove(transactionId) != nil {
            transactionProgress.removeValue(forKey: transactionId)
            updateOverallProgress()
            AppLogger.project.debug(
                "🚫 Cancelled transaction: \(transactionId.uuidString.prefix(8))")
        }
    }

    func updateTransactionProgress(_ transactionId: UUID, progress: Double) {
        guard processingTransactions.contains(transactionId) else { return }
        transactionProgress[transactionId] = max(0.0, min(1.0, progress))
        updateOverallProgress()
    }

    func getTransactionProgress(_ transactionId: UUID) -> Double? {
        return transactionProgress[transactionId]
    }

    private func updateOverallProgress() {
        guard !transactionProgress.isEmpty else {
            processingProgress = 0.0
            return
        }

        let totalProgress = transactionProgress.values.reduce(0.0, +)
        let averageProgress = totalProgress / Double(transactionProgress.count)
        processingProgress = averageProgress
    }

    var activeTransactionCount: Int {
        processingTransactions.count
    }

    func shouldBlockOperation(transactionId: UUID? = nil) -> Bool {
        if let transactionId = transactionId, isValidTransaction(transactionId) {
            return false
        }
        return isProcessing
    }
}

// MARK: - Cancellation

extension ProjectState {

    func cancelProcessing() async {
        currentProcessingTask?.cancel()
        currentProcessingTask = nil

        await MainActor.run {
            let activeCount = activeTransactionCount
            cancelAllTransactions()

            if activeCount > 0 {
                AppLogger.project.info("🚫 Cancelled \(activeCount) active transaction(s)")
                ServiceContainer.shared.toastManager.show("Operation cancelled", type: .info)
            }
        }
    }

    func cancelTransactionById(_ transactionId: UUID) async {
        await MainActor.run {
            if isValidTransaction(transactionId) {
                cancelTransaction(transactionId)
                AppLogger.project.info(
                    "🚫 Cancelled transaction: \(transactionId.uuidString.prefix(8))")
            }
        }
    }

    func setProcessingTask(_ task: Task<Void, Error>) {
        currentProcessingTask = task
    }
}

// MARK: - Relinking

extension ProjectState {

    func relinkClip(_ clip: VideoClip, to newURL: URL, transactionId: UUID? = nil) {
        guard !shouldBlockOperation(transactionId: transactionId) else { return }
        guard var project = currentProject else { return }

        var timeline = project.timeline
        var clipFound = false

        for (trackIndex, track) in timeline.tracks.enumerated() {
            if let index = track.clips.firstIndex(where: { $0.id == clip.id }) {
                if track.isLocked { return }

                registerUndo("Relink Clip")

                var mutableTrack = track
                mutableTrack.clips[index].url = newURL
                mutableTrack.clips[index].isMissing = false

                if let bookmarkData = try? ServiceContainer.shared.projectFileManager.createBookmark(
                    for: newURL) {
                    mutableTrack.clips[index].bookmarkData = bookmarkData
                }

                timeline.tracks[trackIndex] = mutableTrack
                clipFound = true
                break
            }
        }

        if clipFound {
            project.timeline = timeline
            currentProject = project
            saveProject(project)

            NotificationCenter.default.post(name: .clipUpdated, object: project)
            ServiceContainer.shared.toastManager.show("Clip relinked to new file", type: .success)
            AppLogger.project.info("Relinked clip \(clip.id) to \(newURL.lastPathComponent)")
        }
    }
}

// MARK: - Text-Based Editing

extension ProjectState {

    @MainActor
    func updateCaptions(_ newCaptions: [Caption], for clip: VideoClip) {
        guard let project = currentProject else { return }

        for (trackIndex, track) in project.timeline.tracks.enumerated() {
            if let clipIndex = track.clips.firstIndex(where: { $0.id == clip.id }) {
                var updatedClip = clip
                updatedClip.captions = newCaptions

                var tracks = project.timeline.tracks
                var clips = track.clips
                clips[clipIndex] = updatedClip
                tracks[trackIndex].clips = clips

                var updatedProject = project
                updatedProject.timeline.tracks = tracks

                self.currentProject = updatedProject
                saveProject(updatedProject)

                AppLogger.project.info(
                    "📝 ProjectState: Updated \(newCaptions.count) captions for clip \(clip.id)")
                return
            }
        }
    }

    @MainActor
    func removeRange(_ range: CMTimeRange, from clip: VideoClip, rippleDelete: Bool = false) {
        guard let project = currentProject else { return }

        registerUndo("Remove Range")

        for (trackIndex, track) in project.timeline.tracks.enumerated() {
            if let clipIndex = track.clips.firstIndex(where: { $0.id == clip.id }) {
                var updatedClip = clip

                updatedClip.addRemovedRange(range)

                updatedClip.captions = updatedClip.captions.compactMap { caption in
                    if caption.startTime >= range.start && caption.endTime <= range.end {
                        return nil
                    }
                    if caption.startTime < range.end && caption.endTime > range.start {
                        var adjusted = caption
                        if caption.startTime < range.start {
                            adjusted.endTime = min(caption.endTime, range.start)
                        } else {
                            adjusted.startTime = max(caption.startTime, range.end)
                            adjusted.endTime = caption.endTime
                        }
                        if adjusted.endTime > adjusted.startTime
                            && (adjusted.endTime.seconds - adjusted.startTime.seconds) > 0.1 {
                            return adjusted
                        }
                        return nil
                    }
                    if caption.startTime >= range.end {
                        var shifted = caption
                        shifted.startTime = CMTimeSubtract(caption.startTime, range.duration)
                        shifted.endTime = CMTimeSubtract(caption.endTime, range.duration)
                        return shifted
                    }
                    return caption
                }

                var tracks = project.timeline.tracks
                var clips = track.clips
                clips[clipIndex] = updatedClip

                if rippleDelete {
                    let removedDurationCM = range.duration
                    for i in (clipIndex + 1)..<clips.count {
                        clips[i].startTime = CMTimeSubtract(clips[i].startTime, removedDurationCM)
                    }
                }

                tracks[trackIndex].clips = clips

                var updatedProject = project
                updatedProject.timeline.tracks = tracks
                recalculateStartTimes(in: &updatedProject.timeline)

                self.currentProject = updatedProject
                saveProject(updatedProject)

                AppLogger.project.info(
                    "✂️ ProjectState: Removed range \(range.start.seconds)-\(range.end.seconds) from clip \(clip.id) (ripple: \(rippleDelete))"
                )

                NotificationCenter.default.post(name: .clipAddedToTimeline, object: updatedProject)
                return
            }
        }
    }

    @MainActor
    func textRangeToTimeRange(_ textRange: NSRange, in clip: VideoClip) -> CMTimeRange? {
        struct WordSegment {
            let text: String
            let startTime: CMTime
            let endTime: CMTime
            let offset: Int
        }

        var wordSegments: [WordSegment] = []
        var currentOffset = 0

        for caption in clip.captions.sorted(by: { $0.startTime.seconds < $1.startTime.seconds }) {
            if let words = caption.words, !words.isEmpty {
                for word in words {
                    wordSegments.append(
                        WordSegment(
                            text: word.text,
                            startTime: CMTime(seconds: word.start, preferredTimescale: 600),
                            endTime: CMTime(seconds: word.end, preferredTimescale: 600),
                            offset: currentOffset
                        ))
                    currentOffset += word.text.count + 1
                }
            } else {
                let words = caption.text.split(separator: " ")
                guard !words.isEmpty else { continue }
                let wordDuration =
                    (caption.endTime.seconds - caption.startTime.seconds) / Double(words.count)

                for (index, word) in words.enumerated() {
                    let startTime = caption.startTime.seconds + (Double(index) * wordDuration)
                    let endTime = startTime + wordDuration
                    wordSegments.append(
                        WordSegment(
                            text: String(word),
                            startTime: CMTime(seconds: startTime, preferredTimescale: 600),
                            endTime: CMTime(seconds: endTime, preferredTimescale: 600),
                            offset: currentOffset
                        ))
                    currentOffset += word.count + 1
                }
            }
        }

        guard textRange.length > 0 else {
            AppLogger.project.warning("Empty text range provided")
            return nil
        }

        guard
            let startSegment = wordSegments.first(where: {
                $0.offset <= textRange.location && $0.offset + $0.text.count > textRange.location
            }),
            let endSegment = wordSegments.first(where: {
                $0.offset <= textRange.location + textRange.length
                    && $0.offset + $0.text.count >= textRange.location + textRange.length
            })
        else {
            AppLogger.project.warning(
                "Could not map text range to time range (text range: \(textRange.location)-\(textRange.location + textRange.length))"
            )
            ServiceContainer.shared.toastManager.show(
                "Could not find time range for text selection", type: .error)
            return nil
        }

        return CMTimeRange(
            start: startSegment.startTime,
            duration: CMTimeSubtract(endSegment.endTime, startSegment.startTime))
    }
}
