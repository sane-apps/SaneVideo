//
//  AIServiceTests.swift
//  SaneVideoTests
//

import Foundation
@testable import SaneVideo
import Testing

@Suite("AI Service")
struct AIServiceTests {
    @Test("Magic Fix analysis decodes the JSON shape the model returns")
    func magicFixAnalysisDecodesModelJSON() throws {
        let json = """
        {"segments":[
          {"startTime":0,"endTime":5.5,"description":"Intro","type":"topic"},
          {"startTime":12.5,"endTime":13,"description":"Umm...","type":"filler"}
        ]}
        """

        let analysis = try JSONDecoder().decode(MagicFixAnalysis.self, from: Data(json.utf8))

        #expect(analysis.segments.count == 2)
        #expect(analysis.segments[0].endTime == 5.5)
        #expect(analysis.segments[1].type == .filler)
        #expect(analysis.segments[1].startTime == 12.5)
    }

    @Test("refineCaptions returns empty for empty input without calling the model")
    @MainActor
    func refineCaptionsReturnsEmptyForEmptyInput() async throws {
        let result = try await AIService().refineCaptions([])
        #expect(result.isEmpty)
    }
}
