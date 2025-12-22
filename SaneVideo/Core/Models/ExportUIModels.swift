//
//  ExportUIModels.swift
//  SaneVideo
//
//  Created by SaneVideo Refactor
//

import Foundation

enum ExportPreset: String, CaseIterable {
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
            return "1080p HD, H.264 • 1:1 square or 4:5"
        case .twitter:
            return "1080p HD, H.264 • Twitter/X optimized"
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
