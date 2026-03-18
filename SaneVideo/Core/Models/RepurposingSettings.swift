//
//  RepurposingSettings.swift
//  SaneVideo
//
//  Settings for long-to-short video repurposing
//

import Foundation

/// Target duration for short-form clips
enum ShortDuration: Int, CaseIterable, Identifiable, Codable, Sendable {
    case fifteen = 15
    case thirty = 30
    case sixty = 60
    case ninety = 90

    var id: Int { rawValue }

    var label: String {
        switch self {
        case .fifteen: return "15s"
        case .thirty: return "30s"
        case .sixty: return "60s"
        case .ninety: return "90s"
        }
    }

    var description: String {
        switch self {
        case .fifteen: return "TikTok/Reels (Short)"
        case .thirty: return "TikTok/Reels (Standard)"
        case .sixty: return "YouTube Shorts"
        case .ninety: return "Extended Short"
        }
    }

    var icon: String {
        switch self {
        case .fifteen: return "bolt.fill"
        case .thirty: return "sparkles"
        case .sixty: return "play.rectangle.fill"
        case .ninety: return "film.fill"
        }
    }
}

/// Target aspect ratio for short-form clips
public enum ShortAspectRatio: String, CaseIterable, Identifiable, Codable, Sendable {
    case vertical9x16 = "9:16"
    case square1x1 = "1:1"
    case portrait4x5 = "4:5"

    public var id: String { rawValue }

    public var label: String { rawValue }

    public var description: String {
        switch self {
        case .vertical9x16: return "TikTok, Reels, Shorts"
        case .square1x1: return "Instagram Feed"
        case .portrait4x5: return "Instagram Portrait"
        }
    }

    public var icon: String {
        switch self {
        case .vertical9x16: return "rectangle.portrait.fill"
        case .square1x1: return "square.fill"
        case .portrait4x5: return "rectangle.portrait"
        }
    }

    public var widthRatio: CGFloat {
        switch self {
        case .vertical9x16: return 9
        case .square1x1: return 1
        case .portrait4x5: return 4
        }
    }

    public var heightRatio: CGFloat {
        switch self {
        case .vertical9x16: return 16
        case .square1x1: return 1
        case .portrait4x5: return 5
        }
    }

    /// Calculate output dimensions for a given height
    public func dimensions(forHeight height: Int) -> (width: Int, height: Int) {
        let aspectRatio = widthRatio / heightRatio
        let width = Int(CGFloat(height) * aspectRatio)
        // Ensure even dimensions for video encoding
        return (width: width - (width % 2), height: height - (height % 2))
    }
}

/// Target platform presets for short-form content
enum ShortPlatform: String, CaseIterable, Identifiable, Codable, Sendable {
    case tiktok = "TikTok"
    case instagramReels = "Instagram Reels"
    case youtubeShorts = "YouTube Shorts"
    case custom = "Custom"

    var id: String { rawValue }

    var icon: String {
        switch self {
        case .tiktok: return "music.note"
        case .instagramReels: return "camera.fill"
        case .youtubeShorts: return "play.rectangle.fill"
        case .custom: return "slider.horizontal.3"
        }
    }

    var description: String {
        switch self {
        case .tiktok:
            return "Fast-paced vertical clips with aggressive trimming."
        case .instagramReels:
            return "Vertical reels with a slightly cleaner, more polished pacing."
        case .youtubeShorts:
            return "Longer vertical clips that can hold a fuller explanation."
        case .custom:
            return "Start neutral, then tune duration, crop, and export settings manually."
        }
    }

    var recommendedDuration: ShortDuration {
        switch self {
        case .tiktok: return .thirty
        case .instagramReels: return .thirty
        case .youtubeShorts: return .sixty
        case .custom: return .thirty
        }
    }

    var recommendedAspectRatio: ShortAspectRatio {
        switch self {
        case .tiktok: return .vertical9x16
        case .instagramReels: return .vertical9x16
        case .youtubeShorts: return .vertical9x16
        case .custom: return .vertical9x16
        }
    }
}

/// Settings for the repurposing analysis and export
struct RepurposingSettings: Codable, Sendable, Equatable {
    var targetDuration: ShortDuration
    var aspectRatio: ShortAspectRatio
    var platform: ShortPlatform
    var maxShorts: Int  // 1-10

    // Analysis options
    var detectFaces: Bool
    var detectHighlights: Bool
    var useCaptions: Bool
    var avoidSilence: Bool

    // Export options
    var addCaptions: Bool
    var smartCrop: Bool
    var normalizeAudio: Bool

    init(
        targetDuration: ShortDuration = .thirty,
        aspectRatio: ShortAspectRatio = .vertical9x16,
        platform: ShortPlatform = .tiktok,
        maxShorts: Int = 5,
        detectFaces: Bool = true,
        detectHighlights: Bool = true,
        useCaptions: Bool = true,
        avoidSilence: Bool = true,
        addCaptions: Bool = true,
        smartCrop: Bool = true,
        normalizeAudio: Bool = true
    ) {
        self.targetDuration = targetDuration
        self.aspectRatio = aspectRatio
        self.platform = platform
        self.maxShorts = min(max(maxShorts, 1), 10)
        self.detectFaces = detectFaces
        self.detectHighlights = detectHighlights
        self.useCaptions = useCaptions
        self.avoidSilence = avoidSilence
        self.addCaptions = addCaptions
        self.smartCrop = smartCrop
        self.normalizeAudio = normalizeAudio
    }

    /// Apply platform preset settings
    mutating func applyPlatformPreset(_ platform: ShortPlatform) {
        self.platform = platform
        self.targetDuration = platform.recommendedDuration
        self.aspectRatio = platform.recommendedAspectRatio
    }

    /// Default settings for quick access
    static let `default` = RepurposingSettings()

    /// TikTok optimized settings
    static let tiktok = RepurposingSettings(
        targetDuration: .thirty,
        aspectRatio: .vertical9x16,
        platform: .tiktok,
        maxShorts: 5
    )

    /// YouTube Shorts optimized settings
    static let youtubeShorts = RepurposingSettings(
        targetDuration: .sixty,
        aspectRatio: .vertical9x16,
        platform: .youtubeShorts,
        maxShorts: 3
    )

    /// Instagram Reels optimized settings
    static let instagramReels = RepurposingSettings(
        targetDuration: .thirty,
        aspectRatio: .vertical9x16,
        platform: .instagramReels,
        maxShorts: 5
    )
}
