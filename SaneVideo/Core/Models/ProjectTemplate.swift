//
//  ProjectTemplate.swift
//  SaneVideo
//
//  Pre-configured project templates for different platforms
//

import AVFoundation
import Foundation

/// Project template with pre-configured settings
struct ProjectTemplate: Identifiable, Sendable {
    let id: UUID
    let name: String
    let description: String
    let icon: String
    let color: String
    let aspectRatio: CGSize
    let defaultExportSettings: SaneExportSettings
    let defaultCaptionStyle: String

    static let allTemplates: [ProjectTemplate] = [
        .youtube,
        .tiktok,
        .instagram,
        .custom
    ]

    // MARK: - Templates

    static let youtube = ProjectTemplate(
        id: UUID(),
        name: "YouTube",
        description: "16:9 landscape • 1080p or 4K • Best for long-form content",
        icon: "play.rectangle.fill",
        color: "red",
        aspectRatio: CGSize(width: 16, height: 9),
        defaultExportSettings: SaneExportSettings(
            codec: .hevc,
            resolution: .uhd4K,
            bitrate: 20_000_000,
            frameRate: 60.0
        ),
        defaultCaptionStyle: "YouTube"
    )

    static let tiktok = ProjectTemplate(
        id: UUID(),
        name: "TikTok",
        description: "9:16 vertical • 1080p • Optimized for mobile viewing",
        icon: "music.note.tv.fill",
        color: "black",
        aspectRatio: CGSize(width: 9, height: 16),
        defaultExportSettings: SaneExportSettings(
            codec: .h264,
            resolution: .hd1080,
            bitrate: 8_000_000,
            frameRate: 60.0
        ),
        defaultCaptionStyle: "TikTok"
    )

    static let instagram = ProjectTemplate(
        id: UUID(),
        name: "Instagram",
        description: "1:1 square or 4:5 • 1080p • Perfect for Reels and posts",
        icon: "square.and.arrow.up.fill",
        color: "purple",
        aspectRatio: CGSize(width: 1, height: 1),
        defaultExportSettings: SaneExportSettings(
            codec: .h264,
            resolution: .hd1080,
            bitrate: 10_000_000,
            frameRate: 30.0
        ),
        defaultCaptionStyle: "Instagram"
    )

    static let custom = ProjectTemplate(
        id: UUID(),
        name: "Custom",
        description: "Default settings • Fully customizable",
        icon: "slider.horizontal.3",
        color: "blue",
        aspectRatio: CGSize(width: 16, height: 9),
        defaultExportSettings: SaneExportSettings(),
        defaultCaptionStyle: "Classic"
    )
}
