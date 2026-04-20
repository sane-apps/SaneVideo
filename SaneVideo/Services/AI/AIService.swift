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

    // OPTIMIZATION: Timeout for AI operations to prevent UI hangs on large transcripts
    private static let aiOperationTimeout: TimeInterval = 30.0

    init(provider: AIProvider = .appleFoundation) {
        self.providerType = provider
        self.engine = AppleFoundationProvider()
    }

    // MARK: - Timeout Helper

    /// Wraps an async operation with a timeout to prevent indefinite hangs
    private func withTimeout<T: Sendable>(
        seconds: TimeInterval = AIService.aiOperationTimeout,
        operation: @escaping @Sendable () async throws -> T
    ) async throws -> T {
        try await withThrowingTaskGroup(of: T.self) { group in
            group.addTask {
                try await operation()
            }

            group.addTask {
                try await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
                throw AIError.timeout
            }

            // Return first completed result, cancel the other
            let result = try await group.next()!
            group.cancelAll()
            return result
        }
    }

    /// Generates a title and description based on the video transcript
    func generateTitleAndDescription(transcript: String) async throws -> AIGeneratedContent {
        isGenerating = true
        defer { isGenerating = false }

        // OPTIMIZATION: Wrap with timeout to prevent hangs on large transcripts
        return try await withTimeout { [engine] in
            try await engine.generateTitleAndDescription(transcript: transcript)
        }
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

        // OPTIMIZATION: Wrap with timeout to prevent hangs on large transcripts
        return try await withTimeout { [engine] in
            try await engine.analyzeTranscriptForEdits(prompt: prompt)
        }
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

        // OPTIMIZATION: Wrap with timeout to prevent hangs on large transcripts
        return try await withTimeout { [engine] in
            try await engine.refineCaptions(captions: captions, prompt: prompt)
        }
    }

    /// Builds a transcript-grounded commentary draft that SaneVideo can render and edit.
    func generateCommentaryPlan(
        captions: [Caption],
        brief: WorkflowBrief,
        existingMarkers: [CommentaryMarker] = []
    ) async -> [CommentaryPlanItem] {
        isGenerating = true
        defer { isGenerating = false }

        if LocalSaneAIWorkflowRunner.shouldUseLocalModel {
            do {
                return try await withTimeout(seconds: 45) {
                    try await LocalSaneAIWorkflowRunner.generatePlan(
                        captions: captions,
                        brief: brief,
                        existingMarkers: existingMarkers
                    )
                }
            } catch {
                print("Local SaneAI workflow generation failed, falling back to heuristic draft: \(error)")
            }
        }

        return CommentaryWorkflowPlanner.buildDraft(
            from: captions,
            brief: brief,
            existingMarkers: existingMarkers
        )
    }
}
