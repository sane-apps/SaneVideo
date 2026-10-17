import Foundation
import NaturalLanguage

/// Intelligent filler word detection using Apple's NaturalLanguage framework
actor SmartFillerDetector {

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

    /// Returns array of word indices that are filler words
    func detectFillers(in words: [CaptionWord]) -> [Int] {
        var fillerIndices: [Int] = []

        for (index, word) in words.enumerated() {
            let cleanWord = word.text.lowercased().trimmingCharacters(in: .punctuationCharacters)

            guard !cleanWord.isEmpty else { continue }

            // Clean Up cuts without a review step, so only sounds that are never real words are cut.
            // "like", "well", "so", "right" and "actually" carry meaning too often to remove blindly.
            if isDefiniteFiller(cleanWord) {
                fillerIndices.append(index)
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

            if tag == .interjection || isDefiniteFiller(word) {
                fillers.append((range: tokenRange, word: word))
            }
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

        if isDefiniteFiller(cleanWord) {
            return 0.95
        }

        if contextualFillers.contains(cleanWord) {
            let tagger = NLTagger(tagSchemes: [.lexicalClass])
            tagger.string = context

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
}
