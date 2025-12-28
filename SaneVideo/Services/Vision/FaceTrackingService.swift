//
//  FaceTrackingService.swift
//  SaneVideo
//
//  Uses Apple's Vision framework for face detection and tracking
//  Enables auto-framing to keep speakers centered
//  Auto-improves with each macOS update
//

import AVFoundation
import AppKit
import CoreImage
import Foundation
import Vision

/// Face tracking using Vision framework
/// Detects faces and provides coordinates for auto-framing
/// Note: Does not conform to FaceTrackingServiceProtocol due to Swift 6 actor isolation rules.
/// Use FaceTrackingServiceProtocolMock for testing.
actor FaceTrackingService {

  init() {}

  // MARK: - Public API

  /// Detect all faces in an image
  /// Returns array of normalized face rectangles (0-1 coordinate space)
  func detectFaces(in image: CIImage) async throws -> [CGRect] {
    let request = VNDetectFaceRectanglesRequest()
    let handler = VNImageRequestHandler(ciImage: image)

    try handler.perform([request])

    guard let results = request.results else {
      return []
    }

    return results.map { observation in
      let box = observation.boundingBox
      // CRITICAL: Flip Y from Vision's bottom-left origin to top-left origin
      return CGRect(x: box.minX, y: 1.0 - box.maxY, width: box.width, height: box.height)
    }
  }

  /// Detect faces with landmarks (eyes, nose, mouth)
  func detectFacesWithLandmarks(in image: CIImage) async throws -> [FaceDetection] {
    let request = VNDetectFaceLandmarksRequest()
    let handler = VNImageRequestHandler(ciImage: image)

    try handler.perform([request])

    guard let results = request.results else {
      return []
    }

    return results.compactMap { observation -> FaceDetection? in
      let box = observation.boundingBox
      let faceRect = CGRect(
        x: box.minX,
        y: 1.0 - box.maxY,  // Flip Y
        width: box.width,
        height: box.height
      )

      return FaceDetection(
        boundingBox: faceRect,
        confidence: observation.confidence,
        leftEye: observation.landmarks?.leftEye?.normalizedPoints.first,
        rightEye: observation.landmarks?.rightEye?.normalizedPoints.first,
        nose: observation.landmarks?.nose?.normalizedPoints.first,
        mouth: observation.landmarks?.innerLips?.normalizedPoints.first
      )
    }
  }

  /// Calculate optimal crop rect to center face(s) in frame
  /// Returns a rect in the coordinate space of the input image
  func calculateAutoFrameRect(
    faces: [CGRect],
    imageSize: CGSize,
    targetAspectRatio: CGFloat = 16 / 9,
    padding: CGFloat = 0.3  // Extra space around faces
  ) -> CGRect {
    guard !faces.isEmpty else {
      // No faces - return full frame
      return CGRect(origin: .zero, size: imageSize)
    }

    // Find bounding box containing all faces
    var minX = CGFloat.infinity
    var minY = CGFloat.infinity
    var maxX = CGFloat.zero
    var maxY = CGFloat.zero

    for face in faces {
      // Convert from normalized to image coordinates
      let faceRect = CGRect(
        x: face.origin.x * imageSize.width,
        y: face.origin.y * imageSize.height,
        width: face.width * imageSize.width,
        height: face.height * imageSize.height
      )

      minX = min(minX, faceRect.minX)
      minY = min(minY, faceRect.minY)
      maxX = max(maxX, faceRect.maxX)
      maxY = max(maxY, faceRect.maxY)
    }

    // Add padding
    let faceWidth = maxX - minX
    let faceHeight = maxY - minY
    let paddedWidth = faceWidth * (1 + padding * 2)
    let paddedHeight = faceHeight * (1 + padding * 2)

    // Calculate center
    let centerX = (minX + maxX) / 2
    let centerY = (minY + maxY) / 2

    // Calculate crop size maintaining aspect ratio
    var cropWidth = paddedWidth
    var cropHeight = cropWidth / targetAspectRatio

    if cropHeight < paddedHeight {
      cropHeight = paddedHeight
      cropWidth = cropHeight * targetAspectRatio
    }

    // Ensure crop doesn't exceed image bounds
    cropWidth = min(cropWidth, imageSize.width)
    cropHeight = min(cropHeight, imageSize.height)

    // Calculate crop origin (centered on faces)
    var cropX = centerX - cropWidth / 2
    var cropY = centerY - cropHeight / 2

    // Clamp to image bounds
    cropX = max(0, min(cropX, imageSize.width - cropWidth))
    cropY = max(0, min(cropY, imageSize.height - cropHeight))

    return CGRect(x: cropX, y: cropY, width: cropWidth, height: cropHeight)
  }

  /// Track a face across frames (for smooth following)
  func trackFace(in image: CIImage, previousObservation: VNFaceObservation?) async throws
    -> VNFaceObservation? {
    if let previous = previousObservation {
      // Continue tracking existing face
      let trackRequest = VNTrackObjectRequest(detectedObjectObservation: previous)
      trackRequest.trackingLevel = .fast

      let handler = VNImageRequestHandler(ciImage: image)
      try handler.perform([trackRequest])

      return trackRequest.results?.first as? VNFaceObservation
    }

    // If tracking failed or no previous, detect new face
    let detectRequest = VNDetectFaceRectanglesRequest()
    let handler = VNImageRequestHandler(ciImage: image)
    try handler.perform([detectRequest])

    // Return largest face
    return detectRequest.results?.max(by: {
      $0.boundingBox.width * $0.boundingBox.height < $1.boundingBox.width * $1.boundingBox.height
    })
  }

  /// Smooth face position over time (reduces jitter)
  /// Analyze video to track faces over time for auto-framing
  /// - Returns: Dictionary of timestamps to face bounding boxes (normalized)
  func analyzeVideo(
    videoURL: URL,
    sampleInterval: TimeInterval = 0.5,
    progressHandler: (@Sendable (Double) -> Void)? = nil
  ) async throws -> [CMTime: CGRect] {
    let asset = AVURLAsset(url: videoURL)
    let duration = try await asset.load(.duration)
    let generator = AVAssetImageGenerator(asset: asset)
    generator.appliesPreferredTrackTransform = true
    generator.requestedTimeToleranceBefore = .zero
    generator.requestedTimeToleranceAfter = .zero

    var results: [CMTime: CGRect] = [:]
    var currentTime = CMTime.zero
    var lastObservation: VNFaceObservation?

    // Loop through video
    while currentTime < duration {
      // Update progress
      progressHandler?(currentTime.seconds / duration.seconds)

      do {
        let (cgImage, actualTime) = try await generator.image(at: currentTime)
        let ciImage = CIImage(cgImage: cgImage)

        // Track or Detect
        if let observation = try await trackFace(in: ciImage, previousObservation: lastObservation) {
          lastObservation = observation
          // CRITICAL: Flip Y from Vision's bottom-left origin to top-left origin
          let box = observation.boundingBox
          results[actualTime] = CGRect(x: box.minX, y: 1.0 - box.maxY, width: box.width, height: box.height)
        } else {
          lastObservation = nil  // Lost face
        }
      } catch {
        AppLogger.vision.warning("Face tracking failed at \(currentTime.seconds)s: \(error)")
      }

      currentTime = currentTime + CMTime(seconds: sampleInterval, preferredTimescale: 600)
    }

    progressHandler?(1.0)
    return results
  }
}

// MARK: - Face Detection Result

struct FaceDetection {
  let boundingBox: CGRect
  let confidence: Float
  let leftEye: CGPoint?
  let rightEye: CGPoint?
  let nose: CGPoint?
  let mouth: CGPoint?

  /// Calculate face rotation based on eye positions
  var faceAngle: CGFloat? {
    guard let left = leftEye, let right = rightEye else { return nil }
    return atan2(right.y - left.y, right.x - left.x)
  }
}
