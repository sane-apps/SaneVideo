//
//  SoundAnalysisServiceTests.swift
//  SaneVideoTests
//

import XCTest
import AVFoundation
@testable import SaneVideo

@MainActor
final class SoundAnalysisServiceTests: XCTestCase {
    
    var service: SoundAnalysisService!
    
    override func setUp() {
        super.setUp()
        service = SoundAnalysisService()
    }
    
    override func tearDown() {
        service = nil
        super.tearDown()
    }
    
    func testGatingMetadataGeneration() async throws {
        // We need a sample audio file. 
        // SaneMaster.rb gen_assets usually creates test_video.mp4 and others.
        let bundle = Bundle(for: SoundAnalysisServiceTests.self)
        // Try to find a test asset
        let testAssetURL = bundle.url(forResource: "test_video", withExtension: "mp4") ?? 
                          URL(fileURLWithPath: "/Users/sj/SaneVideo/Tests/Assets/test_video.mp4")
        
        // Ensure asset exists
        guard FileManager.default.fileExists(atPath: testAssetURL.path) else {
            throw XCTSkip("Test asset test_video.mp4 not found")
        }
        
        let segments = try await service.generateGatingMetadata(for: testAssetURL)
        
        // Verify we got some segments
        XCTAssertFalse(segments.isEmpty, "Gating segments should not be empty for a valid video file")
        
        // Verify segment properties
        if let first = segments.first {
            XCTAssertGreaterThan(first.timeRange.duration.seconds, 0)
            XCTAssertTrue(first.confidence >= 0 && first.confidence <= 1.0)
        }
    }
}
