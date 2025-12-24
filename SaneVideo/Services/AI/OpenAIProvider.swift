//
//  OpenAIProvider.swift
//  SaneVideo
//

import Foundation

struct OpenAIProvider: AIModelProvider {
    func generateTitleAndDescription(transcript: String) async throws -> AIGeneratedContent {
        // Use KeychainService for user-provided API keys (optional cloud enhancement)
        let keychain = await MainActor.run { ServiceContainer.shared.keychainService }
        let key = await keychain.retrieve(for: .openAIKey) ?? ""
        guard !key.isEmpty else {
            throw AIError.noAPIKey
        }

        guard let url = URL(string: "https://api.openai.com/v1/chat/completions") else {
            throw AIError.invalidResponse
        }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let systemPrompt = """
        You are a helpful assistant that generates catchy video titles and descriptions for YouTube videos.
        Given a transcript, create a compelling title (max 100 characters) and description (max 500 characters).
        Return ONLY valid JSON in this exact format:
        {"title": "Your Title Here", "description": "Your description here"}
        """

        let userPrompt = "Generate a title and description for this video transcript:\n\n\(transcript)"

        let body: [String: Any] = [
            "model": "gpt-4o-mini",
            "messages": [
                ["role": "system", "content": systemPrompt],
                ["role": "user", "content": userPrompt]
            ],
            "response_format": ["type": "json_object"],
            "temperature": 0.7
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

        // Parse OpenAI response
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let choices = json["choices"] as? [[String: Any]],
              let firstChoice = choices.first,
              let message = firstChoice["message"] as? [String: Any],
              let content = message["content"] as? String,
              let contentData = content.data(using: String.Encoding.utf8),
              let contentJson = try JSONSerialization.jsonObject(with: contentData) as? [String: String],
              let title = contentJson["title"],
              let description = contentJson["description"]
        else {
            throw AIError.invalidResponse
        }

        return AIGeneratedContent(title: title, description: description)
    }

    func analyzeTranscriptForEdits(prompt: String) async throws -> MagicFixAnalysis {
        // Use KeychainService for user-provided API keys (optional cloud enhancement)
        let keychain = await MainActor.run { ServiceContainer.shared.keychainService }
        let key = await keychain.retrieve(for: .openAIKey) ?? ""
        guard !key.isEmpty else { throw AIError.noAPIKey }
        
        guard let url = URL(string: "https://api.openai.com/v1/chat/completions") else { throw AIError.invalidResponse }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        
        let body: [String: Any] = [
            "model": "gpt-4o-mini",
            "messages": [
                ["role": "system", "content": "You are an expert video editor AI."],
                ["role": "user", "content": prompt]
            ],
            "response_format": ["type": "json_object"],
            "temperature": 0.3
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
        guard (response as? HTTPURLResponse)?.statusCode == 200 else { throw AIError.apiError("OpenAI Error") }
        
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let choices = json["choices"] as? [[String: Any]],
              let firstChoice = choices.first,
              let message = firstChoice["message"] as? [String: Any],
              let text = message["content"] as? String,
              let data = text.data(using: String.Encoding.utf8)
        else { throw AIError.invalidResponse }
        
        return try JSONDecoder().decode(MagicFixAnalysis.self, from: data)
    }

    func refineCaptions(captions: [Caption], prompt: String) async throws -> [Caption] {
        // Use KeychainService for user-provided API keys (optional cloud enhancement)
        let keychain = await MainActor.run { ServiceContainer.shared.keychainService }
        let key = await keychain.retrieve(for: .openAIKey) ?? ""
        guard !key.isEmpty else { throw AIError.noAPIKey }
        
        guard let url = URL(string: "https://api.openai.com/v1/chat/completions") else { throw AIError.invalidResponse }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        
        let body: [String: Any] = [
            "model": "gpt-4o-mini",
            "messages": [
                ["role": "system", "content": "You are a professional copywriter specialing in video captions."],
                ["role": "user", "content": prompt]
            ],
            "response_format": ["type": "json_object"],
            "temperature": 0.2
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
        guard (response as? HTTPURLResponse)?.statusCode == 200 else { throw AIError.apiError("OpenAI Error") }
        
        return try AIProviderParser.parseRefinedResponse(data: data, originalCaptions: captions)
    }
}
