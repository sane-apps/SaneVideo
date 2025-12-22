//
//  ThumbnailService.swift
//  SaneVideo
//
//  Created by SaneVideo Refactor
//  Optimized for Apple Silicon with efficient caching and batch generation
//

import AVFoundation
import Combine
import SwiftUI

/// Service responsible for generating and caching video thumbnails
/// Optimized for scrolling performance on M1+
actor ThumbnailService {

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
    func thumbnail(for clip: VideoClip, time: CMTime, size: CGSize) async -> NSImage? {
        let key = cacheKey(for: clip, time: time, size: size)

        // Check cache first
        if let cached = cache.object(forKey: key as NSString) {
            return cached
        }

        // Generate if not cached
        return await generateThumbnail(for: clip, time: time, size: size, key: key)
    }

    // MARK: - Internal Generation

    private func generateThumbnail(for clip: VideoClip, time: CMTime, size: CGSize, key: String) async -> NSImage? {
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

            return image
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
}
