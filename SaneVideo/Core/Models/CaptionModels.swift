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

// MARK: - Caption Style Presets

// Moved to Core/Models/CaptionStyle.swift
