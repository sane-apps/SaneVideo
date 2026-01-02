//
//  ExportUIModels.swift
//  SaneVideo
//
//  Created by SaneVideo Refactor
//

import Foundation

// MARK: - Smart Crop Settings

/// Settings for AI-powered smart cropping during export
/// Uses face detection and/or saliency analysis to keep subjects in frame
public struct SmartCropSettings: Codable, Sendable, Equatable {
    /// Enable smart cropping
    public var enabled: Bool = false

    /// What to track for cropping
    public var trackingMode: TrackingMode = .face

    /// Keyframe smoothing factor (0.0-1.0, higher = smoother but less responsive)
    public var smoothing: Double = 0.3

    public init(enabled: Bool = false, trackingMode: TrackingMode = .face, smoothing: Double = 0.3) {
        self.enabled = enabled
        self.trackingMode = trackingMode
        self.smoothing = smoothing
    }

    /// Tracking mode options
    public enum TrackingMode: String, Codable, Sendable, CaseIterable {
        case face       // Track faces (best for talking head videos)
        case saliency   // Track visual interest (best for action/product videos)
        case combined   // Use both, prefer faces when present

        public var displayName: String {
            switch self {
            case .face: return "Face Tracking"
            case .saliency: return "Visual Interest"
            case .combined: return "Smart (Combined)"
            }
        }

        public var icon: String {
            switch self {
            case .face: return "person.crop.rectangle"
            case .saliency: return "sparkle.magnifyingglass"
            case .combined: return "brain.head.profile"
            }
        }
    }
}

// MARK: - Export Presets

enum ExportPreset: String, CaseIterable, Identifiable {
    var id: String { rawValue }
    case custom = "Custom"
    case youtube4K = "YouTube 4K"
    case youtube1080 = "YouTube 1080p"
    case tiktok = "TikTok"
    case instagram = "Instagram"
    case twitter = "Twitter"
    case facebook = "Facebook"
    case social1080 = "Social (1080p)"
    case compressed = "Compressed"

    var description: String {
        switch self {
        case .custom:
            return "Manual settings"
        case .youtube4K:
            return "4K UHD, HEVC • Best for YouTube uploads"
        case .youtube1080:
            return "1080p HD, H.264 • YouTube standard"
        case .tiktok:
            return "1080p HD, H.264 • 9:16 vertical format"
        case .instagram:
            return "1080p HD, H.264 • 9:16 vertical (Reels)"
        case .twitter:
            return "1080p HD, H.264 • 9:16 vertical format"
        case .facebook:
            return "1080p HD, H.264 • Facebook optimized"
        case .social1080:
            return "1080p HD, H.264 • Compatible with all platforms"
        case .compressed:
            return "1080p HD, HEVC • Smaller file size"
        }
    }

    var icon: String {
        switch self {
        case .custom: return "slider.horizontal.3"
        case .youtube4K: return "play.rectangle.fill"
        case .youtube1080: return "play.rectangle"
        case .tiktok: return "music.note.tv.fill"
        case .instagram: return "square.and.arrow.up.fill"
        case .twitter: return "bird.fill"
        case .facebook: return "f.circle.fill"
        case .social1080: return "square.stack.3d.up.fill"
        case .compressed: return "arrow.down.circle.fill"
        }
    }
}
