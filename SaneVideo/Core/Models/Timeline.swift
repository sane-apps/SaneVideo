//
//  Timeline.swift
//  SaneVideo
//
//  Domain model representing a video timeline with clips
//  Optimized for Apple Silicon M1+ with value semantics

import AVFoundation
import Foundation

/// Timeline containing video clips and playback state
/// Note: This is a value type (struct) for better performance and memory safety on Apple Silicon
/// Sendable for safe cross-actor usage (Swift 6 compliance)
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

    /// Total number of tracks
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

    /// Add a track
    mutating func addTrack(_ track: Track) {
        tracks.append(track)
        // Sort by zIndex if needed, or just append
        updateDuration()
    }

    // MARK: - Private Helpers

    /// Calculate total duration from tracks (max end time of any clip on any track)
    private static func calculateDuration(from tracks: [Track]) -> CMTime {
        // Simplified: Sum of clips in each track (assuming sequential for now per track)
        // In a real NLE, clips on a track might have gaps.
        // For Phase 1, we assume each track is a sequence of clips (magnetic-ish) or we sum them.
        // Let's assume magnetic per track for now (previous behavior).
        let trackDurations = tracks.map { track in
            track.clips.reduce(CMTime.zero) { $0 + $1.effectiveDuration }
        }
        return trackDurations.max() ?? .zero
    }

    // MARK: - Codable

    enum CodingKeys: String, CodingKey {
        case tracks, clips, currentTime, duration
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)

        // Migration: Check for 'tracks' first, then fallback to 'clips'
        if let decodedTracks = try? container.decode([Track].self, forKey: .tracks) {
            tracks = decodedTracks
        } else if let legacyClips = try? container.decode([VideoClip].self, forKey: .clips) {
            // Migrate legacy clips to a default Main Track
            let mainTrack = Track(name: "Main Video", type: .video, clips: legacyClips, zIndex: 0)
            tracks = [mainTrack]
        } else {
            tracks = []
        }

        // Decode CMTime as seconds
        let currentSeconds = try container.decode(Double.self, forKey: .currentTime)
        currentTime = CMTime(seconds: currentSeconds, preferredTimescale: 600)

        // Recalculate duration from loaded tracks/clips to be safe
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
