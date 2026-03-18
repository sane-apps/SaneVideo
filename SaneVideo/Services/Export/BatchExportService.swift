//
//  BatchExportService.swift
//  SaneVideo
//
//  Service for batch exporting short-form video clips
//

import AVFoundation
import CoreMedia
import Foundation
import OSLog

/// Actor for batch exporting short-form clips from long-form content
actor BatchExportService {
    // MARK: - Properties

    private let logger = Logger(subsystem: "com.sanevideo.SaneVideo", category: "BatchExport")
    private var isExporting = false

    private struct UncheckedExportSession: @unchecked Sendable {
        let session: AVAssetExportSession
    }

    /// Export context for single short (reduces parameter count)
    private struct ExportContext {
        let outputDirectory: URL
        let index: Int
    }

    // MARK: - Public API

    /// Export multiple short candidates from a source video
    /// - Parameters:
    ///   - candidates: The short candidates to export
    ///   - sourceURL: URL of the source video
    ///   - settings: Repurposing settings including aspect ratio
    ///   - progressHandler: Called with overall progress (0.0 - 1.0)
    /// - Returns: Array of exported file URLs
    func exportShorts(
        _ candidates: [ShortCandidate],
        from sourceURL: URL,
        settings: RepurposingSettings,
        progressHandler: @escaping @Sendable (Double) -> Void
    ) async throws -> [URL] {
        guard !isExporting else {
            throw BatchExportError.alreadyExporting
        }

        guard !candidates.isEmpty else {
            return []
        }

        isExporting = true
        defer { isExporting = false }

        // Create output directory
        let outputDir = try createOutputDirectory()

        var exportedURLs: [URL] = []
        let totalCount = candidates.count

        for (index, candidate) in candidates.enumerated() {
            let baseProgress = Double(index) / Double(totalCount)

            do {
                let context = ExportContext(outputDirectory: outputDir, index: index + 1)
                let outputURL = try await exportSingleShort(
                    candidate: candidate,
                    from: sourceURL,
                    settings: settings,
                    context: context
                ) { individualProgress in
                    let overallProgress = baseProgress + (individualProgress / Double(totalCount))
                    progressHandler(overallProgress)
                }

                exportedURLs.append(outputURL)
                logger.info("Exported short \(index + 1)/\(totalCount): \(outputURL.lastPathComponent)")

            } catch {
                logger.error("Failed to export short \(index + 1): \(error.localizedDescription)")
                // Continue with other exports even if one fails
            }
        }

        progressHandler(1.0)
        return exportedURLs
    }

    // MARK: - Private Methods

    private func createOutputDirectory() throws -> URL {
        let fileManager = FileManager.default
        guard let moviesDir = fileManager.urls(for: .moviesDirectory, in: .userDomainMask).first else {
            throw BatchExportError.outputDirectoryCreationFailed
        }

        let shortsDir = moviesDir
            .appendingPathComponent("SaneVideo")
            .appendingPathComponent("Shorts")

        if !fileManager.fileExists(atPath: shortsDir.path) {
            try fileManager.createDirectory(at: shortsDir, withIntermediateDirectories: true)
        }

        return shortsDir
    }

    private func exportSingleShort(
        candidate: ShortCandidate,
        from sourceURL: URL,
        settings: RepurposingSettings,
        context: ExportContext,
        progressHandler: @escaping @Sendable (Double) -> Void
    ) async throws -> URL {
        let asset = AVURLAsset(url: sourceURL)

        // Create composition for trimming
        let composition = AVMutableComposition()

        // Load tracks
        let videoTracks = try await asset.loadTracks(withMediaType: .video)
        let audioTracks = try await asset.loadTracks(withMediaType: .audio)

        guard let sourceVideoTrack = videoTracks.first else {
            throw BatchExportError.noVideoTrack
        }

        // Add video track
        guard let compositionVideoTrack = composition.addMutableTrack(
            withMediaType: .video,
            preferredTrackID: kCMPersistentTrackID_Invalid
        ) else {
            throw BatchExportError.compositionFailed
        }

        try compositionVideoTrack.insertTimeRange(
            candidate.timeRange,
            of: sourceVideoTrack,
            at: .zero
        )

        // Add audio track if present
        if let sourceAudioTrack = audioTracks.first {
            if let compositionAudioTrack = composition.addMutableTrack(
                withMediaType: .audio,
                preferredTrackID: kCMPersistentTrackID_Invalid
            ) {
                try compositionAudioTrack.insertTimeRange(
                    candidate.timeRange,
                    of: sourceAudioTrack,
                    at: .zero
                )
            }
        }

        // Create video composition for aspect ratio transformation
        let videoComposition = try await createVideoComposition(
            for: composition,
            sourceTrack: sourceVideoTrack,
            settings: settings,
            crop: candidate.suggestedCrop
        )

        // Generate output filename
        let timestamp = DateFormatter.shortExportFormatter.string(from: Date())
        let filename = "Short_\(context.index)_\(timestamp).mp4"
        let outputURL = context.outputDirectory.appendingPathComponent(filename)

        // Remove existing file if present
        try? FileManager.default.removeItem(at: outputURL)

        // Export
        guard let exportSession = AVAssetExportSession(
            asset: composition,
            presetName: AVAssetExportPresetHighestQuality
        ) else {
            throw BatchExportError.exportSessionCreationFailed
        }

        exportSession.videoComposition = videoComposition
        exportSession.shouldOptimizeForNetworkUse = true

        let uncheckedSession = UncheckedExportSession(session: exportSession)
        let progressTask = Task {
            while !Task.isCancelled {
                progressHandler(Double(uncheckedSession.session.progress))
                try? await Task.sleep(for: .milliseconds(100))
            }
        }
        defer { progressTask.cancel() }

        do {
            try await exportSession.export(to: outputURL, as: .mp4)
            progressHandler(1.0)
        } catch is CancellationError {
            throw BatchExportError.exportCancelled
        } catch {
            if Task.isCancelled {
                throw BatchExportError.exportCancelled
            }
            throw error
        }

        return outputURL
    }

    private func createVideoComposition(
        for composition: AVMutableComposition,
        sourceTrack: AVAssetTrack,
        settings: RepurposingSettings,
        crop: SuggestedCrop
    ) async throws -> AVMutableVideoComposition {
        // Get source dimensions
        let naturalSize = try await sourceTrack.load(.naturalSize)
        let preferredTransform = try await sourceTrack.load(.preferredTransform)

        // Calculate actual size after transform
        var sourceWidth = naturalSize.width
        var sourceHeight = naturalSize.height

        // Check if video is rotated
        let isRotated = abs(preferredTransform.a) < 0.1 && abs(preferredTransform.d) < 0.1
        if isRotated {
            swap(&sourceWidth, &sourceHeight)
        }

        // Calculate output dimensions based on aspect ratio
        var renderWidth: CGFloat
        var renderHeight: CGFloat

        if settings.aspectRatio == .vertical9x16 {
            // For vertical video, use 1080x1920
            renderWidth = 1080
            renderHeight = 1920
        } else if settings.aspectRatio == .square1x1 {
            renderWidth = 1080
            renderHeight = 1080
        } else {
            // 4:5 portrait
            renderWidth = 1080
            renderHeight = 1350
        }

        let videoComposition = AVMutableVideoComposition()
        videoComposition.renderSize = CGSize(width: renderWidth, height: renderHeight)
        videoComposition.frameDuration = CMTime(value: 1, timescale: 30)

        // Create instruction
        let instruction = AVMutableVideoCompositionInstruction()
        instruction.timeRange = CMTimeRange(
            start: .zero,
            duration: composition.duration
        )

        // Create layer instruction with transform
        guard let compositionTrack = composition.tracks(withMediaType: .video).first else {
            throw BatchExportError.compositionFailed
        }

        let layerInstruction = AVMutableVideoCompositionLayerInstruction(assetTrack: compositionTrack)

        // Calculate transform for cropping and scaling
        let transform = calculateCropTransform(
            sourceSize: CGSize(width: sourceWidth, height: sourceHeight),
            renderSize: CGSize(width: renderWidth, height: renderHeight),
            crop: crop,
            sourceTransform: preferredTransform
        )

        layerInstruction.setTransform(transform, at: .zero)
        instruction.layerInstructions = [layerInstruction]
        videoComposition.instructions = [instruction]

        return videoComposition
    }

    private func calculateCropTransform(
        sourceSize: CGSize,
        renderSize: CGSize,
        crop: SuggestedCrop,
        sourceTransform: CGAffineTransform
    ) -> CGAffineTransform {
        let targetAspect = renderSize.width / renderSize.height
        let sourceAspect = sourceSize.width / sourceSize.height

        var scale: CGFloat
        var cropWidth: CGFloat
        var cropHeight: CGFloat

        if targetAspect > sourceAspect {
            // Target is wider - fit width, crop height
            scale = renderSize.width / sourceSize.width
            cropWidth = sourceSize.width
            cropHeight = sourceSize.width / targetAspect
        } else {
            // Target is taller - fit height, crop width
            scale = renderSize.height / sourceSize.height
            cropHeight = sourceSize.height
            cropWidth = sourceSize.height * targetAspect
        }

        // Apply smart crop center offset
        let centerOffsetX = (crop.centerX - 0.5) * sourceSize.width
        let centerOffsetY = (crop.centerY - 0.5) * sourceSize.height

        // Calculate translation to center the crop region
        let translateX = -(sourceSize.width - cropWidth) / 2 - centerOffsetX
        let translateY = -(sourceSize.height - cropHeight) / 2 - centerOffsetY

        // Build transform: translate to crop center, then scale
        var transform = CGAffineTransform.identity

        // Apply source transform first (for rotation)
        transform = sourceTransform

        // Translate
        transform = transform.translatedBy(x: translateX * scale, y: translateY * scale)

        // Scale
        transform = transform.scaledBy(x: scale * crop.scale, y: scale * crop.scale)

        return transform
    }
}

// MARK: - Errors

enum BatchExportError: LocalizedError {
    case alreadyExporting
    case outputDirectoryCreationFailed
    case noVideoTrack
    case compositionFailed
    case exportSessionCreationFailed
    case exportFailed
    case exportCancelled

    var errorDescription: String? {
        switch self {
        case .alreadyExporting:
            return "A batch export is already in progress."
        case .outputDirectoryCreationFailed:
            return "Failed to create output directory."
        case .noVideoTrack:
            return "Source video has no video track."
        case .compositionFailed:
            return "Failed to create video composition."
        case .exportSessionCreationFailed:
            return "Failed to create export session."
        case .exportFailed:
            return "Export failed."
        case .exportCancelled:
            return "Export was cancelled."
        }
    }
}

// MARK: - Date Formatter Extension

private extension DateFormatter {
    static let shortExportFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyyMMdd_HHmmss"
        return formatter
    }()
}
