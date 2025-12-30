//
//  VisionOrchestratorTests.swift
//  SaneVideoTests
//
//  Tests for VisionOrchestrator data structures and initialization
//

import Testing
import Foundation
import CoreMedia
@testable import SaneVideo

@Suite("Vision Orchestrator Tests")
struct VisionOrchestratorTests {

    // MARK: - VisionAnalysisConfig Tests

    @Test("VisionAnalysisConfig default values are all false")
    func configDefaultValues() {
        // Arrange & Act
        let config = VisionAnalysisConfig()

        // Assert
        #expect(config.detectText == false)
        #expect(config.detectFaces == false)
        #expect(config.detectSaliency == false)
        #expect(config.detectPrivacy == false)
    }

    @Test("VisionAnalysisConfig can enable text detection")
    func configEnableTextDetection() {
        // Arrange & Act
        var config = VisionAnalysisConfig()
        config.detectText = true

        // Assert
        #expect(config.detectText == true)
    }

    @Test("VisionAnalysisConfig can enable face detection")
    func configEnableFaceDetection() {
        // Arrange & Act
        var config = VisionAnalysisConfig()
        config.detectFaces = true

        // Assert
        #expect(config.detectFaces == true)
    }

    @Test("VisionAnalysisConfig can enable saliency detection")
    func configEnableSaliencyDetection() {
        // Arrange & Act
        var config = VisionAnalysisConfig()
        config.detectSaliency = true

        // Assert
        #expect(config.detectSaliency == true)
    }

    @Test("VisionAnalysisConfig can enable privacy detection")
    func configEnablePrivacyDetection() {
        // Arrange & Act
        var config = VisionAnalysisConfig()
        config.detectPrivacy = true

        // Assert
        #expect(config.detectPrivacy == true)
    }

    @Test("VisionAnalysisConfig can enable multiple detections")
    func configEnableMultipleDetections() {
        // Arrange & Act
        var config = VisionAnalysisConfig()
        config.detectText = true
        config.detectFaces = true
        config.detectSaliency = true

        // Assert
        #expect(config.detectText == true)
        #expect(config.detectFaces == true)
        #expect(config.detectSaliency == true)
        #expect(config.detectPrivacy == false)
    }

    // MARK: - VisionAnalysisResult Tests

    @Test("VisionAnalysisResult default values are empty")
    func resultDefaultValues() {
        // Arrange & Act
        let result = VisionAnalysisResult()

        // Assert
        #expect(result.detectedText.isEmpty)
        #expect(result.faces.isEmpty)
        #expect(result.saliency.isEmpty)
        #expect(result.privacyRegions.isEmpty)
    }

    @Test("VisionAnalysisResult merge combines detectedText")
    func resultMergeCombinesText() {
        // Arrange
        var result1 = VisionAnalysisResult()
        var result2 = VisionAnalysisResult()

        // Create sample recognized text
        let text1 = RecognizedText(
            text: "Hello",
            boundingBox: CGRect(x: 0, y: 0, width: 0.5, height: 0.1), // Normalized 0-1
            confidence: 0.95,
            time: CMTime(seconds: 1.0, preferredTimescale: 600)
        )
        let text2 = RecognizedText(
            text: "World",
            boundingBox: CGRect(x: 0, y: 0.2, width: 0.5, height: 0.1), // Normalized 0-1
            confidence: 0.90,
            time: CMTime(seconds: 2.0, preferredTimescale: 600)
        )

        result1.detectedText = [text1]
        result2.detectedText = [text2]

        // Act
        result1.merge(other: result2)

        // Assert
        #expect(result1.detectedText.count == 2)
    }

    @Test("VisionAnalysisResult merge combines faces")
    func resultMergeCombinesFaces() {
        // Arrange
        var result1 = VisionAnalysisResult()
        var result2 = VisionAnalysisResult()

        let time1 = CMTime(seconds: 1.0, preferredTimescale: 600)
        let time2 = CMTime(seconds: 2.0, preferredTimescale: 600)

        result1.faces = [time1: CGRect(x: 100, y: 100, width: 50, height: 50)]
        result2.faces = [time2: CGRect(x: 200, y: 200, width: 60, height: 60)]

        // Act
        result1.merge(other: result2)

        // Assert
        #expect(result1.faces.count == 2)
        #expect(result1.faces[time1] != nil)
        #expect(result1.faces[time2] != nil)
    }

    @Test("VisionAnalysisResult merge overwrites duplicate face timestamps")
    func resultMergeOverwritesDuplicateFaces() {
        // Arrange
        var result1 = VisionAnalysisResult()
        var result2 = VisionAnalysisResult()

        let sameTime = CMTime(seconds: 1.0, preferredTimescale: 600)

        result1.faces = [sameTime: CGRect(x: 100, y: 100, width: 50, height: 50)]
        result2.faces = [sameTime: CGRect(x: 200, y: 200, width: 60, height: 60)]

        // Act
        result1.merge(other: result2)

        // Assert - new value should win
        #expect(result1.faces.count == 1)
        #expect(result1.faces[sameTime]?.origin.x == 200)
    }

    @Test("VisionAnalysisResult merge combines privacyRegions")
    func resultMergeCombinesPrivacyRegions() {
        // Arrange
        var result1 = VisionAnalysisResult()
        var result2 = VisionAnalysisResult()

        let region1 = PrivacyRegion(
            timeRange: CMTimeRange(start: .zero, duration: CMTime(seconds: 1, preferredTimescale: 600)),
            frame: CGRect(x: 0, y: 0, width: 0.5, height: 0.5) // Normalized rect
        )
        let region2 = PrivacyRegion(
            timeRange: CMTimeRange(start: CMTime(seconds: 1, preferredTimescale: 600), duration: CMTime(seconds: 1, preferredTimescale: 600)),
            frame: CGRect(x: 0.5, y: 0.5, width: 0.3, height: 0.3) // Normalized rect
        )

        result1.privacyRegions = [region1]
        result2.privacyRegions = [region2]

        // Act
        result1.merge(other: result2)

        // Assert
        #expect(result1.privacyRegions.count == 2)
    }

    // MARK: - VisionOrchestrator Initialization Tests

    @Test("VisionOrchestrator can be initialized")
    func orchestratorInitialization() async {
        // Arrange & Act
        let orchestrator = VisionOrchestrator()

        // Assert - no crash
        _ = orchestrator
        #expect(Bool(true))
    }

    @Test("VisionOrchestrator warmup completes without error")
    func orchestratorWarmup() async {
        // Arrange
        let orchestrator = VisionOrchestrator()

        // Act - warmup is fire-and-forget, just verify no crash
        await orchestrator.warmup()

        // Assert - if we get here, warmup didn't crash
        #expect(Bool(true))
    }
}
