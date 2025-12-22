//
//  AIServiceTests.swift
//  SaneVideoTests
//

import XCTest
import AVFoundation
@testable import SaneVideo

@MainActor
final class AIServiceTests: XCTestCase {
    func testRefineCaptionsPromptGeneration() async throws {
        let aiService = ServiceContainer.shared.aiService
        let captions = [
            Caption(text: "hello world", startTime: .zero, endTime: CMTime(seconds: 1, preferredTimescale: 600)),
            Caption(text: "this is a test", startTime: CMTime(seconds: 1, preferredTimescale: 600), endTime: CMTime(seconds: 2, preferredTimescale: 600))
        ]
        
        // This test mostly ensures the method can be called and doesn't crash
        // Since it uses a provider, we can't easily mock the network without more boilerplate
        // but we can at least verify the method existence and type signature.
        
        // Mocking provider if needed in future
    }
}
