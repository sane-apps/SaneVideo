//
//  CaptionModels.swift
//  SaneVideo
//
//  Created by SaneVideo Refactor
//

import CoreMedia
import Foundation
import SwiftUI

public struct Caption: Identifiable, Codable, Equatable, Sendable {
    public let id: UUID
    public var text: String
    public var startTime: CMTime
    public var endTime: CMTime
    public var words: [CaptionWord]? // Optional word-level details

    public nonisolated init(id: UUID = UUID(), text: String, startTime: CMTime, endTime: CMTime, words: [CaptionWord]? = nil) {
        self.id = id
        self.text = text
        self.startTime = startTime
        self.endTime = endTime
        self.words = words
    }

    // MARK: - Utility: Clean Text

    /// Returns cleaned text for display (removes Whisper tokens, timestamps, etc.)
    /// Use this for UI display instead of raw `text` property
    public var displayText: String {
        Self.cleanText(text)
    }

    /// Static helper to clean caption text
    public static func cleanText(_ input: String) -> String {
        var cleanedText = input.trimmingCharacters(in: CharacterSet.whitespacesAndNewlines)

        // CRITICAL: Remove Whisper special tokens first
        // These are control tokens like <|startoftranscript|>, <|en|>, <|endoftranscript|>, etc.
        let specialTokenPatterns = [
            #"<\|[^|>]+\|>"#,  // Matches <|anything|> - all special tokens
            #"\[BLANK_AUDIO\]"#,  // WhisperKit silence marker
            #"\[MUSIC\]"#,  // WhisperKit music marker
            #"\[APPLAUSE\]"#  // WhisperKit sound markers
        ]

        for pattern in specialTokenPatterns {
            cleanedText = cleanedText.replacingOccurrences(
                of: pattern,
                with: "",
                options: [.regularExpression, .caseInsensitive]
            )
        }

        // Remove timestamp patterns: [00:01:23], (00:01:23), 00:01:23, etc.
        let timestampPatterns = [
            #"\[?\d{1,2}:\d{2}:\d{2}(?:\.\d+)?\]?\s*"#,  // [00:01:23] or 00:01:23
            #"\[?\d{1,2}:\d{2}\]?\s*"#,                  // [01:23] or 01:23
            #"\(\d{1,2}:\d{2}:\d{2}(?:\.\d+)?\)\s*"#    // (00:01:23)
        ]

        for pattern in timestampPatterns {
            cleanedText = cleanedText.replacingOccurrences(
                of: pattern,
                with: "",
                options: [.regularExpression, .caseInsensitive]
            )
        }

        // Collapse multiple spaces and trim
        cleanedText = cleanedText.replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
        return cleanedText.trimmingCharacters(in: CharacterSet.whitespacesAndNewlines)
    }

    /// Removes timestamp patterns from caption text (e.g., [00:01:23], (00:01:23))
    public func withCleanedText() -> Caption {
        var cleaned = self
        cleaned.text = Self.cleanText(text)
        return cleaned
    }

    // MARK: - Codable (Manual implementation for CMTime)

    enum CodingKeys: String, CodingKey {
        case id, text, startTime, endTime, words
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        text = try container.decode(String.self, forKey: .text)

        let startSeconds = try container.decode(Double.self, forKey: .startTime)
        startTime = CMTime(seconds: startSeconds, preferredTimescale: 600)

        let endSeconds = try container.decode(Double.self, forKey: .endTime)
        endTime = CMTime(seconds: endSeconds, preferredTimescale: 600)

        words = try container.decodeIfPresent([CaptionWord].self, forKey: .words)
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(text, forKey: .text)
        try container.encode(startTime.seconds, forKey: .startTime)
        try container.encode(endTime.seconds, forKey: .endTime)
        try container.encodeIfPresent(words, forKey: .words)
    }
}

public struct CaptionWord: Identifiable, Codable, Equatable, Sendable {
    public var id = UUID()
    public let text: String
    public let start: Double
    public let end: Double
    public let probability: Double

    public var timeRange: CMTimeRange {
        let startCm = CMTime(seconds: start, preferredTimescale: 600)
        let endCm = CMTime(seconds: end, preferredTimescale: 600)
        return CMTimeRange(start: startCm, end: endCm)
    }
}

struct TimestampedTranscriptLine: Equatable, Sendable {
    let startTime: CMTime
    let text: String
}

enum TranscriptImportPayload: Equatable, Sendable {
    case captions([Caption])
    case timestampedLines([TimestampedTranscriptLine])
}

enum TranscriptImportParser {
    enum Error: LocalizedError {
        case unsupportedFormat

        var errorDescription: String? {
            switch self {
            case .unsupportedFormat:
                return "Unsupported transcript format."
            }
        }
    }

    static func parseFile(at url: URL) throws -> TranscriptImportPayload {
        let raw = try String(contentsOf: url, encoding: .utf8)
        return try parse(raw: raw, suggestedExtension: url.pathExtension.lowercased())
    }

    static func parse(raw: String, suggestedExtension: String = "") throws -> TranscriptImportPayload {
        if suggestedExtension == "srt", let captions = parseSRT(raw) {
            return .captions(captions)
        }

        if suggestedExtension == "vtt" || raw.trimmingCharacters(in: .whitespacesAndNewlines).hasPrefix("WEBVTT"),
           let captions = parseVTT(raw) {
            return .captions(captions)
        }

        if let lines = parseTimestampedLines(raw), !lines.isEmpty {
            return .timestampedLines(lines)
        }

        if let captions = parseSRT(raw) {
            return .captions(captions)
        }
        if let captions = parseVTT(raw) {
            return .captions(captions)
        }

        throw Error.unsupportedFormat
    }

    private static func parseSRT(_ raw: String) -> [Caption]? {
        let blocks = raw
            .replacingOccurrences(of: "\r\n", with: "\n")
            .components(separatedBy: "\n\n")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }

        guard !blocks.isEmpty else { return nil }

        let captions = blocks.compactMap { block -> Caption? in
            let lines = block.components(separatedBy: "\n").filter { !$0.isEmpty }
            guard !lines.isEmpty else { return nil }

            let timingIndex = lines.first?.contains("-->") == true ? 0 : 1
            guard lines.indices.contains(timingIndex),
                  let (startTime, endTime) = parseRangeLine(lines[timingIndex], separator: "-->", decimalSeparator: ",")
            else {
                return nil
            }

            let textLines = Array(lines.dropFirst(timingIndex + 1))
            let text = textLines.joined(separator: " ").trimmingCharacters(in: .whitespacesAndNewlines)
            guard !text.isEmpty else { return nil }

            return Caption(text: text, startTime: startTime, endTime: endTime)
        }

        return captions.isEmpty ? nil : captions
    }

    private static func parseVTT(_ raw: String) -> [Caption]? {
        let normalized = raw.replacingOccurrences(of: "\r\n", with: "\n")
        let blocks = normalized
            .components(separatedBy: "\n\n")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty && $0 != "WEBVTT" }

        guard !blocks.isEmpty else { return nil }

        let captions = blocks.compactMap { block -> Caption? in
            let lines = block.components(separatedBy: "\n").filter { !$0.isEmpty }
            guard !lines.isEmpty else { return nil }

            let timingIndex = lines.first?.contains("-->") == true ? 0 : 1
            guard lines.indices.contains(timingIndex),
                  let (startTime, endTime) = parseRangeLine(lines[timingIndex], separator: "-->", decimalSeparator: ".")
            else {
                return nil
            }

            let textLines = Array(lines.dropFirst(timingIndex + 1))
            let text = textLines.joined(separator: " ").trimmingCharacters(in: .whitespacesAndNewlines)
            guard !text.isEmpty else { return nil }

            return Caption(text: text, startTime: startTime, endTime: endTime)
        }

        return captions.isEmpty ? nil : captions
    }

    private static func parseTimestampedLines(_ raw: String) -> [TimestampedTranscriptLine]? {
        let pattern = #"^\[?(\d{1,2}:\d{2}(?::\d{2})?)\]?\s+(.+)$"#
        let regex = try? NSRegularExpression(pattern: pattern, options: [.anchorsMatchLines])
        let fullRange = NSRange(raw.startIndex..., in: raw)
        let matches = regex?.matches(in: raw, options: [], range: fullRange) ?? []

        let lines = matches.compactMap { match -> TimestampedTranscriptLine? in
            guard let timeRange = Range(match.range(at: 1), in: raw),
                  let textRange = Range(match.range(at: 2), in: raw),
                  let seconds = parseTimestamp(String(raw[timeRange]))
            else {
                return nil
            }

            let text = String(raw[textRange]).trimmingCharacters(in: .whitespacesAndNewlines)
            guard !text.isEmpty else { return nil }
            return TimestampedTranscriptLine(
                startTime: CMTime(seconds: seconds, preferredTimescale: 600),
                text: text
            )
        }

        return lines.isEmpty ? nil : lines
    }

    private static func parseRangeLine(
        _ line: String,
        separator: String,
        decimalSeparator: Character
    ) -> (CMTime, CMTime)? {
        let parts = line.components(separatedBy: separator)
        guard parts.count == 2,
              let start = parseClockTime(parts[0], decimalSeparator: decimalSeparator),
              let end = parseClockTime(parts[1], decimalSeparator: decimalSeparator)
        else {
            return nil
        }
        return (start, end)
    }

    private static func parseClockTime(_ raw: String, decimalSeparator: Character) -> CMTime? {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        let pieces = trimmed.split(separator: ":")
        guard pieces.count >= 2 else { return nil }

        let hours: Double
        let minutes: Double
        let seconds: Double

        if pieces.count == 3 {
            hours = Double(pieces[0]) ?? 0
            minutes = Double(pieces[1]) ?? 0
            seconds = parseSecondsComponent(String(pieces[2]), decimalSeparator: decimalSeparator)
        } else {
            hours = 0
            minutes = Double(pieces[0]) ?? 0
            seconds = parseSecondsComponent(String(pieces[1]), decimalSeparator: decimalSeparator)
        }

        return CMTime(seconds: (hours * 3600) + (minutes * 60) + seconds, preferredTimescale: 600)
    }

    private static func parseSecondsComponent(_ raw: String, decimalSeparator: Character) -> Double {
        let normalized = raw.replacingOccurrences(of: String(decimalSeparator), with: ".")
        return Double(normalized) ?? 0
    }

    private static func parseTimestamp(_ raw: String) -> Double? {
        let pieces = raw.split(separator: ":").compactMap { Double($0) }

        switch pieces.count {
        case 2:
            return (pieces[0] * 60) + pieces[1]
        case 3:
            return (pieces[0] * 3600) + (pieces[1] * 60) + pieces[2]
        default:
            return nil
        }
    }
}

// MARK: - Caption Style Presets

// Moved to Core/Models/CaptionStyle.swift
