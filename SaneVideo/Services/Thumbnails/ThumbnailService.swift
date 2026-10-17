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
actor ThumbnailService: ThumbnailServiceProtocol {

    // MARK: - Caching

    /// Capped at about 100 MB to avoid memory pressure.
    private let cache = NSCache<NSString, NSImage>()

    /// Cached generators avoid creating an AVURLAsset per thumbnail.
    /// Key: clip URL path, Value: (generator, lastAccessTime)
    private var generatorCache: [String: (generator: UncheckedBox<AVAssetImageGenerator>, lastAccess: Date)] = [:]
    private let maxGeneratorCacheSize = 10

    init() {
        cache.countLimit = 500
        cache.totalCostLimit = 100 * 1024 * 1024 // 100MB
    }

    private func getGenerator(for url: URL) -> AVAssetImageGenerator {
        let key = url.path

        if var entry = generatorCache[key] {
            entry.lastAccess = Date()
            generatorCache[key] = entry
            return entry.generator.value
        }

        let asset = AVURLAsset(url: url)
        let generator = AVAssetImageGenerator(asset: asset)
        generator.appliesPreferredTrackTransform = true
        
        // Zero tolerance for exact frames.
        generator.requestedTimeToleranceBefore = .zero
        generator.requestedTimeToleranceAfter = .zero

        generatorCache[key] = (generator: UncheckedBox(generator), lastAccess: Date())

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

        if let cached = cache.object(forKey: key as NSString) {
            return UncheckedBox(cached)
        }

        return await generateThumbnail(for: clip, time: time, size: size, key: key)
    }

    // MARK: - Internal Generation

    private func generateThumbnail(for clip: VideoClip, time: CMTime, size: CGSize, key: String) async -> UncheckedBox<NSImage>? {
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

        let generator = getGenerator(for: clip.url)
        
        // maximumSize keeps the aspect ratio.
        generator.maximumSize = size

        do {
            let boxedGenerator = UncheckedBox(generator)
            let (cgImage, _) = try await boxedGenerator.value.image(at: time)

            // Use the generated size, not the requested one, to keep the aspect ratio.
            let actualSize = CGSize(width: CGFloat(cgImage.width), height: CGFloat(cgImage.height))
            let image = NSImage(cgImage: cgImage, size: actualSize)

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
    ///   - strategy: Scoring strategy to use (defaults to .aesthetic)
    func generateBestThumbnail(for url: URL, strategy: ThumbnailScoringStrategy = .aesthetic) async throws -> UncheckedBox<NSImage> {
        try await withSecurityScopedAccess(to: url) {
            try await generateBestThumbnailWithAccess(for: url, strategy: strategy)
        }
    }

    private func generateBestThumbnailWithAccess(for url: URL, strategy: ThumbnailScoringStrategy) async throws -> UncheckedBox<NSImage> {
        let asset = AVURLAsset(url: url)
        let duration = try await asset.load(.duration)
        let durationSeconds = CMTimeGetSeconds(duration)

        guard durationSeconds > 0 else {
            throw ThumbnailError.assetLoadingFailed
        }

        let times: [CMTime] = switch strategy {
        case .fast:
            [CMTime(seconds: durationSeconds * 0.5, preferredTimescale: 600)]
        case .aesthetic:
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
        try await withSecurityScopedAccess(to: url) {
            try await generateSmartThumbnailWithAccess(for: url, strategy: strategy)
        }
    }

    private func generateSmartThumbnailWithAccess(for url: URL, strategy: ThumbnailScoringStrategy) async throws -> URL {
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

    private func withSecurityScopedAccess<T>(
        to url: URL,
        operation: () async throws -> T
    ) async throws -> T {
        let isAccessing = url.startAccessingSecurityScopedResource()
        defer {
            if isAccessing {
                url.stopAccessingSecurityScopedResource()
            }
        }

        return try await operation()
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

    private func scoreFaceQuality(_ cgImage: CGImage) async throws -> Float {
        let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])
        let faceRequest = VNDetectFaceCaptureQualityRequest()

        try handler.perform([faceRequest])

        if let faceObservations = faceRequest.results, !faceObservations.isEmpty {
            // faceCaptureQuality is still the best face-quality API as of macOS 26.2.
            let maxQuality = faceObservations.compactMap { $0.faceCaptureQuality }.max() ?? 0.1
            let maxFaceArea = faceObservations.map { $0.boundingBox.width * $0.boundingBox.height }.max() ?? 0.0
            return (maxQuality * 0.7) + (Float(maxFaceArea) * 0.3) + 1.0
        }

        return 0.5 // No faces found
    }

    private func saveThumbnail(image: CGImage, filename: String) throws -> URL {
        let fileManager = FileManager.default
        let thumbDir = try thumbnailDirectory(fileManager: fileManager)

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

    private func thumbnailDirectory(fileManager: FileManager) throws -> URL {
        guard let supportURL = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else {
            throw ThumbnailError.visionRequestFailed
        }

        return supportURL
            .appendingPathComponent("SaneVideo", isDirectory: true)
            .appendingPathComponent("Thumbnails", isDirectory: true)
    }
}
