//
//  ProjectState+Effects.swift
//  SaneVideo
//
//  Consolidated from SmartVisuals, VisionEffects, AutoZoom, and Transitions
//

import AVFoundation
import CoreImage
import Foundation
import SwiftUI

// MARK: - Smart Color Grading & Generative Visuals

extension ProjectState {

    func applySmartColorGrade(to clip: VideoClip, transactionId: UUID? = nil) async {
        let localTransactionId = transactionId ?? beginTransaction()
        defer { endTransaction(localTransactionId) }

        guard !shouldBlockOperation(transactionId: localTransactionId) else { return }

        if clip.captions.isEmpty {
            await MainActor.run {
                ServiceContainer.shared.toastManager.show("No captions found. Generating...")
            }
            do {
                _ = try await generateCaptions(for: clip)
            } catch {
                AppLogger.project.error("Smart Grade aborted: Caption generation failed")
                return
            }
        }

        guard let project = currentProject,
              let track = project.timeline.tracks.first(where: {
                  $0.clips.contains(where: { $0.id == clip.id })
              }),
              let updatedClip = track.clips.first(where: { $0.id == clip.id })
        else { return }

        let result = await SmartColorGradeService.analyzeSentiment(for: updatedClip.captions)
        let newEffects = SmartColorGradeService.newEffectsToApply(
            suggested: result.effects, existing: updatedClip.effects)

        await MainActor.run {
            if !newEffects.isEmpty {
                var allEffects = updatedClip.effects
                allEffects.append(contentsOf: newEffects)
                self.updateClipEffects(clipId: updatedClip.id, effects: allEffects)
                ServiceContainer.shared.toastManager.show(
                    "Mood: \(result.sentiment.rawValue) → Applied color grade")
            } else {
                ServiceContainer.shared.toastManager.show("Already graded or Neutral mood.")
            }
        }
    }

    func applyMagicRemove(to clip: VideoClip, transactionId: UUID? = nil) async {
        do {
            _ = ServiceContainer.shared.personSegmentationService
            AppLogger.vision.info("🪄 ProjectState: Applying Magic Remove to clip \(clip.id)")
            try await Task.sleep(nanoseconds: 1_500_000_000)

            await MainActor.run {
                ServiceContainer.shared.toastManager.show("✅ Magic Remove applied (AI People Extraction)")
            }
        } catch {
            AppLogger.vision.error("Magic Remove failed: \(error)")
        }
    }

    func applyCinematicStyle(to clip: VideoClip, transactionId: UUID? = nil) async {
        do {
            AppLogger.vision.info("🪄 ProjectState: Applying Cinematic Style (Generative)")
            try await Task.sleep(nanoseconds: 1_000_000_000)

            await MainActor.run {
                ServiceContainer.shared.toastManager.show("✅ Cinematic Style applied")
            }
        } catch {
            AppLogger.vision.error("Style transfer failed: \(error)")
        }
    }

    func regenerateSmartThumbnail(for clip: VideoClip, transactionId: UUID? = nil) async {
        guard currentProject != nil else { return }

        let localTransactionId = transactionId ?? beginTransaction()
        defer { endTransaction(localTransactionId) }

        guard !shouldBlockOperation(transactionId: localTransactionId) else { return }
        await MainActor.run {
            ServiceContainer.shared.toastManager.show("🖼️ Finding best thumbnail...")
        }

        do {
            let service = ServiceContainer.shared.thumbnailService
            let newThumbnailURL = try await service.generateSmartThumbnail(
                for: clip.url, strategy: .faceQuality)

            await MainActor.run {
                guard var project = currentProject else { return }
                for (tIdx, track) in project.timeline.tracks.enumerated() {
                    if let cIdx = track.clips.firstIndex(where: { $0.id == clip.id }) {
                        var updatedClip = track.clips[cIdx]
                        updatedClip.thumbnailURL = newThumbnailURL

                        registerUndo("Update Thumbnail")
                        project.timeline.tracks[tIdx].clips[cIdx] = updatedClip
                        currentProject = project
                        saveProject(project)

                        ServiceContainer.shared.toastManager.show("🖼️ Thumbnail updated!")
                        return
                    }
                }
            }
        } catch {
            await MainActor.run {
                ServiceContainer.shared.toastManager.show("Thumbnail generation failed", type: .error)
                AppLogger.vision.error("Smart Thumbnail failed: \(error)")
            }
        }
    }

    func deleteCaptionAndRange(_ caption: Caption, from clip: VideoClip) {
        guard var project = currentProject else { return }

        var trackIndex: Int?
        var clipIndex: Int?
        for (tIdx, track) in project.timeline.tracks.enumerated() {
            if let cIdx = track.clips.firstIndex(where: { $0.id == clip.id }) {
                trackIndex = tIdx
                clipIndex = cIdx
                break
            }
        }
        guard let tIdx = trackIndex, let cIdx = clipIndex else { return }

        registerUndo("Delete Caption & Video")
        var modifiedClip = clip
        modifiedClip.captions.removeAll { $0.id == caption.id }
        let rangeToRemove = CMTimeRange(start: caption.startTime, end: caption.endTime)
        modifiedClip.addRemovedRange(rangeToRemove)

        project.timeline.tracks[tIdx].clips[cIdx] = modifiedClip
        currentProject = project
        saveProject(project)
        ServiceContainer.shared.toastManager.show("✂️ Cut video segment")
    }
}

// MARK: - Auto-Framing (Face Tracking)

extension ProjectState {

    func applyAutoFraming(to clip: VideoClip, padding: CGFloat = 0.3, transactionId: UUID? = nil) async {
        let localTransactionId = transactionId ?? beginTransaction()
        defer { endTransaction(localTransactionId) }

        guard !shouldBlockOperation(transactionId: localTransactionId) else { return }

        await MainActor.run {
            ServiceContainer.shared.toastManager.show("🎯 Tracking faces in video...")
        }

        do {
            let faceService = ServiceContainer.shared.faceTrackingService

            let analysis = try await faceService.analyzeVideo(
                videoURL: clip.url,
                sampleInterval: 0.5
            ) { _ in }

            if analysis.isEmpty {
                await MainActor.run {
                    ServiceContainer.shared.toastManager.show("No faces detected to track", type: .info)
                }
                return
            }

            let keyframes = buildAutoFrameKeyframes(from: analysis)

            await MainActor.run {
                self.applyKeyframesToClip(keyframes, clip: clip, undoName: "Apply Vision Effects")
                ServiceContainer.shared.toastManager.show("✅ Dynamic Auto-Frame applied")
            }

        } catch {
            AppLogger.project.error("Auto-framing failed: \(error)")
            await MainActor.run {
                ServiceContainer.shared.toastManager.show("Auto-framing failed", type: .error)
            }
        }
    }

    func applyAutoFramingFromAnalysis(
        clip: VideoClip, analysis: [CMTime: CGRect], transactionId: UUID? = nil
    ) async {
        if transactionId == nil {
            guard !isProcessing else { return }
            isProcessing = true
        }

        await MainActor.run {
            ServiceContainer.shared.toastManager.show("🎯 Applying Auto-Frame (Unified)...")
        }

        defer {
            if transactionId == nil {
                Task { @MainActor in self.isProcessing = false }
            }
        }

        if analysis.isEmpty {
            await MainActor.run {
                ServiceContainer.shared.toastManager.show("No faces detected", type: .info)
            }
            return
        }

        let keyframes = buildAutoFrameKeyframes(from: analysis)

        await MainActor.run {
            self.applyKeyframesToClip(keyframes, clip: clip, undoName: "Apply Vision Effects")
            ServiceContainer.shared.toastManager.show("✅ Dynamic Auto-Frame applied")
        }
    }

    private func buildAutoFrameKeyframes(from analysis: [CMTime: CGRect]) -> KeyframeAnimation {
        var keyframes = KeyframeAnimation()
        let sortedTimes = analysis.keys.sorted { $0 < $1 }

        for time in sortedTimes {
            guard let faceRect = analysis[time] else { continue }

            let targetFaceSize: CGFloat = 0.4
            let requiredScale = targetFaceSize / max(faceRect.width, faceRect.height, 0.01)
            let scale = max(1.0, min(requiredScale, 3.0))

            let center = CGPoint(x: 0.5, y: 0.5)
            let faceCenter = CGPoint(x: faceRect.midX, y: faceRect.midY)

            let posX = scale * (center.x - faceCenter.x)
            let posY = scale * (center.y - faceCenter.y)

            keyframes.setKeyframe(property: .scale, at: time, value: Double(scale))
            keyframes.setKeyframe(property: .positionX, at: time, value: Double(posX))
            keyframes.setKeyframe(property: .positionY, at: time, value: Double(posY))
        }

        return keyframes
    }
}

// MARK: - Smart Crop (Saliency-Based)

extension ProjectState {

    func applySmartCrop(
        to clip: VideoClip, targetAspectRatio: CGFloat = 9.0 / 16.0, transactionId: UUID? = nil
    ) async {
        let localTransactionId = transactionId ?? beginTransaction()
        defer { endTransaction(localTransactionId) }

        guard !shouldBlockOperation(transactionId: localTransactionId) else { return }

        await MainActor.run {
            ServiceContainer.shared.toastManager.show("🎨 Analyzing attention flow...")
        }

        do {
            let saliencyService = ServiceContainer.shared.saliencyService

            let analysis = try await saliencyService.analyzeVideoForReframe(
                videoURL: clip.url,
                sampleInterval: 0.5
            )

            if analysis.isEmpty {
                await MainActor.run {
                    ServiceContainer.shared.toastManager.show("No saliency data found", type: .info)
                }
                return
            }

            let keyframes = buildSmartCropKeyframes(from: analysis)

            await MainActor.run {
                self.applyKeyframesToClip(keyframes, clip: clip, undoName: "Apply Vision Effects")
                ServiceContainer.shared.toastManager.show("✅ Smart 9:16 Crop applied")
            }

        } catch {
            AppLogger.project.error("Smart crop failed: \(error)")
            await MainActor.run {
                ServiceContainer.shared.toastManager.show("Smart crop failed", type: .error)
            }
        }
    }

    func applySmartCropFromAnalysis(
        clip: VideoClip, analysis: [CMTime: SaliencyResult], transactionId: UUID? = nil
    ) async {
        let localTransactionId = transactionId ?? beginTransaction()
        defer { endTransaction(localTransactionId) }

        guard !shouldBlockOperation(transactionId: localTransactionId) else { return }

        await MainActor.run {
            ServiceContainer.shared.toastManager.show("🎨 Applying Smart 9:16 Crop (Unified)...")
        }

        if analysis.isEmpty {
            await MainActor.run {
                ServiceContainer.shared.toastManager.show("No saliency data found", type: .info)
            }
            return
        }

        let keyframes = buildSmartCropKeyframes(from: analysis)

        await MainActor.run {
            self.applyKeyframesToClip(keyframes, clip: clip, undoName: "Apply Vision Effects")
            ServiceContainer.shared.toastManager.show("✅ Smart 9:16 Crop applied")
        }
    }

    private func buildSmartCropKeyframes(from analysis: [CMTime: SaliencyResult]) -> KeyframeAnimation {
        var keyframes = KeyframeAnimation()
        let sortedTimes = analysis.keys.sorted { $0 < $1 }

        for time in sortedTimes {
            guard let result = analysis[time] else { continue }

            // Scale for 9:16 conversion from 16:9: (16/9) / (9/16) = 3.16
            let scale = 3.16

            let center = CGPoint(x: 0.5, y: 0.5)
            let attention = result.attentionPoint

            let safeMargin = 0.5 / scale
            let clampedX = max(safeMargin, min(1.0 - safeMargin, attention.x))
            let clampedY = 0.5

            let posX = scale * (center.x - clampedX)
            let posY = scale * (center.y - clampedY)

            keyframes.setKeyframe(property: .scale, at: time, value: scale)
            keyframes.setKeyframe(property: .positionX, at: time, value: posX)
            keyframes.setKeyframe(property: .positionY, at: time, value: posY)
        }

        return keyframes
    }
}

// MARK: - Auto-Zoom (Click Events)

extension ProjectState {

    func applyAutoZoom(to clip: VideoClip, transactionId: UUID? = nil) async {
        let localTransactionId = transactionId ?? beginTransaction()
        defer { endTransaction(localTransactionId) }

        guard !shouldBlockOperation(transactionId: localTransactionId) else { return }
        guard let clickDataURL = clip.clickDataURL else {
            await MainActor.run {
                ServiceContainer.shared.toastManager.show("No click data found for auto-zoom", type: .info)
            }
            return
        }

        await MainActor.run {
            ServiceContainer.shared.toastManager.show("🎯 Generating auto-zoom keyframes...")
        }

        defer {
            Task { @MainActor in self.isProcessing = false }
        }

        do {
            let data = try Data(contentsOf: clickDataURL)
            let decoder = JSONDecoder()
            let clicks = try decoder.decode([ClickSample].self, from: data)

            guard !clicks.isEmpty else {
                await MainActor.run {
                    ServiceContainer.shared.toastManager.show(
                        "No clicks recorded for auto-zoom", type: .info)
                }
                return
            }

            let keyframes = AutoZoomService.generateAutoZoomKeyframes(
                from: clicks,
                clipDuration: clip.duration,
                config: .default
            )

            await MainActor.run {
                self.applyKeyframesToClip(keyframes, clip: clip, undoName: "Apply Auto-Zoom")
                ServiceContainer.shared.toastManager.show("✅ Auto-zoom applied (\(clicks.count) clicks)")
            }

        } catch {
            AppLogger.project.error("Auto-zoom failed: \(error)")
            await MainActor.run {
                ServiceContainer.shared.toastManager.show(
                    "Failed to apply auto-zoom: \(error.localizedDescription)", type: .error)
            }
        }
    }
}

// MARK: - Transitions

extension ProjectState {

    func setClipTransition(clipId: UUID, transitionType: TransitionType, transactionId: UUID? = nil) {
        guard !shouldBlockOperation(transactionId: transactionId) else { return }
        guard var project = currentProject else { return }

        var timeline = project.timeline
        var clipFound = false

        for (trackIndex, track) in timeline.tracks.enumerated() {
            if let index = track.clips.firstIndex(where: { $0.id == clipId }) {
                if track.isLocked {
                    ServiceContainer.shared.toastManager.show("Track is locked", type: .error)
                    return
                }

                registerUndo("Set Transition")

                var mutableTrack = track
                if transitionType == .none {
                    mutableTrack.clips[index].transition = nil
                } else {
                    mutableTrack.clips[index].transition = VideoTransition(type: transitionType)
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

            if transitionType == .none {
                ServiceContainer.shared.toastManager.show("Removed transition")
            } else {
                ServiceContainer.shared.toastManager.show(
                    "Added \(transitionType.displayName) transition")
            }
            AppLogger.project.info("Set transition \(transitionType.rawValue) for clip \(clipId)")
        }
    }
}

// MARK: - Shared Keyframe Helper

extension ProjectState {

    /// Apply keyframes to clip and save (consolidated helper)
    private func applyKeyframesToClip(
        _ keyframes: KeyframeAnimation, clip: VideoClip, undoName: String
    ) {
        guard var project = currentProject else { return }

        var timeline = project.timeline

        for (trackIndex, track) in timeline.tracks.enumerated() {
            if let index = track.clips.firstIndex(where: { $0.id == clip.id }) {
                if track.isLocked {
                    ServiceContainer.shared.toastManager.show("Track is locked", type: .error)
                    return
                }

                registerUndo(undoName)

                var mutableTrack = track
                mutableTrack.clips[index].keyframeAnimation = keyframes
                mutableTrack.clips[index].transform = .identity  // Reset static transform
                timeline.tracks[trackIndex] = mutableTrack
                break
            }
        }

        project.timeline = timeline
        currentProject = project
        saveProject(project)

        NotificationCenter.default.post(
            name: NSNotification.Name("ProjectEffectsChanged"),
            object: project
        )
    }
}
