//
//  CustomTemplate.swift
//  SaneVideo
//
//  User-created export templates for saving and reusing settings
//

import AVFoundation
import Foundation

/// User-created template with custom export settings
struct CustomTemplate: Identifiable, Codable, Sendable, Hashable {
    let id: UUID
    var name: String
    var description: String
    var icon: String
    var color: String
    var aspectRatio: CGSize
    var exportSettings: SaneExportSettings
    var captionStyle: String
    var presentationPreset: PresentationPreset
    var speakerNotes: SpeakerNotes
    var chapterMarkers: [ChapterMarker]
    var demoPackSettings: DemoPackSettings
    var publishMetadata: PublishMetadata
    var createdAt: Date
    var modifiedAt: Date

    init(
        id: UUID = UUID(),
        name: String,
        description: String = "",
        icon: String = "star.fill",
        color: String = "blue",
        aspectRatio: CGSize = CGSize(width: 16, height: 9),
        exportSettings: SaneExportSettings = SaneExportSettings(),
        captionStyle: String = "Classic",
        presentationPreset: PresentationPreset = .productWalkthrough,
        speakerNotes: SpeakerNotes = .init(),
        chapterMarkers: [ChapterMarker] = [],
        demoPackSettings: DemoPackSettings = .init(),
        publishMetadata: PublishMetadata = .init()
    ) {
        self.id = id
        self.name = name
        self.description = description
        self.icon = icon
        self.color = color
        self.aspectRatio = aspectRatio
        self.exportSettings = exportSettings
        self.captionStyle = captionStyle
        self.presentationPreset = presentationPreset
        self.speakerNotes = speakerNotes
        self.chapterMarkers = chapterMarkers
        self.demoPackSettings = demoPackSettings
        self.publishMetadata = publishMetadata
        self.createdAt = Date()
        self.modifiedAt = Date()
    }

    // MARK: - Hashable

    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }

    static func == (lhs: CustomTemplate, rhs: CustomTemplate) -> Bool {
        lhs.id == rhs.id
    }

    // MARK: - Computed Properties

    var aspectRatioString: String {
        let w = Int(aspectRatio.width)
        let h = Int(aspectRatio.height)
        return "\(w):\(h)"
    }

    var resolutionString: String {
        exportSettings.resolution.displayName
    }

    var codecString: String {
        switch exportSettings.codec {
        case .h264: return "H.264"
        case .hevc: return "HEVC"
        case .proRes422: return "ProRes"
        default: return "Unknown"
        }
    }
}

// MARK: - Template Icons

extension CustomTemplate {
    static let availableIcons = [
        "star.fill",
        "heart.fill",
        "bolt.fill",
        "flame.fill",
        "sparkles",
        "wand.and.stars",
        "play.rectangle.fill",
        "film.stack.fill",
        "camera.fill",
        "mic.fill",
        "music.note",
        "globe"
    ]

    static let availableColors = [
        "blue",
        "purple",
        "pink",
        "red",
        "orange",
        "yellow",
        "green",
        "teal"
    ]
}
