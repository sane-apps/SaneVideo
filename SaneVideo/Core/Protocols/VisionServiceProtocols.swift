// Protocols for Vision services to enable mocking in tests

import AVFoundation
import AppKit
import CoreImage
import Vision

// MARK: - Face Tracking

/// @mockable
protocol FaceTrackingServiceProtocol: Sendable {
    /// Detect all faces in an image
    /// Returns array of normalized face rectangles (0-1 coordinate space, top-left origin)
    func detectFaces(in image: CIImage) async throws -> [CGRect]

    /// Detect faces with landmarks (eyes, nose, mouth)
    func detectFacesWithLandmarks(in image: CIImage) async throws -> [FaceDetection]

    /// Calculate optimal crop rect to center face(s) in frame
    func calculateAutoFrameRect(
        faces: [CGRect],
        imageSize: CGSize,
        targetAspectRatio: CGFloat,
        padding: CGFloat
    ) -> CGRect

    /// Analyze video and return face keyframes for auto-reframe
    func analyzeVideo(
        videoURL: URL,
        sampleInterval: TimeInterval
    ) async throws -> [CMTime: CGRect]
}

// MARK: - Saliency

/// @mockable
protocol SaliencyServiceProtocol: Sendable {
    /// Detect the most attention-grabbing region in an image
    func detectAttention(in image: CIImage) async throws -> SaliencyResult

    /// Detect objects in an image (object-based saliency)
    func detectObjects(in image: CIImage) async throws -> [CGRect]

    /// Calculate smart crop rectangle for a target aspect ratio
    func calculateSmartCrop(
        for image: CIImage,
        targetAspectRatio: CGFloat,
        padding: CGFloat
    ) async throws -> CGRect

    /// Analyze video and return keyframe saliency data for auto-reframe
    func analyzeVideoForReframe(
        videoURL: URL,
        sampleInterval: TimeInterval,
        progressHandler: (@Sendable (Int, Int) -> Void)?
    ) async throws -> [CMTime: SaliencyResult]
}

// MARK: - Person Segmentation

/// @mockable
protocol PersonSegmentationServiceProtocol: Sendable {
    /// Generate a segmentation mask for persons in the image
    func generateMask(
        for image: CIImage,
        quality: VNGeneratePersonSegmentationRequest.QualityLevel,
        reuseRequest: Bool
    ) async throws -> CIImage

    /// Clear cached request (call when done processing video)
    func clearCache() async

    /// Apply background blur to image, keeping person sharp
    func applyBackgroundBlur(
        to image: CIImage,
        blurRadius: Float,
        reuseRequest: Bool
    ) async throws -> CIImage

    /// Replace background with a solid color
    func replaceBackground(
        in image: CIImage,
        with color: NSColor,
        reuseRequest: Bool
    ) async throws -> CIImage

    /// Replace background with an image
    func replaceBackground(
        in image: CIImage,
        with backgroundImage: CIImage,
        reuseRequest: Bool
    ) async throws -> CIImage
}

// MARK: - Text Recognition

// MARK: - Body Pose

// MARK: - Vision Orchestrator

