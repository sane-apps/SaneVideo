//
//  ShortCandidate.swift
//  SaneVideo
//
//  Model for short-form video candidates extracted from long-form content
//

import CoreMedia
import Foundation

/// Type of highlight detected in a short candidate
enum HighlightType: String, Codable, Sendable, CaseIterable {
    case applause = "Applause"
    case laughter = "Laughter"
    case keyMoment = "Key Moment"
    case musicPeak = "Music Peak"
    case speechEmphasis = "Speech Emphasis"
    case visualAction = "Visual Action"
    case faceReaction = "Reaction"

    var icon: String {
        switch self {
        case .applause: return "hands.clap.fill"
        case .laughter: return "face.smiling.fill"
        case .keyMoment: return "star.fill"
        case .musicPeak: return "waveform.path"
        case .speechEmphasis: return "quote.bubble.fill"
        case .visualAction: return "figure.run"
        case .faceReaction: return "person.crop.circle"
        }
    }

    var color: String {
        switch self {
        case .applause: return "orange"
        case .laughter: return "yellow"
        case .keyMoment: return "purple"
        case .musicPeak: return "blue"
        case .speechEmphasis: return "green"
        case .visualAction: return "red"
        case .faceReaction: return "pink"
        }
    }
}

/// Suggested crop region for reframing to vertical aspect ratio
struct SuggestedCrop: Codable, Sendable, Equatable {
    var centerX: CGFloat  // 0.0 - 1.0 normalized position
    var centerY: CGFloat  // 0.0 - 1.0 normalized position
    var scale: CGFloat    // 1.0 = full frame, higher = more zoom

    static let `default` = SuggestedCrop(centerX: 0.5, centerY: 0.5, scale: 1.0)

    /// Create crop focused on a face at given position
    static func focusedOn(faceCenter: CGPoint, zoom: CGFloat = 1.2) -> SuggestedCrop {
        SuggestedCrop(
            centerX: faceCenter.x,
            centerY: faceCenter.y,
            scale: zoom
        )
    }
}

/// A candidate short-form clip extracted from long-form content
struct ShortCandidate: Identifiable, Codable, Sendable, Equatable {
    let id: UUID
    var sourceClipId: UUID?           // Original clip this was extracted from
    var timeRange: CMTimeRange        // Time range in source video
    var score: Double                 // Overall quality score 0.0 - 1.0
    var suggestedCrop: SuggestedCrop  // Smart crop for vertical reframe
    var titleSuggestion: String?      // AI-suggested title
    var highlights: [HighlightType]   // Detected highlights in this segment

    // Analysis metadata
    var hasFace: Bool                 // Contains prominent face
    var silencePercentage: Double     // % of segment that is silence
    var averageLoudness: Double       // Average audio level
    var hasCaption: Bool              // Has caption data

    init(
        id: UUID = UUID(),
        sourceClipId: UUID? = nil,
        timeRange: CMTimeRange,
        score: Double = 0.5,
        suggestedCrop: SuggestedCrop = .default,
        titleSuggestion: String? = nil,
        highlights: [HighlightType] = [],
        hasFace: Bool = false,
        silencePercentage: Double = 0.0,
        averageLoudness: Double = 0.0,
        hasCaption: Bool = false
    ) {
        self.id = id
        self.sourceClipId = sourceClipId
        self.timeRange = timeRange
        self.score = score
        self.suggestedCrop = suggestedCrop
        self.titleSuggestion = titleSuggestion
        self.highlights = highlights
        self.hasFace = hasFace
        self.silencePercentage = silencePercentage
        self.averageLoudness = averageLoudness
        self.hasCaption = hasCaption
    }

    // MARK: - Computed Properties

    var duration: Double {
        timeRange.duration.seconds
    }

    var startTime: Double {
        timeRange.start.seconds
    }

    var endTime: Double {
        timeRange.end.seconds
    }

    /// Human-readable score label
    var scoreLabel: String {
        switch score {
        case 0.8...: return "Excellent"
        case 0.6..<0.8: return "Good"
        case 0.4..<0.6: return "Fair"
        default: return "Low"
        }
    }

    /// Formatted duration string
    var durationLabel: String {
        let seconds = Int(duration)
        if seconds >= 60 {
            return "\(seconds / 60)m \(seconds % 60)s"
        }
        return "\(seconds)s"
    }

    // MARK: - Codable

    enum CodingKeys: String, CodingKey {
        case id, sourceClipId, score, suggestedCrop, titleSuggestion
        case highlights, hasFace, silencePercentage, averageLoudness, hasCaption
        case timeRangeStart, timeRangeDuration
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        sourceClipId = try container.decodeIfPresent(UUID.self, forKey: .sourceClipId)
        score = try container.decode(Double.self, forKey: .score)
        suggestedCrop = try container.decode(SuggestedCrop.self, forKey: .suggestedCrop)
        titleSuggestion = try container.decodeIfPresent(String.self, forKey: .titleSuggestion)
        highlights = try container.decode([HighlightType].self, forKey: .highlights)
        hasFace = try container.decode(Bool.self, forKey: .hasFace)
        silencePercentage = try container.decode(Double.self, forKey: .silencePercentage)
        averageLoudness = try container.decode(Double.self, forKey: .averageLoudness)
        hasCaption = try container.decode(Bool.self, forKey: .hasCaption)

        let startSeconds = try container.decode(Double.self, forKey: .timeRangeStart)
        let durationSeconds = try container.decode(Double.self, forKey: .timeRangeDuration)
        timeRange = CMTimeRange(
            start: CMTime(seconds: startSeconds, preferredTimescale: 600),
            duration: CMTime(seconds: durationSeconds, preferredTimescale: 600)
        )
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encodeIfPresent(sourceClipId, forKey: .sourceClipId)
        try container.encode(score, forKey: .score)
        try container.encode(suggestedCrop, forKey: .suggestedCrop)
        try container.encodeIfPresent(titleSuggestion, forKey: .titleSuggestion)
        try container.encode(highlights, forKey: .highlights)
        try container.encode(hasFace, forKey: .hasFace)
        try container.encode(silencePercentage, forKey: .silencePercentage)
        try container.encode(averageLoudness, forKey: .averageLoudness)
        try container.encode(hasCaption, forKey: .hasCaption)
        try container.encode(timeRange.start.seconds, forKey: .timeRangeStart)
        try container.encode(timeRange.duration.seconds, forKey: .timeRangeDuration)
    }
}

// MARK: - Hashable

extension ShortCandidate: Hashable {
    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }
}
