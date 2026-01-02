//
//  SmartCropService.swift
//  SaneVideo
//
//  Combines face tracking and saliency analysis to generate smart crop keyframes
//  for vertical/square export from horizontal source video.
//

import AVFoundation
import CoreMedia
import Foundation

/// Service for generating smart crop keyframes for export
actor SmartCropService {

    // MARK: - Dependencies

    private let faceTracking: FaceTrackingService
    private let saliencyService: SaliencyService

    // MARK: - Initialization

    init(
        faceTracking: FaceTrackingService = FaceTrackingService(),
        saliencyService: SaliencyService = SaliencyService()
    ) {
        self.faceTracking = faceTracking
        self.saliencyService = saliencyService
    }

    // MARK: - Public API

    /// Result of smart crop analysis for a video
    struct SmartCropResult: Sendable {
        /// Per-time crop suggestions (sampled at interval)
        let keyframes: [CMTime: SuggestedCrop]

        /// Overall suggested crop (weighted average)
        let defaultCrop: SuggestedCrop

        /// Duration of analyzed video
        let duration: CMTime
    }

    /// Analyze a video for smart crop keyframes
    /// - Parameters:
    ///   - sourceURL: URL of the video to analyze
    ///   - settings: Smart crop settings (mode, smoothing)
    ///   - progressHandler: Progress callback (0.0 - 1.0)
    /// - Returns: SmartCropResult with keyframes and default crop
    func analyzeVideo(
        sourceURL: URL,
        settings: SmartCropSettings,
        progressHandler: (@Sendable (Double) -> Void)? = nil
    ) async throws -> SmartCropResult {
        guard settings.enabled else {
            // Return default center crop if not enabled
            let asset = AVURLAsset(url: sourceURL)
            let duration = try await asset.load(.duration)
            return SmartCropResult(
                keyframes: [:],
                defaultCrop: .default,
                duration: duration
            )
        }

        AppLogger.export.info("📐 SmartCrop: Analyzing video with mode \(settings.trackingMode.rawValue)")

        let asset = AVURLAsset(url: sourceURL)
        let duration = try await asset.load(.duration)

        // Sample interval: 1fps for performance (interpolate between keyframes)
        let sampleInterval: TimeInterval = 1.0

        var keyframes: [CMTime: SuggestedCrop] = [:]

        switch settings.trackingMode {
        case .face:
            keyframes = try await analyzeFaces(
                sourceURL: sourceURL,
                sampleInterval: sampleInterval,
                progressHandler: progressHandler
            )

        case .saliency:
            keyframes = try await analyzeSaliency(
                sourceURL: sourceURL,
                sampleInterval: sampleInterval,
                progressHandler: progressHandler
            )

        case .combined:
            // Run both, prefer faces when available
            let faceKeyframes = try await analyzeFaces(
                sourceURL: sourceURL,
                sampleInterval: sampleInterval,
                progressHandler: { progressHandler?($0 * 0.5) }
            )
            let saliencyKeyframes = try await analyzeSaliency(
                sourceURL: sourceURL,
                sampleInterval: sampleInterval,
                progressHandler: { progressHandler?(0.5 + $0 * 0.5) }
            )

            // Merge: use face data when available, fallback to saliency
            for (time, saliencyCrop) in saliencyKeyframes {
                keyframes[time] = faceKeyframes[time] ?? saliencyCrop
            }
        }

        // Apply smoothing to keyframes
        let smoothedKeyframes = applySmoothing(to: keyframes, factor: settings.smoothing)

        // Calculate default crop (weighted average of all keyframes)
        let defaultCrop = calculateDefaultCrop(from: smoothedKeyframes)

        AppLogger.export.info("📐 SmartCrop: Generated \(smoothedKeyframes.count) keyframes")

        return SmartCropResult(
            keyframes: smoothedKeyframes,
            defaultCrop: defaultCrop,
            duration: duration
        )
    }

    // MARK: - Private Analysis Methods

    private func analyzeFaces(
        sourceURL: URL,
        sampleInterval: TimeInterval,
        progressHandler: (@Sendable (Double) -> Void)?
    ) async throws -> [CMTime: SuggestedCrop] {
        let faceData = try await faceTracking.analyzeVideo(
            videoURL: sourceURL,
            sampleInterval: sampleInterval,
            progressHandler: progressHandler
        )

        var keyframes: [CMTime: SuggestedCrop] = [:]

        for (time, faceRect) in faceData {
            // Convert face rect to crop suggestion
            // Face rect is normalized 0-1, center X/Y
            let centerX = faceRect.midX
            let centerY = faceRect.midY

            // Zoom based on face size (larger face = less zoom needed)
            let faceSize = max(faceRect.width, faceRect.height)
            let zoom = min(1.5, max(1.0, 0.3 / faceSize)) // Inverse relationship

            keyframes[time] = SuggestedCrop(centerX: centerX, centerY: centerY, scale: zoom)
        }

        return keyframes
    }

    private func analyzeSaliency(
        sourceURL: URL,
        sampleInterval: TimeInterval,
        progressHandler: (@Sendable (Double) -> Void)?
    ) async throws -> [CMTime: SuggestedCrop] {
        let saliencyData = try await saliencyService.analyzeVideoForReframe(
            videoURL: sourceURL,
            sampleInterval: sampleInterval,
            progressHandler: { current, total in
                progressHandler?(Double(current) / Double(max(1, total)))
            }
        )

        var keyframes: [CMTime: SuggestedCrop] = [:]

        for (time, result) in saliencyData {
            // Use saliency attention point for center
            let center = result.attentionPoint
            let rect = result.attentionRect

            // Zoom based on saliency region size
            let regionSize = max(rect.width, rect.height)
            let zoom = min(1.3, max(1.0, 0.4 / regionSize))

            keyframes[time] = SuggestedCrop(centerX: center.x, centerY: center.y, scale: zoom)
        }

        return keyframes
    }

    // MARK: - Smoothing

    private func applySmoothing(
        to keyframes: [CMTime: SuggestedCrop],
        factor: Double
    ) -> [CMTime: SuggestedCrop] {
        guard factor > 0, keyframes.count > 1 else {
            return keyframes
        }

        // Sort keyframes by time
        let sortedTimes = keyframes.keys.sorted { $0 < $1 }
        var smoothed: [CMTime: SuggestedCrop] = [:]

        var previousCrop: SuggestedCrop?

        for time in sortedTimes {
            guard let crop = keyframes[time] else { continue }

            if let prev = previousCrop {
                // EMA smoothing
                let alpha = 1.0 - factor
                let smoothedCrop = SuggestedCrop(
                    centerX: alpha * crop.centerX + factor * prev.centerX,
                    centerY: alpha * crop.centerY + factor * prev.centerY,
                    scale: alpha * crop.scale + factor * prev.scale
                )
                smoothed[time] = smoothedCrop
                previousCrop = smoothedCrop
            } else {
                smoothed[time] = crop
                previousCrop = crop
            }
        }

        return smoothed
    }

    private func calculateDefaultCrop(from keyframes: [CMTime: SuggestedCrop]) -> SuggestedCrop {
        guard !keyframes.isEmpty else {
            return .default
        }

        var totalX: CGFloat = 0
        var totalY: CGFloat = 0
        var totalScale: CGFloat = 0

        for crop in keyframes.values {
            totalX += crop.centerX
            totalY += crop.centerY
            totalScale += crop.scale
        }

        let count = CGFloat(keyframes.count)
        return SuggestedCrop(
            centerX: totalX / count,
            centerY: totalY / count,
            scale: totalScale / count
        )
    }
}
