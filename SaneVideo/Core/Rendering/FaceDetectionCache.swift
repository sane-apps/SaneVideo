//
//  FaceDetectionCache.swift
//  SaneVideo
//
//  Caches face detection results across nearby frames to avoid
//  running expensive Vision requests on every frame.
//

import CoreImage
import CoreMedia
import Vision

/// Caches face detection results across nearby frames to avoid
/// running expensive Vision requests on every frame.
actor FaceDetectionCache {
    private struct CacheEntry {
        let time: CMTime
        let faceRects: [CGRect]
    }

    /// Cache window: reuse results within this time range
    private let cacheWindowSeconds: Double = 0.5 // 15 frames at 30fps

    /// Maximum cached entries
    private let maxEntries: Int = 30

    private var entries: [CacheEntry] = []

    /// Get face rects for a given time, using cache if available.
    /// Falls back to running detection if no cached result is close enough.
    func getFaceRects(for image: CIImage, at time: CMTime) -> [CGRect] {
        // Check cache first
        if let cached = findCachedEntry(near: time) {
            return cached.faceRects
        }

        // Cache miss: run detection
        let faceRects = detectFaces(in: image)

        // Store result
        let entry = CacheEntry(time: time, faceRects: faceRects)
        entries.append(entry)

        // Evict old entries
        if entries.count > maxEntries {
            entries.removeFirst(entries.count - maxEntries)
        }

        return faceRects
    }

    /// Clear cache (e.g., on seek)
    func invalidate() {
        entries.removeAll()
    }

    private func findCachedEntry(near time: CMTime) -> CacheEntry? {
        let timeSeconds = time.seconds
        return entries.first(where: {
            abs($0.time.seconds - timeSeconds) < cacheWindowSeconds
        })
    }

    private func detectFaces(in image: CIImage) -> [CGRect] {
        let request = VNDetectFaceRectanglesRequest()
        let handler = VNImageRequestHandler(ciImage: image, options: [:])
        try? handler.perform([request])
        return request.results?.map(\.boundingBox) ?? []
    }
}
