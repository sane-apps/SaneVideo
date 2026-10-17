import AppKit
import CoreImage
import Foundation
import Vision
import CoreVideo
import AVFoundation

/// Separates person from background for blur/replacement effects
/// Note: Does not conform to PersonSegmentationServiceProtocol due to Swift 6 actor isolation rules.
actor PersonSegmentationService {

    private let ciContext: CIContext

    init(ciContext: CIContext) {
        self.ciContext = ciContext
    }

    // MARK: - Public API

    /// Reusable request for video frame processing (improves performance)
    private var cachedRequest: VNGeneratePersonSegmentationRequest?

    /// - Parameters:
    ///   - quality: Quality level (.fast for video, .balanced default, .accurate for stills)
    ///   - reuseRequest: If true, reuses cached request (better for video frames)
    /// Returns a grayscale mask where white = person, black = background
    func generateMask(
        for image: CIImage,
        quality: VNGeneratePersonSegmentationRequest.QualityLevel = .balanced,
        reuseRequest: Bool = false
    ) async throws -> CIImage {
        let request: VNGeneratePersonSegmentationRequest

        if reuseRequest {
            if let cached = cachedRequest {
                request = cached
            } else {
                request = VNGeneratePersonSegmentationRequest()
                request.outputPixelFormat = kCVPixelFormatType_OneComponent8
                cachedRequest = request
            }
        } else {
            request = VNGeneratePersonSegmentationRequest()
            request.outputPixelFormat = kCVPixelFormatType_OneComponent8
        }

        if request.qualityLevel != quality {
            request.qualityLevel = quality
        }

        let handler = VNImageRequestHandler(ciImage: image)
        try handler.perform([request])

        guard let observation = request.results?.first else {
            throw SegmentationError.noResults
        }

        let maskImage = CIImage(cvPixelBuffer: observation.pixelBuffer)

        let scaleX = image.extent.width / maskImage.extent.width
        let scaleY = image.extent.height / maskImage.extent.height
        let scaledMask = maskImage.transformed(by: CGAffineTransform(scaleX: scaleX, y: scaleY))

        return scaledMask
    }

    /// Call when done processing video.
    func clearCache() {
        cachedRequest = nil
    }

    /// Apply background blur to image, keeping person sharp
    func applyBackgroundBlur(to image: CIImage, blurRadius: Float = 20, reuseRequest: Bool = true) async throws -> CIImage {
        let mask = try await generateMask(for: image, reuseRequest: reuseRequest)

        guard let blurFilter = CIFilter(name: "CIGaussianBlur") else {
            throw SegmentationError.filterFailed
        }
        blurFilter.setValue(image, forKey: kCIInputImageKey)
        blurFilter.setValue(blurRadius, forKey: kCIInputRadiusKey)

        guard let blurredImage = blurFilter.outputImage else {
            throw SegmentationError.filterFailed
        }

        guard let blendFilter = CIFilter(name: "CIBlendWithMask") else {
            throw SegmentationError.filterFailed
        }
        blendFilter.setValue(image, forKey: kCIInputImageKey)
        blendFilter.setValue(blurredImage.cropped(to: image.extent), forKey: kCIInputBackgroundImageKey)
        blendFilter.setValue(mask, forKey: kCIInputMaskImageKey)

        return blendFilter.outputImage ?? image
    }

    func replaceBackground(in image: CIImage, with color: NSColor, reuseRequest: Bool = true) async throws -> CIImage {
        let mask = try await generateMask(for: image, reuseRequest: reuseRequest)

        let colorImage = CIImage(color: CIColor(color: color)!).cropped(to: image.extent)

        guard let blendFilter = CIFilter(name: "CIBlendWithMask") else {
            throw SegmentationError.filterFailed
        }
        blendFilter.setValue(image, forKey: kCIInputImageKey)
        blendFilter.setValue(colorImage, forKey: kCIInputBackgroundImageKey)
        blendFilter.setValue(mask, forKey: kCIInputMaskImageKey)

        return blendFilter.outputImage ?? image
    }

    func replaceBackground(in image: CIImage, with backgroundImage: CIImage, reuseRequest: Bool = true) async throws -> CIImage {
        let mask = try await generateMask(for: image, reuseRequest: reuseRequest)

        let scaleX = image.extent.width / backgroundImage.extent.width
        let scaleY = image.extent.height / backgroundImage.extent.height
        let scale = max(scaleX, scaleY)
        let scaledBackground = backgroundImage.transformed(by: CGAffineTransform(scaleX: scale, y: scale))
            .cropped(to: image.extent)

        guard let blendFilter = CIFilter(name: "CIBlendWithMask") else {
            throw SegmentationError.filterFailed
        }
        blendFilter.setValue(image, forKey: kCIInputImageKey)
        blendFilter.setValue(scaledBackground, forKey: kCIInputBackgroundImageKey)
        blendFilter.setValue(mask, forKey: kCIInputMaskImageKey)

        return blendFilter.outputImage ?? image
    }

    /// Apply to NSImage (for thumbnails/previews)
    func applyBackgroundBlur(to nsImage: NSImage, blurRadius: Float = 20) async throws -> NSImage {
        guard let cgImage = nsImage.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
            throw SegmentationError.invalidImage
        }

        let ciImage = CIImage(cgImage: cgImage)
        let processed = try await applyBackgroundBlur(to: ciImage, blurRadius: blurRadius)

        guard let outputCGImage = ciContext.createCGImage(processed, from: processed.extent) else {
            throw SegmentationError.renderFailed
        }

        return NSImage(cgImage: outputCGImage, size: nsImage.size)
    }
}

// MARK: - Errors

enum SegmentationError: LocalizedError {
    case noResults
    case filterFailed
    case invalidImage
    case renderFailed

    var errorDescription: String? {
        switch self {
        case .noResults: return "No person detected in image"
        case .filterFailed: return "Failed to apply filter"
        case .invalidImage: return "Invalid image format"
        case .renderFailed: return "Failed to render result"
        }
    }
}
