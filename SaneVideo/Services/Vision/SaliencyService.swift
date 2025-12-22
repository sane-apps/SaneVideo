//
//  SaliencyService.swift
//  SaneVideo
//
//  Apple Vision framework for attention/saliency detection
//  Finds the "interesting" parts of each frame for smart cropping
//

import AVFoundation
import CoreImage
import Foundation
import Vision

/// Result of saliency analysis
struct SaliencyResult: Sendable {
    let attentionPoint: CGPoint // Most important point (0-1 normalized)
    let attentionRect: CGRect // Bounding box of attention area
    let objectnessRect: CGRect? // Object-based saliency (if detected)
    let confidence: Float
}

/// Service for detecting salient (attention-grabbing) regions in video
actor SaliencyService {

    init() {}

    /// Detect the most attention-grabbing region in an image
    /// Uses Apple's attention-based saliency model
    func detectAttention(in image: CIImage) async throws -> SaliencyResult {
        let request = VNGenerateAttentionBasedSaliencyImageRequest()

        let handler = VNImageRequestHandler(ciImage: image)
        try handler.perform([request])

        guard let observation = request.results?.first else {
            throw SaliencyError.noResults
        }

        // Get the salient objects
        let salientObjects = observation.salientObjects ?? []

        if let primaryObject = salientObjects.first {
            // Convert from Vision coordinates (bottom-left origin) to normalized
            let rect = primaryObject.boundingBox
            let centerX = rect.midX
            let centerY = 1.0 - rect.midY // Flip Y

            return SaliencyResult(
                attentionPoint: CGPoint(x: centerX, y: centerY),
                attentionRect: CGRect(
                    x: rect.minX,
                    y: 1.0 - rect.maxY,
                    width: rect.width,
                    height: rect.height
                ),
                objectnessRect: nil,
                confidence: primaryObject.confidence
            )
        }

        // Fallback to center
        return SaliencyResult(
            attentionPoint: CGPoint(x: 0.5, y: 0.5),
            attentionRect: CGRect(x: 0.25, y: 0.25, width: 0.5, height: 0.5),
            objectnessRect: nil,
            confidence: 0.5
        )
    }

    /// Detect objects in an image (object-based saliency)
    func detectObjects(in image: CIImage) async throws -> [CGRect] {
        let request = VNGenerateObjectnessBasedSaliencyImageRequest()

        let handler = VNImageRequestHandler(ciImage: image)
        try handler.perform([request])

        guard let observation = request.results?.first else {
            return []
        }

        return (observation.salientObjects ?? []).map { obj in
            let rect = obj.boundingBox
            return CGRect(
                x: rect.minX,
                y: 1.0 - rect.maxY,
                width: rect.width,
                height: rect.height
            )
        }
    }

    /// Calculate smart crop rectangle for a target aspect ratio
    /// Keeps the attention point in frame
    func calculateSmartCrop(
        for image: CIImage,
        targetAspectRatio: CGFloat, // e.g., 9/16 for vertical, 16/9 for horizontal
        padding _: CGFloat = 0.1
    ) async throws -> CGRect {
        let saliency = try await detectAttention(in: image)

        let imageWidth = image.extent.width
        let imageHeight = image.extent.height
        let sourceAspect = imageWidth / imageHeight

        var cropWidth: CGFloat
        var cropHeight: CGFloat

        if targetAspectRatio > sourceAspect {
            // Target is wider, crop height
            cropWidth = imageWidth
            cropHeight = cropWidth / targetAspectRatio
        } else {
            // Target is taller, crop width
            cropHeight = imageHeight
            cropWidth = cropHeight * targetAspectRatio
        }

        // Center crop on attention point
        let attentionX = saliency.attentionPoint.x * imageWidth
        let attentionY = saliency.attentionPoint.y * imageHeight

        var cropX = attentionX - cropWidth / 2
        var cropY = attentionY - cropHeight / 2

        // Clamp to image bounds
        cropX = max(0, min(imageWidth - cropWidth, cropX))
        cropY = max(0, min(imageHeight - cropHeight, cropY))

        return CGRect(x: cropX, y: cropY, width: cropWidth, height: cropHeight)
    }

    /// Analyze video and return keyframe saliency data for auto-reframe
    /// - Parameters:
    ///   - videoURL: URL of video to analyze
    ///   - sampleInterval: Seconds between frame samples
    ///   - progressHandler: Optional callback with (currentFrame, totalFrames)
    func analyzeVideoForReframe(
        videoURL: URL,
        sampleInterval: TimeInterval = 1.0,
        progressHandler: ((Int, Int) -> Void)? = nil
    ) async throws -> [CMTime: SaliencyResult] {
        let asset = AVURLAsset(url: videoURL)
        let duration = try await asset.load(.duration)
        let totalFrames = Int(duration.seconds / sampleInterval)

        let generator = AVAssetImageGenerator(asset: asset)
        generator.appliesPreferredTrackTransform = true
        generator.requestedTimeToleranceBefore = .zero
        generator.requestedTimeToleranceAfter = .zero

        var results: [CMTime: SaliencyResult] = [:]
        var currentTime = CMTime.zero
        var frameIndex = 0

        await MainActor.run {
            AppLogger.vision.info("📊 Analyzing \(totalFrames) frames for saliency...")
        }

        var skippedFrames = 0

        while currentTime < duration {
            frameIndex += 1
            progressHandler?(frameIndex, totalFrames)

            do {
                let (cgImage, _) = try await generator.image(at: currentTime)
                let ciImage = CIImage(cgImage: cgImage)
                let saliency = try await detectAttention(in: ciImage)
                results[currentTime] = saliency
            } catch {
                // Track skipped frames instead of silently ignoring
                skippedFrames += 1
            }

            currentTime = currentTime + CMTime(seconds: sampleInterval, preferredTimescale: 600)
        }

        // Log summary if frames were skipped
        if skippedFrames > 0 {
            let skipped = skippedFrames
            await MainActor.run {
                AppLogger.vision.warning("📊 Saliency analysis: Skipped \(skipped)/\(totalFrames) frames due to errors")
            }
        }

        return results
    }
}

// MARK: - Errors

enum SaliencyError: Error, LocalizedError {
    case noResults

    var errorDescription: String? {
        switch self {
        case .noResults: return "No saliency data detected"
        }
    }
}
