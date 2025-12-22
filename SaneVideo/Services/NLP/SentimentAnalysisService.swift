//
//  SentimentAnalysisService.swift
//  SaneVideo
//
//  Apple NaturalLanguage framework for sentiment analysis
//  Analyzes caption text to detect mood for color grading suggestions
//

import Foundation
import NaturalLanguage
import FoundationModels
import CoreMedia

/// Sentiment result for text analysis
struct SentimentResult: Sendable {
    let score: Double // -1.0 (negative) to 1.0 (positive)
    let sentiment: Sentiment
    let confidence: Double

    /// Suggested color grading based on sentiment
    var suggestedColorGrade: ColorGrade {
        switch sentiment {
        case .veryPositive: return .warm
        case .positive: return .brightWarm
        case .neutral: return .natural
        case .negative: return .cool
        case .veryNegative: return .desaturated
        }
    }
}

/// Sentiment categories
enum Sentiment: String, Sendable {
    case veryPositive = "Very Positive"
    case positive = "Positive"
    case neutral = "Neutral"
    case negative = "Negative"
    case veryNegative = "Very Negative"

    var emoji: String {
        switch self {
        case .veryPositive: return "😄"
        case .positive: return "🙂"
        case .neutral: return "😐"
        case .negative: return "😕"
        case .veryNegative: return "😢"
        }
    }

    nonisolated static func from(score: Double) -> Sentiment {
        switch score {
        case 0.5...: return .veryPositive
        case 0.1 ..< 0.5: return .positive
        case -0.1 ..< 0.1: return .neutral
        case -0.5 ..< -0.1: return .negative
        default: return .veryNegative
        }
    }
}

/// Color grade suggestions based on sentiment
enum ColorGrade: String, Sendable {
    case warm = "Warm" // Happy, energetic
    case brightWarm = "Bright" // Positive, uplifting
    case natural = "Natural" // Neutral, documentary
    case cool = "Cool" // Serious, professional
    case desaturated = "Muted" // Sad, dramatic

    /// Corresponding effect types to apply
    var effects: [VideoEffectType] {
        switch self {
        case .warm:
            return [.lut, .vibrance] // Use Cinematic Teal & Orange LUT
        case .brightWarm:
            return [.lut, .brightness]
        case .natural:
            return [] // No changes
        case .cool:
            return [.warmth, .contrast] // Cool warmth (low value)
        case .desaturated:
            return [.saturation, .contrast]
        }
    }
}

/// Detected emotion in text
struct EmotionResult: Sendable {
    let emotion: Emotion
    let confidence: Double
    let keywords: [String]
}

/// Emotions detectable from text
enum Emotion: String, CaseIterable, Sendable {
    case joy = "Joy"
    case excitement = "Excitement"
    case surprise = "Surprise"
    case sadness = "Sadness"
    case anger = "Anger"
    case fear = "Fear"
    case love = "Love"
    case neutral = "Neutral"

    var emoji: String {
        switch self {
        case .joy: return "😊"
        case .excitement: return "🎉"
        case .surprise: return "😮"
        case .sadness: return "😢"
        case .anger: return "😠"
        case .fear: return "😨"
        case .love: return "❤️"
        case .neutral: return "😐"
        }
    }

    /// Keywords associated with this emotion
    nonisolated var keywords: Set<String> {
        switch self {
        case .joy: return ["happy", "glad", "pleased", "delighted", "wonderful", "great", "amazing", "awesome", "fantastic", "love"]
        case .excitement: return ["excited", "thrilled", "pumped", "hyped", "can't wait", "incredible", "unbelievable", "wow"]
        case .surprise: return ["surprised", "shocked", "amazed", "unexpected", "wow", "whoa", "omg"]
        case .sadness: return ["sad", "unhappy", "depressed", "down", "upset", "disappointed", "sorry", "miss", "lost"]
        case .anger: return ["angry", "mad", "furious", "annoyed", "frustrated", "hate", "terrible", "awful"]
        case .fear: return ["scared", "afraid", "worried", "anxious", "nervous", "terrified", "frightened"]
        case .love: return ["love", "adore", "cherish", "heart", "beloved", "dear", "sweetheart"]
        case .neutral: return []
        }
    }
}

/// Service for analyzing sentiment and emotions in text
actor SentimentAnalysisService {

    private let tagger: NLTagger
    private var modelSession: LanguageModelSession?

    init() {
        tagger = NLTagger(tagSchemes: [.sentimentScore, .lexicalClass])
    }

    /// Initialize the Apple Intelligence session for advanced analysis
    func prepareAI() async {
        // macOS 26+ FoundationModels session
        self.modelSession = LanguageModelSession()
    }

    /// Analyze sentiment using foundation models for high accuracy (macOS 26+)
    func analyzeSentimentIntelligent(text: String) async -> SentimentResult {
        guard let session = modelSession else {
            // Fallback to legacy NLTagger if LLM is not ready
            return analyzeSentiment(text: text)
        }

        do {
            // Guided Generation pattern for Apple Intelligence
            let prompt = "Analyze the sentiment of this text and return a single word (Very Positive, Positive, Neutral, Negative, Very Negative): \(text)"
            let response = try await session.respond(to: prompt)
            
            // Accessing the content from the Response object
            let sentimentStr = response.content.trimmingCharacters(in: .whitespacesAndNewlines)
            let sentiment = Sentiment(rawValue: sentimentStr) ?? .neutral
            
            return SentimentResult(
                score: 0.0,
                sentiment: sentiment,
                confidence: 0.95
            )
        } catch {
            return analyzeSentiment(text: text)
        }
    }

    /// Analyze tone and nuance using Apple Intelligence (macOS 26+)
    func analyzeNuance(text: String) async -> [String: Double] {
        guard let session = modelSession else { return [:] }
        
        let prompt = "Analyze the tone of this text. Return scores from 0-1 for: Professionalism, Sarcasm, Conciseness, Urgent. Format: Key: Value"
        
        do {
            let response = try await session.respond(to: prompt)
            let content = response.content
            
            // Parse response
            var metrics: [String: Double] = [:]
            for line in content.components(separatedBy: .newlines) {
                let parts = line.components(separatedBy: ":")
                if parts.count == 2, let score = Double(parts[1].trimmingCharacters(in: .whitespaces)) {
                    metrics[parts[0].trimmingCharacters(in: .whitespaces)] = score
                }
            }
            return metrics
        } catch {
            return [:]
        }
    }

    /// Summarize a set of captions using Apple Intelligence
    func summarizeCaptions(captions: [Caption]) async -> String {
        guard let session = modelSession else { return "" }
        
        let allText = captions.map { $0.text }.joined(separator: " ")
        let prompt = "Summarize the following video transcript concisely:\n\n\(allText)"
        
        do {
            let response = try await session.respond(to: prompt)
            return response.content
        } catch {
            return "Summary unavailable."
        }
    }

    /// Analyze sentiment of text
    func analyzeSentiment(text: String) -> SentimentResult {
        tagger.string = text

        let range = text.startIndex ..< text.endIndex

        var totalScore: Double = 0
        var count = 0

        tagger.enumerateTags(in: range, unit: .sentence, scheme: .sentimentScore, options: []) { tag, _ in
            if let tag = tag, let score = Double(tag.rawValue) {
                totalScore += score
                count += 1
            }
            return true
        }

        let averageScore = count > 0 ? totalScore / Double(count) : 0
        let sentiment = Sentiment.from(score: averageScore)

        return SentimentResult(
            score: averageScore,
            sentiment: sentiment,
            confidence: min(abs(averageScore) * 2, 1.0)
        )
    }

    /// Detect emotions from text using keyword matching
    func detectEmotions(text: String) -> [EmotionResult] {
        let lowercased = text.lowercased()
        var results: [EmotionResult] = []

        for emotion in Emotion.allCases {
            let keywords = emotion.keywords
            var matchedKeywords: [String] = []

            for keyword in keywords where lowercased.contains(keyword) {
                matchedKeywords.append(keyword)
            }

            if !matchedKeywords.isEmpty {
                let confidence = min(Double(matchedKeywords.count) * 0.2, 1.0)
                results.append(EmotionResult(
                    emotion: emotion,
                    confidence: confidence,
                    keywords: matchedKeywords
                ))
            }
        }

        // Sort by confidence
        return results.sorted { $0.confidence > $1.confidence }
    }

    /// Analyze captions and suggest color grading for each segment
    func analyzeClipMood(captions: [Caption]) -> [(timeRange: CMTimeRange, sentiment: SentimentResult)] {
        return captions.compactMap { caption in
            let sentiment = analyzeSentiment(text: caption.text)
            return (
                timeRange: CMTimeRange(start: caption.startTime, end: caption.endTime),
                sentiment: sentiment
            )
        }
    }

    /// Get overall mood of a video from its captions
    func getOverallMood(captions: [Caption]) -> SentimentResult {
        let allText = captions.map { $0.text }.joined(separator: " ")
        return analyzeSentiment(text: allText)
    }

    /// Extract key topics/entities from text
    func extractTopics(text: String) -> [String: Int] {
        tagger.string = text

        var topics: [String: Int] = [:]
        let range = text.startIndex ..< text.endIndex

        tagger.enumerateTags(in: range, unit: .word, scheme: .lexicalClass, options: [.omitPunctuation, .omitWhitespace]) { tag, tokenRange in
            if let tag = tag {
                // Only include nouns and verbs as topics
                if tag == .noun || tag == .verb {
                    let word = String(text[tokenRange]).lowercased()
                    if word.count > 3 { // Skip short words
                        topics[word, default: 0] += 1
                    }
                }
            }
            return true
        }

        return topics
    }
}
