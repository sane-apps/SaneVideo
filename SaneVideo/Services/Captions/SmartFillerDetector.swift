//
//  SmartFillerDetector.swift
//  SaneVideo
//
//  Uses Apple's NaturalLanguage framework for intelligent filler word detection
//  Auto-improves with each macOS update as Apple enhances NL models
//

import Foundation
import NaturalLanguage

/// Intelligent filler word detection using Apple's NaturalLanguage framework
/// Replaces simple regex matching with linguistic analysis
actor SmartFillerDetector {

    // Common filler words and phrases
    private let fillerWords: Set<String> = [
        "um", "uh", "uhh", "umm", "er", "err", "ah", "ahh",
        "hmm", "hm", "mhm", "uh-huh", "mm-hmm",
        "like", "you know", "i mean", "basically", "actually",
        "literally", "right", "so", "well", "anyway",
        "kind of", "sort of", "kinda", "sorta"
    ]

    // Words that are fillers only in certain contexts
    private let contextualFillers: Set<String> = [
        "like", "right", "so", "well", "actually"
    ]

    init() {}

    // MARK: - Public API

    /// Analyze caption words and identify which ones are fillers
    /// Returns array of word indices that are filler words
    func detectFillers(in words: [CaptionWord]) -> [Int] {
        var fillerIndices: [Int] = []

        // Build full text for context analysis
        let fullText = words.map { $0.text }.joined(separator: " ")

        // Use NLTagger for part-of-speech analysis
        let tagger = NLTagger(tagSchemes: [.lexicalClass, .nameType])
        tagger.string = fullText

        // Track word positions

        var wordStartPositions: [String.Index] = []

        // Find start position of each word
        var searchStart = fullText.startIndex
        for word in words {
            if let range = fullText.range(of: word.text, range: searchStart ..< fullText.endIndex) {
                wordStartPositions.append(range.lowerBound)
                searchStart = range.upperBound
            } else {
                wordStartPositions.append(fullText.startIndex)
            }
        }

        // Analyze each word
        for (index, word) in words.enumerated() {
            let cleanWord = word.text.lowercased().trimmingCharacters(in: .punctuationCharacters)

            // Skip empty words
            guard !cleanWord.isEmpty else { continue }

            // Check if it's a definite filler
            if isDefiniteFiller(cleanWord) {
                fillerIndices.append(index)
                continue
            }

            // For contextual fillers, use NLTagger analysis
            if contextualFillers.contains(cleanWord) {
                if isFillerInContext(word: cleanWord, at: index, in: words, tagger: tagger, positions: wordStartPositions) {
                    fillerIndices.append(index)
                }
            }
        }

        return fillerIndices
    }

    /// Detect filler words from raw text (for caption display)
    func detectFillers(in text: String) -> [(range: Range<String.Index>, word: String)] {
        var fillers: [(range: Range<String.Index>, word: String)] = []

        let tagger = NLTagger(tagSchemes: [.lexicalClass])
        tagger.string = text

        tagger.enumerateTags(in: text.startIndex ..< text.endIndex, unit: .word, scheme: .lexicalClass) { tag, tokenRange in
            let word = String(text[tokenRange]).lowercased()

            // Check for filler interjections
            if tag == .interjection || isDefiniteFiller(word) {
                fillers.append((range: tokenRange, word: word))
            }
            // Check contextual fillers with part-of-speech
            else if contextualFillers.contains(word) {
                // "like" as a verb or preposition is not a filler
                // "like" as an interjection or discourse marker is a filler
                if tag == .particle || tag == .interjection {
                    fillers.append((range: tokenRange, word: word))
                }
            }

            return true
        }

        return fillers
    }

    /// Get confidence score for a word being a filler (0.0 - 1.0)
    func fillerConfidence(for word: String, in context: String) -> Float {
        let cleanWord = word.lowercased().trimmingCharacters(in: .punctuationCharacters)

        // Definite fillers have high confidence
        if isDefiniteFiller(cleanWord) {
            return 0.95
        }

        // Contextual fillers need analysis
        if contextualFillers.contains(cleanWord) {
            let tagger = NLTagger(tagSchemes: [.lexicalClass])
            tagger.string = context

            // Find the word in context
            if let range = context.lowercased().range(of: cleanWord) {
                let contextRange = Range(uncheckedBounds: (
                    lower: context.index(context.startIndex, offsetBy: context.distance(from: context.startIndex, to: range.lowerBound)),
                    upper: context.index(context.startIndex, offsetBy: context.distance(from: context.startIndex, to: range.upperBound))
                ))

                if let tag = tagger.tag(at: contextRange.lowerBound, unit: .word, scheme: .lexicalClass).0 {
                    switch tag {
                    case .interjection: return 0.9
                    case .particle: return 0.7
                    case .adverb: return 0.3
                    default: return 0.2
                    }
                }
            }
        }

        return 0.0
    }

    // MARK: - Private Helpers

    private func isDefiniteFiller(_ word: String) -> Bool {
        let definiteFillers: Set<String> = [
            "um", "uh", "uhh", "umm", "er", "err", "ah", "ahh",
            "hmm", "hm", "mhm", "uh-huh", "mm-hmm"
        ]
        return definiteFillers.contains(word)
    }

    private func isFillerInContext(word: String, at index: Int, in words: [CaptionWord], tagger: NLTagger, positions: [String.Index]) -> Bool {
        guard index < positions.count else { return false }

        let position = positions[index]

        // Get the tag at this position
        let (tag, _) = tagger.tag(at: position, unit: .word, scheme: .lexicalClass)

        if let tag = tag {
            // Interjections are almost always fillers
            if tag == .interjection {
                return true
            }

            // Check surrounding context
            let prevWord = index > 0 ? words[index - 1].text.lowercased() : ""
            let nextWord = index < words.count - 1 ? words[index + 1].text.lowercased() : ""

            switch word {
            case "like":
                // "like" at sentence start or after pause is likely filler
                if prevWord.isEmpty || prevWord.hasSuffix(".") || prevWord.hasSuffix(",") {
                    return true
                }
                // "like" before a verb or adverb is often filler
                if tag == .particle {
                    return true
                }

            case "right":
                // "right" at end of phrase is filler ("...right?")
                if nextWord.isEmpty || nextWord == "so" || nextWord == "and" {
                    return true
                }

            case "so":
                // "so" at sentence start followed by pause
                if prevWord.isEmpty && (nextWord == "um" || nextWord == "uh" || nextWord.isEmpty) {
                    return true
                }

            case "well":
                // "well" at sentence start is often filler
                if prevWord.isEmpty || prevWord.hasSuffix(".") {
                    return true
                }

            case "actually":
                // "actually" as discourse marker
                if tag == .adverb && (prevWord.isEmpty || prevWord.hasSuffix(",")) {
                    return true
                }

            default:
                break
            }
        }

        return false
    }
}
