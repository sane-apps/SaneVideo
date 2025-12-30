//
//  AIProviders.swift
//  SaneVideo
//

import Foundation

enum AIProvider {
    case appleFoundation
}

enum AIError: Error, LocalizedError {
    case invalidResponse
    case networkError(Error)
    case apiError(String)

    var errorDescription: String? {
        switch self {
        case .invalidResponse: return "Invalid response from AI service"
        case let .networkError(error): return "Network error: \(error.localizedDescription)"
        case let .apiError(message): return "API error: \(message)"
        }
    }
}

struct AIGeneratedContent {
    let title: String
    let description: String
}

struct MagicFixAnalysis: Codable {
    struct Segment: Codable {
        let startTime: Double
        let endTime: Double
        let description: String
        let type: SegmentType
        
        enum SegmentType: String, Codable {
            case filler // Useless content to remove
            case topic // Chapter/Topic change
            case highlight // Viral/Key moment
            case silence // Detected silence (usually from other detector, but AI can confirm context)
        }
    }
    
    let segments: [Segment]
}

protocol AIModelProvider: Sendable {
    func generateTitleAndDescription(transcript: String) async throws -> AIGeneratedContent
    func analyzeTranscriptForEdits(prompt: String) async throws -> MagicFixAnalysis
    func refineCaptions(captions: [Caption], prompt: String) async throws -> [Caption]
}
