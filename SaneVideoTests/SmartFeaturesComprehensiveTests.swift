//
//  SmartFeaturesComprehensiveTests.swift
//  SaneVideoTests
//
//  Comprehensive tests for all smart features
//

import AVFoundation
import XCTest
@testable import SaneVideo

@MainActor
final class SmartFeaturesComprehensiveTests: XCTestCase {
    
    // MARK: - Test Setup
    
    var tempDir: URL {
        FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    }
    
    func createTestVideo() -> URL {
        // Try to use test asset if available
        let testAsset = TestEnvironment.mockAssetURL
        if FileManager.default.fileExists(atPath: testAsset.path) {
            return testAsset
        }
        
        // Fallback: create a temporary file
        let url = tempDir.appendingPathComponent("test_video.mp4")
        FileManager.default.createFile(atPath: url.path, contents: Data(), attributes: nil)
        return url
    }
    
    override func setUpWithError() throws {
        continueAfterFailure = false
        
        // Set test timeout to prevent hanging
        if #available(macOS 13.0, *) {
            executionTimeAllowance = 60.0 // 1 minute max per test
        }
    }
    
    // MARK: - Magic Fix Tests
    
    func testMagicFixDefaultOptions() {
        let options = MagicFixOptions()
        
        XCTAssertTrue(options.removeSilence)
        XCTAssertTrue(options.removeFillers)
        XCTAssertTrue(options.generateCaptions)
    }
    
    func testMagicFixPresets() {
        let minimal = MagicFixOptions.minimal
        let proClean = MagicFixOptions.proClean
        let socialMedia = MagicFixOptions.socialMedia
        
        // Minimal preset
        XCTAssertEqual(minimal.presetName, "Minimal Fix")
        XCTAssertTrue(minimal.removeSilence)
        
        // Pro Clean preset
        XCTAssertEqual(proClean.presetName, "Pro Clean-up")
        XCTAssertTrue(proClean.removeSilence)
        XCTAssertTrue(proClean.removeFillers)
        XCTAssertTrue(proClean.enhanceAudio)
        
        // Social Media preset
        XCTAssertEqual(socialMedia.presetName, "Social Media Ready")
        XCTAssertTrue(socialMedia.removeSilence)
    }
    
    func testMagicFixPresetDescriptions() {
        let minimal = MagicFixOptions.minimal
        let proClean = MagicFixOptions.proClean
        let socialMedia = MagicFixOptions.socialMedia
        
        XCTAssertFalse(minimal.presetDescription.isEmpty)
        XCTAssertFalse(proClean.presetDescription.isEmpty)
        XCTAssertFalse(socialMedia.presetDescription.isEmpty)
    }
    
    func testMagicFixSilenceThreshold() {
        var options = MagicFixOptions()
        
        // Test default threshold
        XCTAssertEqual(options.silenceThreshold, -45.0)
        
        // Test threshold modification
        options.silenceThreshold = -30.0
        XCTAssertEqual(options.silenceThreshold, -30.0)
    }
    
    func testMagicFixMinSilenceDuration() {
        var options = MagicFixOptions()
        
        // Test default duration
        XCTAssertEqual(options.minSilenceDuration, 0.3)
        
        // Test duration modification
        options.minSilenceDuration = 0.5
        XCTAssertEqual(options.minSilenceDuration, 0.5)
    }
    
    func testMagicFixKeepRangesEmpty() {
        let duration = CMTime(seconds: 10, preferredTimescale: 600)
        let removals: [CMTimeRange] = []
        
        let keepRanges = MagicFixService.calculateKeepRanges(removals: removals, duration: duration)
        
        XCTAssertEqual(keepRanges.count, 1)
        XCTAssertEqual(keepRanges.first?.start.seconds, 0)
        XCTAssertEqual(keepRanges.first?.end.seconds, 10)
    }
    
    func testMagicFixKeepRangesSingle() {
        let duration = CMTime(seconds: 10, preferredTimescale: 600)
        let removals = [
            CMTimeRange(start: CMTime(seconds: 3, preferredTimescale: 600), 
                       duration: CMTime(seconds: 2, preferredTimescale: 600))
        ]
        
        let keepRanges = MagicFixService.calculateKeepRanges(removals: removals, duration: duration)
        
        XCTAssertEqual(keepRanges.count, 2)
        XCTAssertEqual(keepRanges[0].start.seconds, 0)
        XCTAssertEqual(keepRanges[0].end.seconds, 3)
        XCTAssertEqual(keepRanges[1].start.seconds, 5)
        XCTAssertEqual(keepRanges[1].end.seconds, 10)
    }
    
    // MARK: - Smart Thumbnail Tests
    
    func testSmartThumbnailServiceExists() {
        let service = ServiceContainer.shared.smartThumbnailService
        
        XCTAssertNotNil(service)
    }
    
    // MARK: - Auto Enhance Tests
    
    func testAutoEnhanceOptions() {
        var options = MagicFixOptions()
        
        // Test auto enhance option
        options.autoEnhance = true
        XCTAssertTrue(options.autoEnhance)
        
        options.autoEnhance = false
        XCTAssertFalse(options.autoEnhance)
    }
    
    // MARK: - Audio Enhancement Tests
    
    func testAudioEnhancementOptions() {
        var options = MagicFixOptions()
        
        // Test audio enhancement option
        options.enhanceAudio = true
        XCTAssertTrue(options.enhanceAudio)
        
        options.enhanceAudio = false
        XCTAssertFalse(options.enhanceAudio)
    }
    
    // MARK: - Smart Crop Tests
    
    func testSmartCropOptions() {
        var options = MagicFixOptions()
        
        // Test smart crop option
        options.smartCrop = true
        XCTAssertTrue(options.smartCrop)
        
        options.smartCrop = false
        XCTAssertFalse(options.smartCrop)
    }
    
    // MARK: - Auto Framing Tests
    
    func testAutoFramingOptions() {
        var options = MagicFixOptions()
        
        // Test auto framing option
        options.autoFraming = true
        XCTAssertTrue(options.autoFraming)
        
        options.autoFraming = false
        XCTAssertFalse(options.autoFraming)
    }
    
    // MARK: - Text Recognition Tests
    
    func testTextRecognitionOptions() {
        var options = MagicFixOptions()
        
        // Test text recognition option
        options.scanForText = true
        XCTAssertTrue(options.scanForText)
        
        options.scanForText = false
        XCTAssertFalse(options.scanForText)
    }
    
    // MARK: - Mood Analysis Tests
    
    func testMoodAnalysisOptions() {
        var options = MagicFixOptions()
        
        // Test mood analysis option
        options.analyzeMood = true
        XCTAssertTrue(options.analyzeMood)
        
        options.analyzeMood = false
        XCTAssertFalse(options.analyzeMood)
    }
    
    // MARK: - Highlight Detection Tests
    
    func testHighlightDetectionOptions() {
        var options = MagicFixOptions()
        
        // Test highlight detection option
        options.findHighlights = true
        XCTAssertTrue(options.findHighlights)
        
        options.findHighlights = false
        XCTAssertFalse(options.findHighlights)
    }
    
    // MARK: - Cursor Highlight Tests
    
    func testCursorHighlightOptions() {
        var options = MagicFixOptions()
        
        // Test cursor highlight option (default true)
        XCTAssertTrue(options.applyHighlightCursor)
        
        options.applyHighlightCursor = false
        XCTAssertFalse(options.applyHighlightCursor)
    }
    
    // MARK: - Jump Cut Smoothing Tests
    
    func testJumpCutSmoothingOptions() {
        var options = MagicFixOptions()
        
        // Test jump cut smoothing option (default true)
        XCTAssertTrue(options.smoothJumpCuts)
        
        options.smoothJumpCuts = false
        XCTAssertFalse(options.smoothJumpCuts)
    }
    
    // MARK: - Generative AI Tests
    
    func testGenerativeAIOptions() {
        var options = MagicFixOptions()
        
        // Test generative AI options
        options.magicRemovePeople = true
        XCTAssertTrue(options.magicRemovePeople)
        
        options.generativeStyle = true
        XCTAssertTrue(options.generativeStyle)
    }
    
    // MARK: - Options Equatability Tests
    
    func testMagicFixOptionsEquatable() {
        let options1 = MagicFixOptions()
        let options2 = MagicFixOptions()
        
        // Default options should be equal
        XCTAssertEqual(options1, options2)
        
        // Modified options should not be equal
        var options3 = MagicFixOptions()
        options3.removeSilence = false
        XCTAssertNotEqual(options1, options3)
    }
    
    // MARK: - Options Codability Tests
    
    func testMagicFixOptionsCodable() throws {
        let options = MagicFixOptions.proClean
        
        // Encode
        let encoder = JSONEncoder()
        let data = try encoder.encode(options)
        
        // Decode
        let decoder = JSONDecoder()
        let decoded = try decoder.decode(MagicFixOptions.self, from: data)
        
        // Should be equal
        XCTAssertEqual(decoded, options)
    }
}
