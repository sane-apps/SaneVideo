//
//  VideoClipTypes.swift
//  SaneVideo
//
//  Created by SaneVideo Refactor
//

import AVFoundation
import Foundation

// MARK: - Privacy Region

/// A region to blur for privacy (e.g. sensitive text, faces)
struct PrivacyRegion: Identifiable, Codable, Equatable, Sendable {
    var id: UUID = .init()
    var timeRange: CMTimeRange
    var frame: CGRect // Normalized rect (0-1) in the video frame
    
    enum CodingKeys: String, CodingKey {
        case id, timeRange, frame
    }
    
    init(timeRange: CMTimeRange, frame: CGRect) {
        self.timeRange = timeRange
        self.frame = frame
    }
    
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        frame = try container.decode(CGRect.self, forKey: .frame)
        let codableRange = try container.decode(CodableTimeRange.self, forKey: .timeRange)
        timeRange = codableRange.timeRange
    }
    
    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(frame, forKey: .frame)
        try container.encode(CodableTimeRange(timeRange), forKey: .timeRange)
    }
}

// MARK: - Background Effect

/// Background effect using Apple Vision person segmentation
enum BackgroundEffect: Codable, Equatable, Hashable, Sendable {
    /// Blur the background, keeping person sharp
    case blur(radius: Float)
    
    /// Replace background with a solid color
    case solidColor(red: CGFloat, green: CGFloat, blue: CGFloat, alpha: CGFloat)
    
    /// Replace background with an image
    case image(url: URL)
    
    // MARK: - Display Properties
    
    var displayName: String {
        switch self {
        case .blur: return "Portrait Blur"
        case .solidColor: return "Solid Color"
        case .image: return "Virtual Background"
        }
    }
    
    var icon: String {
        switch self {
        case .blur: return "person.crop.rectangle"
        case .solidColor: return "paintpalette"
        case .image: return "photo"
        }
    }
    
    // MARK: - Presets
    
    static let presets: [(name: String, effect: BackgroundEffect)] = [
        ("Light Blur", .blur(radius: 10)),
        ("Medium Blur", .blur(radius: 20)),
        ("Heavy Blur", .blur(radius: 35)),
        ("Green Screen", .solidColor(red: 0, green: 1, blue: 0, alpha: 1)),
        ("Black", .solidColor(red: 0, green: 0, blue: 0, alpha: 1)),
        ("White", .solidColor(red: 1, green: 1, blue: 1, alpha: 1))
    ]
}

// MARK: - Codable Time Range Helper

/// A Codable wrapper for CMTimeRange
struct CodableTimeRange: Codable, Equatable, Hashable, Sendable {
    let start: Double
    let duration: Double

    init(_ range: CMTimeRange) {
        start = range.start.seconds
        duration = range.duration.seconds
    }

    var timeRange: CMTimeRange {
        CMTimeRange(
            start: CMTime(seconds: start, preferredTimescale: 600),
            duration: CMTime(seconds: duration, preferredTimescale: 600)
        )
    }
}
