//
//  ThumbnailGeneratorService.swift
//  SaneVideo
//
//  Created by SaneVideo Refactor
//

import AppKit
import AVFoundation
import Combine
import Foundation
import Vision

enum ThumbnailError: Error, LocalizedError {
    case assetLoadingFailed
    case frameExtractionFailed
    case visionRequestFailed

    var errorDescription: String? {
        switch self {
        case .assetLoadingFailed: return "Failed to load video asset."
        case .frameExtractionFailed: return "Failed to extract frame from video."
        case .visionRequestFailed: return "Vision request failed."
        }
    }
}

actor ThumbnailGeneratorService {

    init() {}

    /// Generates the "best" thumbnail from the video by analyzing frame quality/aesthetics.
    func generateBestThumbnail(for url: URL) async throws -> NSImage {
        let asset = AVURLAsset(url: url)

        // Load duration asynchronously
        let duration = try await asset.load(.duration)
        let durationSeconds = CMTimeGetSeconds(duration)

        guard durationSeconds > 0 else {
            throw ThumbnailError.assetLoadingFailed
        }

        // Candidates: 10%, 30%, 50%, 70%, 90% (increased sampling for better accuracy)
        let times: [CMTime] = [0.1, 0.3, 0.5, 0.7, 0.9].map {
            CMTime(seconds: durationSeconds * $0, preferredTimescale: 600)
        }

        let generator = AVAssetImageGenerator(asset: asset)
        generator.appliesPreferredTrackTransform = true
        generator.requestedTimeToleranceBefore = .zero
        generator.requestedTimeToleranceAfter = .zero

        var bestImage: NSImage?
        var maxAestheticScore: Float = -1.0

        for time in times {
            do {
                let (cgImage, _) = try await generator.image(at: time)
                let score = try calculateAestheticScore(for: cgImage)

                // track the most aesthetically pleasing frame (lighting, composition, blur, etc.)
                if score > maxAestheticScore {
                    maxAestheticScore = score
                    bestImage = NSImage(cgImage: cgImage, size: NSSize(width: cgImage.width, height: cgImage.height))
                }
            } catch {
                await MainActor.run {
                    AppLogger.timeline.warning("ThumbnailGenerator: Failed to extract/score frame at \(time.seconds)s: \(error)")
                }
            }
        }

        if let image = bestImage {
            return image
        }

        throw ThumbnailError.frameExtractionFailed
    }
    
    private let cache = NSCache<NSString, NSImage>()
    
    /// Calculates the aesthetic score using Apple's pre-trained Vision models (macOS 15+)
    private func calculateAestheticScore(for cgImage: CGImage) throws -> Float {
        // Modern API: VNCalculateImageAestheticsScoresRequest
        // This analyzes lighting, composition, and overall quality
        let request = VNCalculateImageAestheticsScoresRequest()
        let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])

        try handler.perform([request])

        guard let result = request.results?.first else {
            return 0.0
        }

        // overallScore is a value between 0.0 and 1.0 (usually ~0.5-0.8 for good frames)
        return result.overallScore
    }
}
