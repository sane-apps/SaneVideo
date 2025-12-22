//
//  CursorRenderer.swift
//  SaneVideo
//
//  Created by SaneVideo Refactor
//

import CoreImage
import Foundation
import AppKit

/// Renders cursor highlights based on recorded data
enum CursorRenderer {
    
    // Simple in-memory cache for cursor data
    // Isolated to a serial queue for Swift 6 concurrency safety
    private static let cacheQueue = DispatchQueue(label: "com.sanevideo.cursorCache")
    private nonisolated(unsafe) static var cursorCache: [URL: [CursorSample]] = [:]
    
    // MARK: - Cache Management

    private static func getCachedSamples(for url: URL) -> [CursorSample]? {
        return cacheQueue.sync {
            cursorCache[url]
        }
    }

    private static func cacheSamples(_ samples: [CursorSample], for url: URL) {
        cacheQueue.async {
            cursorCache[url] = samples
        }
    }

    /// Clear the cursor cache (called during memory pressure)
    static func clearCursorCache() {
        cacheQueue.async {
            cursorCache.removeAll()
        }
        AppLogger.general.info("SaneVideoCompositor: Cursor cache cleared")
    }

    static func loadCursorSamples(from url: URL) -> [CursorSample]? {
        // Check cache first
        if let cached = getCachedSamples(for: url) { return cached }

        // Load from disk synchronously
        do {
            let data = try Data(contentsOf: url)
            let decoder = JSONDecoder()
            let samples = try decoder.decode([CursorSample].self, from: data)

            // Cache for future use
            cacheSamples(samples, for: url)
            return samples
        } catch {
            AppLogger.general.warning("Failed to load cursor samples from \(url.lastPathComponent): \(error)")
            return nil
        }
    }
    
    // MARK: - Rendering
    
    static func renderCursor(for url: URL, time: Double, renderSize: CGSize) -> CIImage? {
        // Get valid samples
        guard let samples = getCachedSamples(for: url) ?? loadCursorSamples(from: url) else {
            return nil
        }
        
        // Ensure cache (if redundant load happened, it's cheap)
        if getCachedSamples(for: url) == nil {
            cacheSamples(samples, for: url)
        }
        
        if let sample = samples.first(where: { abs($0.timestamp - time) < 0.05 }) {
            let cursorPoint = CGPoint(x: sample.x * renderSize.width, y: sample.y * renderSize.height)
            return renderCursorImage(at: cursorPoint, size: renderSize)
        }
        
        return nil
    }

    private static func renderCursorImage(at point: CGPoint, size _: CGSize) -> CIImage {
        // Create a simple circle cursor using CoreImage or CoreGraphics
        let cursorSize: CGFloat = 40.0

        let colorSpace = CGColorSpace(name: CGColorSpace.sRGB)!
        let bitmapInfo = CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue)

        if let context = CGContext(
            data: nil,
            width: Int(cursorSize),
            height: Int(cursorSize),
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: colorSpace,
            bitmapInfo: bitmapInfo.rawValue
        ) {
            let cursorRect = CGRect(x: 0, y: 0, width: cursorSize, height: cursorSize)
            
            context.setFillColor(NSColor.yellow.withAlphaComponent(0.5).cgColor)
            context.fillEllipse(in: cursorRect)
            context.setStrokeColor(NSColor.white.cgColor)
            context.setLineWidth(2)
            context.strokeEllipse(in: cursorRect.insetBy(dx: 2, dy: 2))

            if let cgImage = context.makeImage() {
                let ciImage = CIImage(cgImage: cgImage)

                // Position it: Center of cursor at 'point'
                let tx = point.x - cursorSize / 2
                let ty = point.y - cursorSize / 2

                return ciImage.transformed(by: CGAffineTransform(translationX: tx, y: ty))
            }
        }

        return CIImage.empty()
    }
}
