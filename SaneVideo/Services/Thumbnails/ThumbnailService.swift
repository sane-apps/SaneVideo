//
//  ThumbnailService.swift
//  SaneVideo
//
//  Created by SaneVideo Refactor
//  Optimized for Apple Silicon with efficient caching and batch generation
//  Consolidated: Merged ThumbnailGeneratorService + SmartThumbnailService
//

@preconcurrency import AVFoundation
@preconcurrency import Combine
@preconcurrency import AppKit
import SwiftUI
import Vision

// MARK: - Thumbnail Types

enum ThumbnailError: Error, LocalizedError {
    case assetLoadingFailed
    case frameExtractionFailed
    case visionRequestFailed
    case noValidFrames

    var errorDescription: String? {
        switch self {
        case .assetLoadingFailed: return "Failed to load video asset."
        case .frameExtractionFailed: return "Failed to extract frame from video."
        case .visionRequestFailed: return "Vision request failed."
        case .noValidFrames: return "No valid frames could be generated."
        }
    }
}

/// Strategy for scoring frames when selecting the "best" thumbnail
enum ThumbnailScoringStrategy: Sendable {
    /// Fast: Just pick middle frame, no scoring (for timeline scrubbing)
    case fast
    /// Aesthetic: Use Apple's CalculateImageAestheticsScoresRequest (macOS 15+)
    case aesthetic
    /// Face Quality: Prioritize frames with good face capture quality
    case faceQuality
}

/// Service responsible for generating and caching video thumbnails
/// Optimized for scrolling performance on M1+
/// Consolidated: Handles both on-demand timeline thumbnails and "best" thumbnail generation
actor ThumbnailService: ThumbnailServiceProtocol {

    // MARK: - Caching

    /// Memory cache for thumbnails
    /// Limit set to ~100MB to avoid memory pressure
    private let cache = NSCache<NSString, NSImage>()

    /// FIXED: Cache image generators to avoid creating new AVURLAsset for every thumbnail
    /// Key: clip URL path, Value: (generator, lastAccessTime)
    private var generatorCache: [String: (generator: UncheckedBox<AVAssetImageGenerator>, lastAccess: Date)] = [:]
    private let maxGeneratorCacheSize = 10

    init() {
        // Configure cache limits
        cache.countLimit = 500
        cache.totalCostLimit = 100 * 1024 * 1024 // 100MB
    }

    /// Get or create an image generator for a clip URL
    private func getGenerator(for url: URL) -> AVAssetImageGenerator {
        let key = url.path

        // Check cache
        if var entry = generatorCache[key] {
            entry.lastAccess = Date()
            generatorCache[key] = entry
            return entry.generator.value
        }

        // Create new generator
        let asset = AVURLAsset(url: url)
        let generator = AVAssetImageGenerator(asset: asset)
        generator.appliesPreferredTrackTransform = true
        
        // QUALITY: Use zero tolerance for exact frame extraction (highest quality)
        generator.requestedTimeToleranceBefore = .zero
        generator.requestedTimeToleranceAfter = .zero

        // Cache it (Wrap in UncheckedBox)
        generatorCache[key] = (generator: UncheckedBox(generator), lastAccess: Date())

        // Evict old entries if cache is too large
        if generatorCache.count > maxGeneratorCacheSize {
            let oldest = generatorCache.min { $0.value.lastAccess < $1.value.lastAccess }
            if let oldestKey = oldest?.key {
                generatorCache.removeValue(forKey: oldestKey)
            }
        }

        return generator
    }

    // MARK: - Public API

    /// Request a thumbnail for a specific time
    /// - Returns: Cached image immediately if available, or nil if generation started
    func thumbnail(for clip: VideoClip, time: CMTime, size: CGSize) async -> UncheckedBox<NSImage>? {
        let key = cacheKey(for: clip, time: time, size: size)

        // Check cache first
        if let cached = cache.object(forKey: key as NSString) {
            return UncheckedBox(cached)
        }

        // Generate if not cached
        return await generateThumbnail(for: clip, time: time, size: size, key: key)
    }

    // MARK: - Internal Generation

    private func generateThumbnail(for clip: VideoClip, time: CMTime, size: CGSize, key: String) async -> UncheckedBox<NSImage>? {
        // Check if file exists (runs on actor, off main thread)
        // 0. Security Scope Access
        let isAccessing = clip.url.startAccessingSecurityScopedResource()
        defer {
            if isAccessing {
                clip.url.stopAccessingSecurityScopedResource()
            }
        }

        let fileManager = FileManager.default
        guard fileManager.fileExists(atPath: clip.url.path),
              let attributes = try? fileManager.attributesOfItem(atPath: clip.url.path),
              let fileSize = attributes[.size] as? UInt64,
              fileSize > 0
        else {
            await MainActor.run { AppLogger.timeline.warning("ThumbnailService: File missing or empty at \(clip.url.path)") }
            return nil
        }

        // FIXED: Use cached generator instead of creating new AVURLAsset each time
        let generator = getGenerator(for: clip.url)
        
        // QUALITY: Set maximum size (generator maintains aspect ratio)
        // Use higher resolution for better quality on retina displays
        generator.maximumSize = size

        do {
            // Use modern async API
            // Use UncheckedBox to silence Sendability warning for generator
            let boxedGenerator = UncheckedBox(generator)
            let (cgImage, _) = try await boxedGenerator.value.image(at: time)

            // Fix: Do NOT force the requested size. Use the actual generated size to maintain aspect ratio.
            // The generator respects maximumSize but maintains aspect ratio.
            // We just wrap that resulting bitmap in an NSImage.
            let actualSize = CGSize(width: CGFloat(cgImage.width), height: CGFloat(cgImage.height))
            let image = NSImage(cgImage: cgImage, size: actualSize)

            // Cache the result
            cache.setObject(image, forKey: key as NSString, cost: cgImage.bytesPerRow * cgImage.height)

            return UncheckedBox(image)
        } catch {
            await MainActor.run { AppLogger.timeline.error("Thumbnail generation failed for \(clip.url.lastPathComponent): \(error.localizedDescription)") }
            return nil
        }
    }

    private func cacheKey(for clip: VideoClip, time: CMTime, size: CGSize) -> String {
        "\(clip.id.uuidString)-\(time.seconds)-\(Int(size.width))x\(Int(size.height))"
    }

    /// Clear the thumbnail cache (called during memory pressure)
    func clearCache() {
        cache.removeAllObjects()
        generatorCache.removeAll() // Also clear generator cache to free AVURLAssets
        AppLogger.timeline.info("ThumbnailService: Cache cleared")
    }

    // MARK: - Best Thumbnail Generation (Consolidated from ThumbnailGeneratorService + SmartThumbnailService)

    /// Generates the "best" thumbnail from the video by analyzing frames with the specified strategy.
    /// - Parameters:
    ///   - url: The video file URL
    ///   - strategy: Scoring strategy to use (defaults to .aesthetic)
    /// - Returns: The best-scored NSImage
    func generateBestThumbnail(for url: URL, strategy: ThumbnailScoringStrategy = .aesthetic) async throws -> UncheckedBox<NSImage> {
        let asset = AVURLAsset(url: url)
        let duration = try await asset.load(.duration)
        let durationSeconds = CMTimeGetSeconds(duration)

        guard durationSeconds > 0 else {
            throw ThumbnailError.assetLoadingFailed
        }

        // Sample positions based on strategy
        let times: [CMTime] = switch strategy {
        case .fast:
            // Just middle frame
            [CMTime(seconds: durationSeconds * 0.5, preferredTimescale: 600)]
        case .aesthetic:
            // 5 samples across video: 10%, 30%, 50%, 70%, 90%
            [0.1, 0.3, 0.5, 0.7, 0.9].map { CMTime(seconds: durationSeconds * $0, preferredTimescale: 600) }
        case .faceQuality:
            // 10 samples from first 30% (faces are usually at start)
            generateCandidateTimes(durationSeconds: durationSeconds, count: 10)
        }

        let generator = AVAssetImageGenerator(asset: asset)
        generator.appliesPreferredTrackTransform = true
        generator.requestedTimeToleranceBefore = .zero
        generator.requestedTimeToleranceAfter = .zero

        if strategy == .faceQuality {
            generator.maximumSize = CGSize(width: 512, height: 512) // Faster for face analysis
        }

        var bestImage: UncheckedBox<NSImage>?
        var maxScore: Float = -1.0

        for time in times {
            do {
                let (cgImage, _) = try await generator.image(at: time)
                let score = try await scoreFrame(cgImage, strategy: strategy)

                if score > maxScore {
                    maxScore = score
                    bestImage = UncheckedBox(NSImage(
                        cgImage: cgImage,
                        size: NSSize(width: cgImage.width, height: cgImage.height)
                    ))
                }
            } catch {
                await MainActor.run {
                    AppLogger.timeline.warning("ThumbnailService: Failed to extract/score frame at \(time.seconds)s: \(error)")
                }
            }
        }

        guard let image = bestImage else {
            throw ThumbnailError.noValidFrames
        }

        return image
    }

    /// Generates a smart thumbnail and saves it to disk (for project thumbnails)
    /// - Returns: The local URL of the saved JPEG thumbnail
    func generateSmartThumbnail(for url: URL, strategy: ThumbnailScoringStrategy = .faceQuality) async throws -> URL {
        AppLogger.vision.info("🖼️ ThumbnailService: Generating smart thumbnail for \(url.lastPathComponent)")

        let asset = AVURLAsset(url: url)
        let duration = try await asset.load(.duration)
        let durationSeconds = duration.seconds

        guard durationSeconds > 0 else {
            throw ThumbnailError.assetLoadingFailed
        }

        let candidateTimes = generateCandidateTimes(durationSeconds: durationSeconds, count: 10)

        // Low-res pass for scoring
        let generator = AVAssetImageGenerator(asset: asset)
        generator.appliesPreferredTrackTransform = true
        generator.requestedTimeToleranceBefore = .zero
        generator.requestedTimeToleranceAfter = .zero
        generator.maximumSize = CGSize(width: 512, height: 512)

        var bestTime: CMTime = candidateTimes.first ?? .zero
        var maxScore: Float = -1.0

        for time in candidateTimes {
            do {
                let (cgImage, actualTime) = try await generator.image(at: time)
                let score = try await scoreFrame(cgImage, strategy: strategy)

                if score > maxScore {
                    maxScore = score
                    bestTime = actualTime
                }
            } catch {
                AppLogger.vision.warning("ThumbnailService: Failed to score candidate at \(time.seconds)s")
            }
        }

        // High-res pass for final image
        let fullResGenerator = AVAssetImageGenerator(asset: asset)
        fullResGenerator.appliesPreferredTrackTransform = true
        fullResGenerator.requestedTimeToleranceBefore = .zero
        fullResGenerator.requestedTimeToleranceAfter = .zero

        let (highResImage, _) = try await fullResGenerator.image(at: bestTime)

        AppLogger.vision.info("🖼️ ThumbnailService: Selected frame at \(bestTime.seconds)s with score \(String(format: "%.2f", maxScore))")

        return try saveThumbnail(image: highResImage, filename: url.lastPathComponent)
    }

    // MARK: - Private Scoring Helpers

    private func generateCandidateTimes(durationSeconds: Double, count: Int) -> [CMTime] {
        // Sample from first 30% of video (or full if short)
        let endWindow = (durationSeconds > 10) ? (durationSeconds * 0.3) : durationSeconds
        let step = endWindow / Double(count)

        return (0..<count).map { i in
            let t = max(0.1, Double(i) * step) // Avoid 0.0 to skip potential black frames
            return CMTime(seconds: t, preferredTimescale: 600)
        }
    }

    private func scoreFrame(_ cgImage: CGImage, strategy: ThumbnailScoringStrategy) async throws -> Float {
        switch strategy {
        case .fast:
            return 1.0 // No scoring for fast mode

        case .aesthetic:
            return try await scoreAesthetic(cgImage)

        case .faceQuality:
            return try await scoreFaceQuality(cgImage)
        }
    }

    /// Score using Apple's CalculateImageAestheticsScoresRequest (macOS 15+)
    private func scoreAesthetic(_ cgImage: CGImage) async throws -> Float {
        let request = CalculateImageAestheticsScoresRequest()
        let handler = ImageRequestHandler(cgImage)
        let observation = try await handler.perform(request)
        return observation.overallScore
    }

    /// Score based on face capture quality
    private func scoreFaceQuality(_ cgImage: CGImage) async throws -> Float {
        let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])
        let faceRequest = VNDetectFaceCaptureQualityRequest()

        try handler.perform([faceRequest])

        if let faceObservations = faceRequest.results, !faceObservations.isEmpty {
            // Note: faceCaptureQuality is still the best API for face quality scoring on macOS 26.2
            // If a replacement API becomes available, update per legacy migration guidelines
            let maxQuality = faceObservations.compactMap { $0.faceCaptureQuality }.max() ?? 0.1
            let maxFaceArea = faceObservations.map { $0.boundingBox.width * $0.boundingBox.height }.max() ?? 0.0
            return (maxQuality * 0.7) + (Float(maxFaceArea) * 0.3) + 1.0
        }

        return 0.5 // No faces found
    }

    private func saveThumbnail(image: CGImage, filename: String) throws -> URL {
        let fileManager = FileManager.default
        let docs = fileManager.urls(for: .documentDirectory, in: .userDomainMask).first!
        let thumbDir = docs.appendingPathComponent("Thumbnails")

        try fileManager.createDirectory(at: thumbDir, withIntermediateDirectories: true)

        let name = (filename as NSString).deletingPathExtension
        let fileURL = thumbDir.appendingPathComponent("\(name).jpg")

        let outputData = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(outputData, "public.jpeg" as CFString, 1, nil) else {
            throw ThumbnailError.visionRequestFailed
        }

        let properties = [kCGImageDestinationLossyCompressionQuality: 0.8] as CFDictionary
        CGImageDestinationAddImage(destination, image, properties)

        guard CGImageDestinationFinalize(destination) else {
            throw ThumbnailError.visionRequestFailed
        }

        try (outputData as Data).write(to: fileURL)
        return fileURL
    }
}
