//
//  VideoProject.swift
//  SaneVideo
//
//  Domain model representing a video editing project
//  Optimized for Apple Silicon M1+ with value semantics

import AVFoundation
import Foundation

/// A video editing project containing a timeline and metadata
/// Note: Value type (struct) for better performance and memory safety
/// Sendable for safe cross-actor usage (Swift 6 compliance)
struct VideoProject: Identifiable, Codable, Equatable, Sendable {
    let id: UUID
    let createdAt: Date
    var name: String
    var timeline: Timeline
    var modifiedAt: Date
    var currentTime: Double = 0.0 // Persist playhead position
    var scrollOffset: CGFloat = 0.0 // Persist horizontal scroll position
    var zoomLevel: CGFloat = 1.0 // Persist timeline zoom level
    var captionStyleName: String = "Classic"
    var captionOffset: CGSize = .zero
    var captionFontName: String?

    init(id: UUID = UUID(), name: String = "Untitled Project", createdAt: Date = Date()) {
        self.id = id
        self.name = name
        self.createdAt = createdAt
        modifiedAt = createdAt
        timeline = Timeline()
        captionStyleName = "Classic"
        captionOffset = .zero
        captionFontName = nil
        currentTime = 0.0
        scrollOffset = 0.0
        zoomLevel = 1.0
    }

    // MARK: - Mutations

    /// Update project name and modification date
    mutating func rename(_ newName: String) {
        name = newName
        modifiedAt = Date()
    }

    /// Update timeline and modification date
    mutating func updateTimeline(_ newTimeline: Timeline) {
        timeline = newTimeline
        modifiedAt = Date()
    }

    /// Update caption offset
    mutating func updateCaptionOffset(_ offset: CGSize) {
        captionOffset = offset
        modifiedAt = Date()
    }

    /// Update caption font
    mutating func updateCaptionFont(_ fontName: String?) {
        captionFontName = fontName
        modifiedAt = Date()
    }
    
    /// Update playback state
    mutating func updatePlaybackState(time: Double, scroll: CGFloat, zoom: CGFloat) {
        currentTime = time
        scrollOffset = scroll
        zoomLevel = zoom
        // Don't update modifiedAt for purely navigational changes to avoid excessive saves?
        // Actually, for "restore state", we probably DO want to save.
        // But maybe debounce it strongly in State.
        modifiedAt = Date() 
    }

    // MARK: - Equatable

    static func == (lhs: VideoProject, rhs: VideoProject) -> Bool {
        lhs.id == rhs.id &&
            lhs.captionOffset == rhs.captionOffset &&
            lhs.captionStyleName == rhs.captionStyleName &&
            lhs.captionFontName == rhs.captionFontName &&
            lhs.timeline == rhs.timeline &&
            lhs.currentTime == rhs.currentTime &&
            lhs.scrollOffset == rhs.scrollOffset &&
            lhs.zoomLevel == rhs.zoomLevel
    }

    // MARK: - Codable

    enum CodingKeys: String, CodingKey {
        case id, createdAt, modifiedAt, name, timeline, captionStyleName, captionOffset, captionFontName
        case currentTime, scrollOffset, zoomLevel
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        createdAt = try container.decode(Date.self, forKey: .createdAt)
        modifiedAt = try container.decodeIfPresent(Date.self, forKey: .modifiedAt) ?? createdAt
        name = try container.decode(String.self, forKey: .name)
        timeline = try container.decode(Timeline.self, forKey: .timeline)
        captionStyleName = try container.decodeIfPresent(String.self, forKey: .captionStyleName) ?? "Classic"
        captionOffset = try container.decodeIfPresent(CGSize.self, forKey: .captionOffset) ?? .zero
        captionFontName = try container.decodeIfPresent(String.self, forKey: .captionFontName)
        currentTime = try container.decodeIfPresent(Double.self, forKey: .currentTime) ?? 0.0
        scrollOffset = try container.decodeIfPresent(CGFloat.self, forKey: .scrollOffset) ?? 0.0
        zoomLevel = try container.decodeIfPresent(CGFloat.self, forKey: .zoomLevel) ?? 1.0
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(createdAt, forKey: .createdAt)
        try container.encode(modifiedAt, forKey: .modifiedAt)
        try container.encode(name, forKey: .name)
        try container.encode(timeline, forKey: .timeline)
        try container.encode(captionStyleName, forKey: .captionStyleName)
        try container.encode(captionOffset, forKey: .captionOffset)
        try container.encodeIfPresent(captionFontName, forKey: .captionFontName)
        try container.encode(currentTime, forKey: .currentTime)
        try container.encode(scrollOffset, forKey: .scrollOffset)
        try container.encode(zoomLevel, forKey: .zoomLevel)
    }
}
