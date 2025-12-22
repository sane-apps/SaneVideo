//
//  AppleFoundationProvider.swift
//  SaneVideo
//

import Foundation

#if canImport(FoundationModels)
import FoundationModels
#endif

struct AppleFoundationProvider: AIModelProvider {
    func generateTitleAndDescription(transcript: String) async throws -> AIGeneratedContent {
        AppLogger.general.info("Using Apple Foundation Models for local processing")
        
        #if canImport(FoundationModels) && false
        // Integration for macOS Tahoe local language models (stubbed)
        let model = try await LanguageModel.load(.large)
        
        let prompt = """
        Generate a catchy YouTube video title and description for this transcript.
        Return as JSON: {"title": "...", "description": "..."}
        
        Transcript: \(transcript)
        """
        
        let response = try await model.generate(prompt)
        
        guard let data = response.text.data(using: String.Encoding.utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: String],
              let title = json["title"],
              let description = json["description"] else {
            throw AIError.invalidResponse
        }
        
        return AIGeneratedContent(title: title, description: description)
        
        #else
        // Fallback for non-Tahoe systems or build environments
        AppLogger.general.warning("FoundationModels framework not available, falling back to Gemini")
        return try await GeminiProvider().generateTitleAndDescription(transcript: transcript)
        #endif
    }

    func analyzeTranscriptForEdits(prompt: String) async throws -> MagicFixAnalysis {
        #if canImport(FoundationModels) && false
        let model = try await LanguageModel.load(.large) 
        let response = try await model.generate(prompt)
        guard let data = response.text.data(using: String.Encoding.utf8) else { throw AIError.invalidResponse }
        return try JSONDecoder().decode(MagicFixAnalysis.self, from: data)
        #else
        AppLogger.general.warning("FoundationModels not available for analysis, falling back to Gemini")
        return try await GeminiProvider().analyzeTranscriptForEdits(prompt: prompt)
        #endif
    }

    func refineCaptions(captions: [Caption], prompt: String) async throws -> [Caption] {
        #if canImport(FoundationModels) && false
        let model = try await LanguageModel.load(.large)
        let response = try await model.generate(prompt)
        guard let data = response.text.data(using: String.Encoding.utf8) else { throw AIError.invalidResponse }
        
        // Use common parser
        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] ?? [:]
        guard let refinedList = json["refined"] as? [[String: String]] else { throw AIError.invalidResponse }
        
        var refinedCaptions = captions
        for refinedItem in refinedList {
            if let idString = refinedItem["id"],
               let id = UUID(uuidString: idString),
               let text = refinedItem["text"],
               let index = refinedCaptions.firstIndex(where: { $0.id == id }) {
                refinedCaptions[index].text = text
            }
        }
        return refinedCaptions
        #else
        AppLogger.general.warning("FoundationModels not available for refinement, falling back to Gemini")
        return try await GeminiProvider().refineCaptions(captions: captions, prompt: prompt)
        #endif
    }
}
