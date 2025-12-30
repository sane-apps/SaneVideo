//
//  AIService.swift
//  SaneVideo
//
//  Created by SaneVideo Refactor
//

import Combine
import Foundation
import Observation

@MainActor
@Observable
class AIService {

    var isGenerating: Bool = false

    private let providerType: AIProvider
    private let engine: AIModelProvider

    init(provider: AIProvider = .appleFoundation) {
        self.providerType = provider
        self.engine = AppleFoundationProvider()
    }

    /// Generates a title and description based on the video transcript
    func generateTitleAndDescription(transcript: String) async throws -> AIGeneratedContent {
        isGenerating = true
        defer { isGenerating = false }
        return try await engine.generateTitleAndDescription(transcript: transcript)
    }

    /// Analyzes transcript for Magic Fix edits (filler words, highlights, topics)
    func analyzeTranscriptForEdits(transcript: String) async throws -> MagicFixAnalysis {
        isGenerating = true
        defer { isGenerating = false }
        
        let prompt = """
        Analyze this video transcript. identifying:
        1. Filler segments (um, uh, tangential/useless chatter) to remove.
        2. Topic changes (start of new sections).
        3. Key highlights (most engaging moments).
        
        Return ONLY valid JSON in this exact format:
        {
            "segments": [
                {"startTime": 0.0, "endTime": 5.0, "type": "topic", "description": "Introduction"},
                {"startTime": 12.5, "endTime": 13.0, "type": "filler", "description": "Umm..."},
                {"startTime": 45.0, "endTime": 60.0, "type": "highlight", "description": "Key insight about AI"}
            ]
        }
        
        Transcript:
        \(transcript)
        """

        return try await engine.analyzeTranscriptForEdits(prompt: prompt)
    }

    /// Refines a list of captions (grammar, punctuation, readability)
    func refineCaptions(_ captions: [Caption]) async throws -> [Caption] {
        guard !captions.isEmpty else { return [] }
        isGenerating = true
        defer { isGenerating = false }
        
        let originalTexts = captions.map { "\($0.id.uuidString): \($0.text)" }.joined(separator: "\n")
        let prompt = """
        Refine these video captions for clarity, grammar, and professional tone.
        Maintain the original ID for each caption.
        Return ONLY valid JSON in this format:
        {
          "refined": [
            {"id": "UUID", "text": "Refined text here"}
          ]
        }
        
        Captions:
        \(originalTexts)
        """

        return try await engine.refineCaptions(captions: captions, prompt: prompt)
    }
}
