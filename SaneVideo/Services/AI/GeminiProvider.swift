//
//  GeminiProvider.swift
//  SaneVideo
//

import Foundation

struct GeminiProvider: AIModelProvider {
    func generateTitleAndDescription(transcript: String) async throws -> AIGeneratedContent {
        let key = await Secrets.geminiKey()
        guard !key.isEmpty && key != "YOUR_GEMINI_API_KEY" else {
            throw AIError.noAPIKey
        }

        let urlString = "https://generativelanguage.googleapis.com/v1beta/models/gemini-1.5-flash:generateContent?key=\(key)"
        guard let url = URL(string: urlString) else {
            throw AIError.invalidResponse
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let prompt = """
        Generate a catchy YouTube video title (max 100 characters) and description (max 500 characters) for this video transcript.
        Return ONLY valid JSON in this exact format:
        {"title": "Your Title Here", "description": "Your description here"}

        Transcript:
        \(transcript)
        """

        let body: [String: Any] = [
            "contents": [
                [
                    "parts": [
                        ["text": prompt]
                    ]
                ]
            ],
            "generationConfig": [
                "temperature": 0.7,
                "maxOutputTokens": 1000
            ]
        ]

        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        
        // PERFORMANCE: Add explicit timeout for robustness
        request.timeoutInterval = 30.0 // 30 second timeout

        // Copy request to avoid concurrency issues
        let requestCopy = request
        let result = try await withTimeout(seconds: 35.0) {
            try await URLSession.shared.data(for: requestCopy)
        }
        let (data, response) = result

        guard let httpResponse = response as? HTTPURLResponse else {
            throw AIError.invalidResponse
        }

        if httpResponse.statusCode != 200 {
            let errorMessage = String(data: data, encoding: .utf8) ?? "Unknown error"
            throw AIError.apiError(errorMessage)
        }

        // Parse Gemini response
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let candidates = json["candidates"] as? [[String: Any]],
              let firstCandidate = candidates.first,
              let content = firstCandidate["content"] as? [String: Any],
              let parts = content["parts"] as? [[String: Any]],
              let firstPart = parts.first,
              let text = firstPart["text"] as? String
        else {
            throw AIError.invalidResponse
        }

        // Parse the JSON from the text response
        guard let textData = text.data(using: String.Encoding.utf8),
              let contentJson = try JSONSerialization.jsonObject(with: textData) as? [String: String],
              let title = contentJson["title"],
              let description = contentJson["description"]
        else {
            throw AIError.invalidResponse
        }

        return AIGeneratedContent(title: title, description: description)
    }

    func analyzeTranscriptForEdits(prompt: String) async throws -> MagicFixAnalysis {
        let key = await Secrets.geminiKey()
        guard !key.isEmpty && key != "YOUR_GEMINI_API_KEY" else { throw AIError.noAPIKey }
        
        let urlString = "https://generativelanguage.googleapis.com/v1beta/models/gemini-1.5-flash:generateContent?key=\(key)"
        guard let url = URL(string: urlString) else { throw AIError.invalidResponse }
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        
        let body: [String: Any] = [
            "contents": [[ "parts": [["text": prompt]] ]],
            "generationConfig": ["temperature": 0.3, "responseMimeType": "application/json"]
        ]
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        
        // PERFORMANCE: Add explicit timeout for robustness
        request.timeoutInterval = 30.0 // 30 second timeout

        // Copy request to avoid concurrency issues
        let requestCopy = request
        let result = try await withTimeout(seconds: 35.0) {
            try await URLSession.shared.data(for: requestCopy)
        }
        let (data, response) = result
        guard (response as? HTTPURLResponse)?.statusCode == 200 else { throw AIError.apiError("Gemini Error") }
        
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let candidates = json["candidates"] as? [[String: Any]],
              let firstCandidate = candidates.first,
              let content = firstCandidate["content"] as? [String: Any],
              let parts = content["parts"] as? [[String: Any]],
              let firstPart = parts.first,
              let responseText = firstPart["text"] as? String,
              let responseData = responseText.data(using: .utf8)
        else { throw AIError.invalidResponse }
        
        return try JSONDecoder().decode(MagicFixAnalysis.self, from: responseData)
    }

    func refineCaptions(captions: [Caption], prompt: String) async throws -> [Caption] {
        let key = await Secrets.geminiKey()
        guard !key.isEmpty && key != "YOUR_GEMINI_API_KEY" else { throw AIError.noAPIKey }
        
        let urlString = "https://generativelanguage.googleapis.com/v1beta/models/gemini-1.5-flash:generateContent?key=\(key)"
        guard let url = URL(string: urlString) else { throw AIError.invalidResponse }
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        
        let body: [String: Any] = [
            "contents": [[ "parts": [["text": prompt]] ]],
            "generationConfig": ["temperature": 0.2, "responseMimeType": "application/json"]
        ]
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        
        // PERFORMANCE: Add explicit timeout for robustness
        request.timeoutInterval = 30.0 // 30 second timeout

        // Copy request to avoid concurrency issues
        let requestCopy = request
        let result = try await withTimeout(seconds: 35.0) {
            try await URLSession.shared.data(for: requestCopy)
        }
        let (data, response) = result
        guard (response as? HTTPURLResponse)?.statusCode == 200 else { throw AIError.apiError("Gemini Error") }
        
        return try AIProviderParser.parseRefinedResponse(data: data, originalCaptions: captions, isGemini: true)
    }
}
