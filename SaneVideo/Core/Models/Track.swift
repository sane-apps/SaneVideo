//
//  Track.swift
//  SaneVideo
//
//  Created by SaneVideo Refactor
//

import Foundation

/// Represents a single timeline track (layer)
/// Tracks are stacked vertically, with higher zIndex appearing "on top" visually
struct Track: Identifiable, Codable, Equatable, Sendable {
    let id: UUID
    var name: String
    var type: TrackType
    var clips: [VideoClip]
    var zIndex: Int
    var isMuted: Bool = false
    var isLocked: Bool = false

    init(id: UUID = UUID(), name: String, type: TrackType, clips: [VideoClip] = [], zIndex: Int) {
        self.id = id
        self.name = name
        self.type = type
        self.clips = clips
        self.zIndex = zIndex
    }

    static func == (lhs: Track, rhs: Track) -> Bool {
        return lhs.id == rhs.id &&
            lhs.name == rhs.name &&
            lhs.type == rhs.type &&
            lhs.clips == rhs.clips &&
            lhs.zIndex == rhs.zIndex &&
            lhs.isMuted == rhs.isMuted &&
            lhs.isLocked == rhs.isLocked
    }
}

enum TrackType: String, Codable, Sendable {
    case video // Main video track
    case audio // Audio only
    case overlay // Text, Graphics, PiP
}
