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

  // OPTIMIZATION: Persist VNSequenceRequestHandler for tracking across frames.
  // Creating a new handler per frame loses tracking state and increases overhead.
  // This handler maintains internal state for VNTrackObjectRequest continuity.
  private var sequenceHandler = VNSequenceRequestHandler()

  // SMOOTHING: EMA filter state for temporal smoothing of face positions
  // Higher alpha = more responsive but more jittery
  // Lower alpha = smoother but more latency
  private var smoothingAlpha: CGFloat = 0.3
  private var smoothedRect: CGRect?

  init() {}

  /// Reset the sequence handler when starting a new tracking sequence.
  /// Call this before beginning a new video analysis or when tracking is lost.
  func resetSequenceHandler() {
    sequenceHandler = VNSequenceRequestHandler()
    smoothedRect = nil  // Reset smoothing state
  }

  /// Configure the smoothing factor for face tracking.
  /// - Parameter alpha: 0.0-1.0, lower = smoother but more latency, higher = more responsive but jittery
  func setSmoothing(alpha: CGFloat) {
    smoothingAlpha = max(0.05, min(1.0, alpha))
  }

  /// Apply Exponential Moving Average (EMA) smoothing to a face rect.
  /// Reduces jitter from frame-to-frame face detection variations.
  private func smoothRect(_ newRect: CGRect) -> CGRect {
    guard let previous = smoothedRect else {
      // First detection - use raw value
      smoothedRect = newRect
      return newRect
    }

    // EMA: smoothed = alpha * new + (1 - alpha) * previous
    let smoothed = CGRect(
      x: smoothingAlpha * newRect.origin.x + (1 - smoothingAlpha) * previous.origin.x,
      y: smoothingAlpha * newRect.origin.y + (1 - smoothingAlpha) * previous.origin.y,
      width: smoothingAlpha * newRect.width + (1 - smoothingAlpha) * previous.width,
      height: smoothingAlpha * newRect.height + (1 - smoothingAlpha) * previous.height
    )

    smoothedRect = smoothed
    return smoothed
  }

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
  /// Uses persisted VNSequenceRequestHandler for tracking continuity.
  func trackFace(in image: CIImage, previousObservation: VNFaceObservation?) async throws
    -> VNFaceObservation? {
    if let previous = previousObservation {
      // Continue tracking existing face using persisted sequence handler
      // OPTIMIZATION: VNSequenceRequestHandler maintains tracking state across frames
      let trackRequest = VNTrackObjectRequest(detectedObjectObservation: previous)
      trackRequest.trackingLevel = .fast

      try sequenceHandler.perform([trackRequest], on: image)

      return trackRequest.results?.first as? VNFaceObservation
    }

    // If tracking failed or no previous, detect new face (one-shot, use image handler)
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
    // OPTIMIZATION: Reset sequence handler for fresh tracking state
    resetSequenceHandler()

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
          let rawRect = CGRect(x: box.minX, y: 1.0 - box.maxY, width: box.width, height: box.height)

          // SMOOTHING: Apply EMA filter to reduce jitter between frames
          let smoothedFaceRect = smoothRect(rawRect)
          results[actualTime] = smoothedFaceRect
        } else {
          lastObservation = nil  // Lost face
          // Reset sequence handler to clear stale tracking state
          resetSequenceHandler()
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
