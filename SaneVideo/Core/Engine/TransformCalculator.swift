//
//  TransformCalculator.swift
//  SaneVideo
//
//  Created by SaneVideo Refactor
//

import AVFoundation
import CoreMedia

/// Helper for calculating video transforms (rotation, aspect fit, user pan/zoom)
enum TransformCalculator {
    
    /// Calculate the final transform for a video asset track
    static func calculateTransform(
        assetTrack: AVAssetTrack,
        rotation: VideoClip.Rotation,
        userTransform: VideoClip.Transform,
        renderSize: CGSize
    ) async throws -> CGAffineTransform {
        let preferredTransform = try await assetTrack.load(.preferredTransform)
        let naturalSize = try await assetTrack.load(.naturalSize)

        AppLogger.composition.debug("CalculateTransform - Preferred: \(preferredTransform), Natural: \(naturalSize), Rotation: \(rotation.rawValue)")

        // 1. Start with the asset's preferred transform (handles camera orientation)
        var t = preferredTransform

        // 2. Apply User Rotation (concatenated on top of preferred)
        if rotation != .none {
            t = t.concatenating(CGAffineTransform(rotationAngle: rotation.radians))
        }

        // 3. Re-align to origin (0,0) logic
        let fullRect = CGRect(origin: .zero, size: naturalSize)
        let transformedRect = fullRect.applying(t)

        // Translate to zero origin
        let tx = -transformedRect.origin.x
        let ty = -transformedRect.origin.y
        t = t.concatenating(CGAffineTransform(translationX: tx, y: ty))

        // 4. Calculate Aspect Fit into Render Size
        let finalWidth = transformedRect.width
        let finalHeight = transformedRect.height

        // Prevent division by zero
        guard finalWidth > 0, finalHeight > 0 else { return t }

        let ratio = min(renderSize.width / finalWidth, renderSize.height / finalHeight)

        let newWidth = finalWidth * ratio
        let newHeight = finalHeight * ratio

        // Center in Render Buffer
        let xOffset = (renderSize.width - newWidth) / 2
        let yOffset = (renderSize.height - newHeight) / 2

        // 5. Apply Base Layout (Aspect Fit + Center)
        var finalT = t
            .concatenating(CGAffineTransform(scaleX: ratio, y: ratio))
            .concatenating(CGAffineTransform(translationX: xOffset, y: yOffset))

        // 6. Apply User Interactive Transform (Pan & Zoom)
        if userTransform.scale != 1.0 {
            let centerX = renderSize.width / 2
            let centerY = renderSize.height / 2

            finalT = finalT
                .concatenating(CGAffineTransform(translationX: -centerX, y: -centerY))
                .concatenating(CGAffineTransform(scaleX: userTransform.scale, y: userTransform.scale))
                .concatenating(CGAffineTransform(translationX: centerX, y: centerY))
        }

        if userTransform.offset != .zero {
            let moveX = userTransform.offset.x * renderSize.width
            let moveY = userTransform.offset.y * renderSize.height

            finalT = finalT.concatenating(CGAffineTransform(translationX: moveX, y: moveY))
        }

        return finalT
    }
}
