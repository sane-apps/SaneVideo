//
//  AIProviderParser.swift
//  SaneVideo
//

import Foundation

struct AIProviderParser {
    static func parseRefinedResponse(data: Data, originalCaptions: [Caption], isGemini: Bool = false) throws -> [Caption] {
        let json: [String: Any]
        if isGemini {
            guard let responseJson = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let candidates = responseJson["candidates"] as? [[String: Any]],
                  let content = candidates.first?["content"] as? [String: Any],
                  let parts = content["parts"] as? [[String: Any]],
                  let text = parts.first?["text"] as? String,
                  let textData = text.data(using: .utf8) else { throw AIError.invalidResponse }
            json = try JSONSerialization.jsonObject(with: textData) as? [String: Any] ?? [:]
        } else {
            guard let responseJson = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let choices = responseJson["choices"] as? [[String: Any]],
                  let content = choices.first?["message"] as? [String: Any],
                  let text = content["content"] as? String,
                  let textData = text.data(using: .utf8) else { throw AIError.invalidResponse }
            json = try JSONSerialization.jsonObject(with: textData) as? [String: Any] ?? [:]
        }
        
        guard let refinedList = json["refined"] as? [[String: String]] else { throw AIError.invalidResponse }
        
        var refinedCaptions = originalCaptions
        for refinedItem in refinedList {
            if let idString = refinedItem["id"],
               let id = UUID(uuidString: idString),
               let text = refinedItem["text"],
               let index = refinedCaptions.firstIndex(where: { $0.id == id }) {
                refinedCaptions[index].text = text
            }
        }
        
        return refinedCaptions
    }
}
