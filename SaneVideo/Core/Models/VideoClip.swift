//
//  VideoClip.swift
//  SaneVideo
//
//  Domain model representing a video clip with editing state
//  Optimized for Apple Silicon M1+ with value semantics and lazy asset loading
//

import AVFoundation
import Foundation

/// A video clip in the timeline with trim and filter settings
/// Note: Value type (struct) for better performance, memory safety, and copy-on-write semantics
/// Sendable for safe cross-actor usage (Swift 6 compliance)
struct VideoClip: Identifiable, Equatable, Hashable, Codable, Sendable {
    let id: UUID
    var url: URL
    var duration: CMTime

    // Playback
    var startTime: CMTime = .zero
    var trimStart: CMTime = .zero
    var trimEnd: CMTime // Initialized to duration
    var volume: Float = 1.0
    var isMuted: Bool = false
    var speed: Double = 1.0
    var thumbnailURL: URL? // Smart Thumbnail

    // Visual
    var rotation: Rotation = .none

    var opacity: Double = 1.0 // New property
    
    // Effects
    var effects: [VideoEffect] = []
    
    // Privacy
    var privacyRegions: [PrivacyRegion] = []

    // Advanced Features
    var transition: VideoTransition?
    var overlays: [VideoOverlay] = []
    var keyframeAnimation: KeyframeAnimation?

    var captions: [Caption] = []

    var cursorDataURL: URL?
    var showCursorHighlight: Bool = false
    
    // Background Effects (Person Segmentation)
    var backgroundEffect: BackgroundEffect?

    // Audio Enhancement (Studio Sound)
    var enhancedAudioURL: URL?

    // Security Scoped Bookmark
    var bookmarkData: Data?

    // Non-destructive editing
    var removedRanges: [CodableTimeRange] = []
    var useSmoothCutForRemovals: Bool = false

    // AI Audio Settings
    var isVoiceIsolationEnabled: Bool = false
    var isGatingEnabled: Bool = false

    /// Flattened list of all words from all captions (for filler detection)
    var allWords: [CaptionWord] {
        captions.flatMap { $0.words ?? [] }
    }

    // MARK: - Transform

    struct Transform: Codable, Equatable, Hashable, Sendable {
        // Normalized offset from center. (0,0) is center.
        var offset: CGPoint = .zero

        // Scale factor. 1.0 is original size.
        var scale: CGFloat = 1.0

        static let identity = Transform()
    }

    var transform: Transform = .identity

    // MARK: - Initialization

    /// Initialize with URL and duration
    /// Note: Bookmarks should be managed externally by ProjectFileManager
    init(url: URL, duration: CMTime, startTime: CMTime = .zero, trimStart: CMTime = .zero, bookmarkData: Data? = nil) {
        id = UUID()
        self.url = url
        self.duration = duration
        trimEnd = duration
        self.startTime = startTime
        self.trimStart = trimStart
        self.bookmarkData = bookmarkData
    }

    // Internal init for full property setting
    init(id: UUID, url: URL, duration: CMTime, trimStart: CMTime, trimEnd: CMTime, startTime: CMTime, volume: Float, speed: Double, isMuted: Bool, captions: [Caption] = [], transition: VideoTransition? = nil, overlays: [VideoOverlay] = [], bookmarkData: Data? = nil, showCursorHighlight: Bool = false, cursorDataURL: URL? = nil, thumbnailURL: URL? = nil) {
        self.id = id
        self.url = url
        self.duration = duration
        self.trimStart = trimStart
        self.trimEnd = trimEnd
        self.startTime = startTime
        self.volume = volume
        self.speed = speed
        self.isMuted = isMuted
        self.captions = captions
        self.transition = transition
        self.overlays = overlays
        self.bookmarkData = bookmarkData
        self.showCursorHighlight = showCursorHighlight
        self.cursorDataURL = cursorDataURL
        self.thumbnailURL = thumbnailURL
        self.useSmoothCutForRemovals = false
    }

    // MARK: - Rotation

    enum Rotation: Int, Codable, CaseIterable, Sendable {
        case none = 0
        case clockwise90 = 90
        case clockwise180 = 180
        case clockwise270 = 270

        var displayName: String {
            switch self {
            case .none: return "Original"
            case .clockwise90: return "90° CW"
            case .clockwise180: return "180°"
            case .clockwise270: return "90° CCW"
            }
        }

        var next: Rotation {
            switch self {
            case .none: return .clockwise90
            case .clockwise90: return .clockwise180
            case .clockwise180: return .clockwise270
            case .clockwise270: return .none
            }
        }

        var counterClockwise: Rotation {
            switch self {
            case .none: return .clockwise270
            case .clockwise90: return .none
            case .clockwise180: return .clockwise90
            case .clockwise270: return .clockwise180
            }
        }

        var radians: CGFloat {
            CGFloat(rawValue) * .pi / 180.0
        }
    }

    mutating func rotateClockwise() {
        rotation = rotation.next
    }

    // MARK: - Advanced Types

    enum VideoClipError: Error {
        case bookmarkResolutionFailed
    }

    struct VideoOverlay: Identifiable, Codable, Equatable, Hashable, Sendable {
        var id: UUID = .init()
        var text: String
        var startTime: Double // Relative to clip start
        var duration: Double
        var position: CGPoint // Normalized (0-1)
        var scale: CGFloat = 1.0
        var rotation: Double = 0.0 // Radians

        static func == (lhs: VideoOverlay, rhs: VideoOverlay) -> Bool {
            lhs.id == rhs.id
        }

        func hash(into hasher: inout Hasher) {
            hasher.combine(id)
        }
    }

    // MARK: - Equatable & Hashable

    static func == (lhs: VideoClip, rhs: VideoClip) -> Bool {
        lhs.id == rhs.id &&
            lhs.trimStart == rhs.trimStart &&
            lhs.trimEnd == rhs.trimEnd &&
            lhs.removedRanges == rhs.removedRanges &&
            lhs.startTime == rhs.startTime &&
            lhs.rotation == rhs.rotation &&
            lhs.volume == rhs.volume &&
            lhs.isMuted == rhs.isMuted &&
            lhs.transition == rhs.transition &&
            lhs.overlays == rhs.overlays &&
            lhs.effects == rhs.effects &&
            lhs.isVoiceIsolationEnabled == rhs.isVoiceIsolationEnabled &&
            lhs.isGatingEnabled == rhs.isGatingEnabled &&
            lhs.thumbnailURL == rhs.thumbnailURL &&
            lhs.useSmoothCutForRemovals == rhs.useSmoothCutForRemovals
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
        hasher.combine(trimStart)
        hasher.combine(trimEnd)
        hasher.combine(removedRanges)
        hasher.combine(startTime)
        hasher.combine(rotation)
        hasher.combine(speed)
        hasher.combine(volume)
        hasher.combine(isMuted)
        hasher.combine(overlays)
        hasher.combine(effects)
        hasher.combine(isVoiceIsolationEnabled)
        hasher.combine(isGatingEnabled)
        hasher.combine(thumbnailURL)
        hasher.combine(useSmoothCutForRemovals)
    }

    // MARK: - Codable Implementation
    
    enum CodingKeys: String, CodingKey {
        case id, url, duration, trimStart, trimEnd
        case startTime, volume, speed, isMuted, captions
        case transition, overlays, bookmarkData, rotation
        case removedRanges, useSmoothCutForRemovals
        case transform
        case cursorDataURL, showCursorHighlight
        case backgroundEffect
        case privacyRegions
        case isVoiceIsolationEnabled
        case isGatingEnabled
        case thumbnailURL
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        url = try container.decode(URL.self, forKey: .url)
        bookmarkData = try container.decodeIfPresent(Data.self, forKey: .bookmarkData)

        let durationSeconds = try container.decode(Double.self, forKey: .duration)
        duration = CMTime(seconds: durationSeconds, preferredTimescale: 600)

        let trimStartSeconds = try container.decode(Double.self, forKey: .trimStart)
        trimStart = CMTime(seconds: trimStartSeconds, preferredTimescale: 600)

        let trimEndSeconds = try container.decode(Double.self, forKey: .trimEnd)
        trimEnd = CMTime(seconds: trimEndSeconds, preferredTimescale: 600)

        let startTimeSeconds = try container.decodeIfPresent(Double.self, forKey: .startTime) ?? 0
        startTime = CMTime(seconds: startTimeSeconds, preferredTimescale: 600)

        volume = try container.decodeIfPresent(Float.self, forKey: .volume) ?? 1.0
        speed = try container.decodeIfPresent(Double.self, forKey: .speed) ?? 1.0
        isMuted = try container.decodeIfPresent(Bool.self, forKey: .isMuted) ?? false
        captions = try container.decodeIfPresent([Caption].self, forKey: .captions) ?? []
        rotation = try container.decodeIfPresent(Rotation.self, forKey: .rotation) ?? .none
        transform = try container.decodeIfPresent(Transform.self, forKey: .transform) ?? .identity
        transition = try container.decodeIfPresent(VideoTransition.self, forKey: .transition)
        overlays = try container.decodeIfPresent([VideoOverlay].self, forKey: .overlays) ?? []
        removedRanges = try container.decodeIfPresent([CodableTimeRange].self, forKey: .removedRanges) ?? []
        useSmoothCutForRemovals = try container.decodeIfPresent(Bool.self, forKey: .useSmoothCutForRemovals) ?? false

        cursorDataURL = try container.decodeIfPresent(URL.self, forKey: .cursorDataURL)
        showCursorHighlight = try container.decodeIfPresent(Bool.self, forKey: .showCursorHighlight) ?? false
        backgroundEffect = try container.decodeIfPresent(BackgroundEffect.self, forKey: .backgroundEffect)
        privacyRegions = try container.decodeIfPresent([PrivacyRegion].self, forKey: .privacyRegions) ?? []
        isVoiceIsolationEnabled = try container.decodeIfPresent(Bool.self, forKey: .isVoiceIsolationEnabled) ?? false
        isGatingEnabled = try container.decodeIfPresent(Bool.self, forKey: .isGatingEnabled) ?? false
        thumbnailURL = try container.decodeIfPresent(URL.self, forKey: .thumbnailURL)
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(url, forKey: .url)
        try container.encode(duration.seconds, forKey: .duration)
        try container.encode(trimStart.seconds, forKey: .trimStart)
        try container.encode(trimEnd.seconds, forKey: .trimEnd)
        try container.encode(startTime.seconds, forKey: .startTime)
        try container.encode(volume, forKey: .volume)
        try container.encode(speed, forKey: .speed)
        try container.encode(isMuted, forKey: .isMuted)
        try container.encode(captions, forKey: .captions)
        try container.encode(rotation, forKey: .rotation)
        try container.encode(transform, forKey: .transform)
        try container.encodeIfPresent(transition, forKey: .transition)
        try container.encode(overlays, forKey: .overlays)
        try container.encodeIfPresent(bookmarkData, forKey: .bookmarkData)
        try container.encode(removedRanges, forKey: .removedRanges)
        try container.encode(useSmoothCutForRemovals, forKey: .useSmoothCutForRemovals)
        try container.encodeIfPresent(cursorDataURL, forKey: .cursorDataURL)
        try container.encode(showCursorHighlight, forKey: .showCursorHighlight)
        try container.encodeIfPresent(backgroundEffect, forKey: .backgroundEffect)
        try container.encode(privacyRegions, forKey: .privacyRegions)
        try container.encode(isVoiceIsolationEnabled, forKey: .isVoiceIsolationEnabled)
        try container.encode(isGatingEnabled, forKey: .isGatingEnabled)
        try container.encodeIfPresent(thumbnailURL, forKey: .thumbnailURL)
    }
}
