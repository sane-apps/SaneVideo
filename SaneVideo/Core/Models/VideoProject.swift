import AVFoundation
import Foundation

/// A video editing project: a timeline plus caption and teleprompter settings.
struct VideoProject: Identifiable, Codable, Equatable, Sendable {
    let id: UUID
    let createdAt: Date
    var name: String
    var timeline: Timeline
    var modifiedAt: Date
    var currentTime = 0.0
    var scrollOffset: CGFloat = 0.0
    var zoomLevel: CGFloat = 1.0
    var captionStyleName = "Classic"
    var captionOffset: CGSize = .zero
    var captionFontName: String?
    var speakerNotes = SpeakerNotes()

    init(id: UUID = UUID(), name: String = "Untitled Project", createdAt: Date = Date()) {
        self.id = id
        self.name = name
        self.createdAt = createdAt
        modifiedAt = createdAt
        timeline = Timeline()
    }

    var clipCount: Int {
        timeline.tracks.reduce(0) { $0 + $1.clips.count }
    }

    var hasContent: Bool {
        clipCount > 0
    }

    var hasCaptions: Bool {
        timeline.tracks.flatMap(\.clips).contains { !$0.captions.isEmpty }
    }

    mutating func rename(_ newName: String) {
        name = newName
        modifiedAt = Date()
    }

    mutating func updateTimeline(_ newTimeline: Timeline) {
        timeline = newTimeline
        modifiedAt = Date()
    }

    mutating func updateCaptionOffset(_ offset: CGSize) {
        captionOffset = offset
        modifiedAt = Date()
    }

    mutating func updateCaptionFont(_ fontName: String?) {
        captionFontName = fontName
        modifiedAt = Date()
    }

    mutating func updateSpeakerNotes(_ notes: SpeakerNotes) {
        speakerNotes = notes
        modifiedAt = Date()
    }

    mutating func updatePlaybackState(time: Double, scroll: CGFloat, zoom: CGFloat) {
        currentTime = time
        scrollOffset = scroll
        zoomLevel = zoom
        modifiedAt = Date()
    }

    /// modifiedAt is left out so saving a project does not count as a change.
    static func == (lhs: VideoProject, rhs: VideoProject) -> Bool {
        lhs.id == rhs.id &&
            lhs.name == rhs.name &&
            lhs.captionOffset == rhs.captionOffset &&
            lhs.captionStyleName == rhs.captionStyleName &&
            lhs.captionFontName == rhs.captionFontName &&
            lhs.timeline == rhs.timeline &&
            lhs.currentTime == rhs.currentTime &&
            lhs.scrollOffset == rhs.scrollOffset &&
            lhs.zoomLevel == rhs.zoomLevel &&
            lhs.speakerNotes == rhs.speakerNotes
    }

    enum CodingKeys: String, CodingKey {
        case id, createdAt, modifiedAt, name, timeline, captionStyleName, captionOffset, captionFontName
        case currentTime, scrollOffset, zoomLevel, speakerNotes
    }

    /// Older projects may lack newer keys, and may carry keys from removed features; both decode.
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
        speakerNotes = try container.decodeIfPresent(SpeakerNotes.self, forKey: .speakerNotes) ?? SpeakerNotes()
    }
}
