//
//  SoundAnalysisServiceTests.swift
//  SaneVideoTests
//

import AVFoundation
@testable import SaneVideo
import Testing

@Suite("Sound Analysis Service")
struct SoundAnalysisServiceTests {
    @Test("Gating metadata for a clip with sound has positive-length segments with 0...1 confidence")
    @MainActor
    func gatingMetadataGeneration() async throws {
        let segments = try await SoundAnalysisService().generateGatingMetadata(for: TestEnvironment.mockAssetURL)

        #expect(!segments.isEmpty)
        #expect(segments.allSatisfy { $0.timeRange.duration.seconds > 0 })
        #expect(segments.allSatisfy { (0.0 ... 1.0).contains($0.confidence) })
    }
}
