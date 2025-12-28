//
//  VisionServicesTests.swift
//  SaneVideoTests
//
//  Tests for Vision services - coordinate handling, result types, and basic functionality
//

import Testing
import CoreImage
import Vision
@testable import SaneVideo

@Suite("Vision Services Tests")
struct VisionServicesTests {

    // MARK: - Coordinate Conversion Tests

    @Test("Vision coordinate Y-flip produces correct top-left origin")
    func visionCoordinateFlip() {
        // Arrange - Vision uses bottom-left origin (0,0 at bottom-left)
        let visionRect = CGRect(x: 0.1, y: 0.2, width: 0.3, height: 0.4)

        // Act - Convert to top-left origin
        let flippedRect = CGRect(
            x: visionRect.minX,
            y: 1.0 - visionRect.maxY,
            width: visionRect.width,
            height: visionRect.height
        )

        // Assert
        #expect(flippedRect.minX == 0.1, "X should remain unchanged")
        #expect(abs(flippedRect.minY - 0.4) < 0.001, "Y should be flipped: 1.0 - 0.6 = 0.4")
        #expect(flippedRect.width == 0.3, "Width should remain unchanged")
        #expect(flippedRect.height == 0.4, "Height should remain unchanged")
    }

    @Test("Vision point Y-flip produces correct coordinates")
    func visionPointFlip() {
        // Arrange - Vision point at bottom of image
        let visionPoint = CGPoint(x: 0.5, y: 0.1)

        // Act - Convert to top-left origin
        let flippedPoint = CGPoint(x: visionPoint.x, y: 1.0 - visionPoint.y)

        // Assert
        #expect(flippedPoint.x == 0.5, "X should remain unchanged")
        #expect(abs(flippedPoint.y - 0.9) < 0.001, "Y should be flipped: 1.0 - 0.1 = 0.9")
    }

    // MARK: - SaliencyResult Tests

    @Test("SaliencyResult stores normalized coordinates correctly")
    func saliencyResultCoordinates() {
        // Arrange & Act
        let result = SaliencyResult(
            attentionPoint: CGPoint(x: 0.5, y: 0.5),
            attentionRect: CGRect(x: 0.2, y: 0.2, width: 0.6, height: 0.6),
            objectnessRect: nil,
            confidence: 0.95
        )

        // Assert
        #expect(result.attentionPoint.x == 0.5)
        #expect(result.attentionPoint.y == 0.5)
        #expect(result.confidence == 0.95)
        #expect(result.attentionRect.width == 0.6)
    }

    // MARK: - FaceDetection Tests

    @Test("FaceDetection calculates face angle from eye positions")
    func faceDetectionAngle() {
        // Arrange - Horizontal eyes (no tilt)
        let horizontalFace = FaceDetection(
            boundingBox: CGRect(x: 0.3, y: 0.3, width: 0.4, height: 0.4),
            confidence: 0.9,
            leftEye: CGPoint(x: 0.35, y: 0.5),
            rightEye: CGPoint(x: 0.65, y: 0.5),
            nose: nil,
            mouth: nil
        )

        // Act
        let angle = horizontalFace.faceAngle

        // Assert - Horizontal should be ~0 radians
        #expect(angle != nil)
        #expect(abs(angle! - 0.0) < 0.01, "Horizontal eyes should produce ~0 angle")
    }

    @Test("FaceDetection returns nil angle without eye data")
    func faceDetectionNilAngle() {
        // Arrange - No eye positions
        let noEyesFace = FaceDetection(
            boundingBox: CGRect(x: 0.3, y: 0.3, width: 0.4, height: 0.4),
            confidence: 0.9,
            leftEye: nil,
            rightEye: nil,
            nose: nil,
            mouth: nil
        )

        // Act & Assert
        #expect(noEyesFace.faceAngle == nil)
    }

    // MARK: - RecognizedText Tests

    @Test("RecognizedText stores text and bounding box")
    func recognizedTextStorage() {
        // Arrange & Act
        let text = RecognizedText(
            text: "Hello World",
            boundingBox: CGRect(x: 0.1, y: 0.1, width: 0.8, height: 0.1),
            confidence: 0.98,
            time: .zero
        )

        // Assert
        #expect(text.text == "Hello World")
        #expect(text.confidence == 0.98)
        #expect(text.boundingBox.width == 0.8)
    }

    // MARK: - BodyPose Tests

    @Test("JointPosition stores position and confidence")
    func jointPositionStorage() {
        // Arrange & Act
        let joint = JointPosition(
            position: CGPoint(x: 0.5, y: 0.7),
            confidence: 0.85
        )

        // Assert
        #expect(joint.position.x == 0.5)
        #expect(joint.position.y == 0.7)
        #expect(joint.confidence == 0.85)
    }

    // MARK: - Configuration Tests

    @Test("MagicFeatures configuration has reasonable defaults")
    func magicFeaturesConfiguration() {
        // Assert confidence thresholds are in valid range
        #expect(AppConstants.MagicFeatures.faceDetectionConfidence >= 0.0)
        #expect(AppConstants.MagicFeatures.faceDetectionConfidence <= 1.0)

        #expect(AppConstants.MagicFeatures.bodyPoseConfidence >= 0.0)
        #expect(AppConstants.MagicFeatures.bodyPoseConfidence <= 1.0)

        // Assert timeouts are positive
        #expect(AppConstants.MagicFeatures.voiceIsolationTimeout > 0)
        #expect(AppConstants.MagicFeatures.videoWriterFinishTimeout > 0)
        #expect(AppConstants.MagicFeatures.exportFinishTimeout > 0)

        // Assert processing limits are reasonable
        #expect(AppConstants.MagicFeatures.maxAudioFileSize > 0)
        #expect(AppConstants.MagicFeatures.visionFrameSkipInterval >= 1)
    }
}
