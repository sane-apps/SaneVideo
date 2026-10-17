import AVFoundation
import Foundation

struct Timeline: Codable, Equatable, Sendable {
    var tracks: [Track] = [] {
        didSet {
            updateDuration()
        }
    }

    var currentTime: CMTime = .zero
    var duration: CMTime = .zero

    init(tracks: [Track] = []) {
        self.tracks = tracks
        duration = Self.calculateDuration(from: tracks)
    }

    // MARK: - Computed Properties

    var trackCount: Int {
        tracks.count
    }

    /// Whether the timeline is empty (no tracks or empty tracks)
    var isEmpty: Bool {
        tracks.allSatisfy { $0.clips.isEmpty }
    }

    // MARK: - Mutations

    /// Recalculate total timeline duration (max of all tracks)
    mutating func updateDuration() {
        duration = Self.calculateDuration(from: tracks)
    }

    mutating func addTrack(_ track: Track) {
        tracks.append(track)
        updateDuration()
    }

    // MARK: - Private Helpers

    /// The latest clip end on any track, so gaps between clips count toward the duration.
    private static func calculateDuration(from tracks: [Track]) -> CMTime {
        let trackEndTimes = tracks.map { track in
            track.clips.reduce(CMTime.zero) { maxEnd, clip in
                let clipEnd = CMTimeAdd(clip.startTime, clip.effectiveDuration)
                return max(maxEnd, clipEnd)
            }
        }
        return trackEndTimes.max() ?? .zero
    }

    // MARK: - Codable

    enum CodingKeys: String, CodingKey {
        case tracks, clips, currentTime, duration
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)

        // Older projects stored a flat 'clips' array instead of tracks.
        if let decodedTracks = try? container.decode([Track].self, forKey: .tracks) {
            tracks = decodedTracks
        } else if let legacyClips = try? container.decode([VideoClip].self, forKey: .clips) {
            let mainTrack = Track(name: "Main Video", type: .video, clips: legacyClips, zIndex: 0)
            tracks = [mainTrack]
        } else {
            tracks = []
        }

        // Decode CMTime as seconds
        let currentSeconds = try container.decode(Double.self, forKey: .currentTime)
        currentTime = CMTime(seconds: currentSeconds, preferredTimescale: 600)

        duration = Self.calculateDuration(from: tracks)
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(tracks, forKey: .tracks)
        try container.encode(currentTime.seconds, forKey: .currentTime)
        try container.encode(duration.seconds, forKey: .duration)
    }
}

// MARK: - Array Extension

extension Array {
    subscript(safe index: Int) -> Element? {
        indices.contains(index) ? self[index] : nil
    }

    mutating func remove(atOffsets offsets: IndexSet) {
        self = enumerated().filter { !offsets.contains($0.offset) }.map(\.element)
    }
}
