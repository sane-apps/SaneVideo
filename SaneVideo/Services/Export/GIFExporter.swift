import AVFoundation
import Foundation
import ImageIO
import UniformTypeIdentifiers

/// Writes a looping GIF from part of a video with AVFoundation frame grabs and ImageIO. No external tools.
enum GIFExporter {
    enum GIFError: LocalizedError {
        case cannotCreateFile
        case noFrames

        var errorDescription: String? {
            switch self {
            case .cannotCreateFile: "Could not create the GIF file."
            case .noFrames: "Could not read any frames from this clip."
            }
        }
    }

    static func export(
        inputURL: URL,
        outputURL: URL,
        fps: Double = 10,
        width: CGFloat = 480,
        startTime: Double = 0,
        duration: Double = 10,
        progress: (@Sendable (Double) -> Void)? = nil
    ) async throws {
        let asset = AVURLAsset(url: inputURL)
        let assetDuration = try await asset.load(.duration).seconds
        let length = max(0.1, min(duration, assetDuration - startTime))
        let frameCount = max(1, Int(length * fps))

        let generator = AVAssetImageGenerator(asset: asset)
        generator.appliesPreferredTrackTransform = true
        generator.maximumSize = CGSize(width: width, height: 0)
        let tolerance = CMTime(seconds: 0.5 / fps, preferredTimescale: 600)
        generator.requestedTimeToleranceBefore = tolerance
        generator.requestedTimeToleranceAfter = tolerance

        guard let destination = CGImageDestinationCreateWithURL(
            outputURL as CFURL, UTType.gif.identifier as CFString, frameCount, nil
        ) else { throw GIFError.cannotCreateFile }
        CGImageDestinationSetProperties(destination, [
            kCGImagePropertyGIFDictionary: [kCGImagePropertyGIFLoopCount: 0]
        ] as CFDictionary)
        let frameProperties = [
            kCGImagePropertyGIFDictionary: [kCGImagePropertyGIFDelayTime: 1.0 / fps]
        ] as CFDictionary

        let times = (0 ..< frameCount).map { CMTime(seconds: startTime + Double($0) / fps, preferredTimescale: 600) }
        var written = 0
        for await result in generator.images(for: times) {
            guard let image = try? result.image else { continue }
            CGImageDestinationAddImage(destination, image, frameProperties)
            written += 1
            progress?(Double(written) / Double(frameCount))
        }
        guard written > 0 else { throw GIFError.noFrames }
        guard CGImageDestinationFinalize(destination) else { throw GIFError.cannotCreateFile }
    }
}
