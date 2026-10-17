import AVFoundation
import CoreMedia

enum TransformCalculator {
    
    static func calculateTransform(
        assetTrack: AVAssetTrack,
        rotation: VideoClip.Rotation,
        userTransform: VideoClip.Transform,
        renderSize: CGSize
    ) async throws -> CGAffineTransform {
        let preferredTransform = try await assetTrack.load(.preferredTransform)
        let naturalSize = try await assetTrack.load(.naturalSize)

        AppLogger.composition.debug("CalculateTransform - Preferred: \(preferredTransform), Natural: \(naturalSize), Rotation: \(rotation.rawValue)")

        // The preferred transform handles camera orientation.
        var t = preferredTransform

        // User rotation goes on top of the preferred transform.
        if rotation != .none {
            t = t.concatenating(CGAffineTransform(rotationAngle: rotation.radians))
        }

        let fullRect = CGRect(origin: .zero, size: naturalSize)
        let transformedRect = fullRect.applying(t)

        let tx = -transformedRect.origin.x
        let ty = -transformedRect.origin.y
        t = t.concatenating(CGAffineTransform(translationX: tx, y: ty))

        let finalWidth = transformedRect.width
        let finalHeight = transformedRect.height

        guard finalWidth > 0, finalHeight > 0 else { return t }

        let ratio = min(renderSize.width / finalWidth, renderSize.height / finalHeight)

        let newWidth = finalWidth * ratio
        let newHeight = finalHeight * ratio

        let xOffset = (renderSize.width - newWidth) / 2
        let yOffset = (renderSize.height - newHeight) / 2

        var finalT = t
            .concatenating(CGAffineTransform(scaleX: ratio, y: ratio))
            .concatenating(CGAffineTransform(translationX: xOffset, y: yOffset))

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
