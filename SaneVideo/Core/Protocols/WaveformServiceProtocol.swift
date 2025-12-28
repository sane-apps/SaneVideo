//
//  WaveformServiceProtocol.swift
//  SaneVideo
//
//  Protocol for waveform generation and caching
//

import Foundation

/// @mockable
protocol WaveformServiceProtocol: Actor {
    /// Get waveform samples for a clip (cached or generated)
    func waveform(for clip: VideoClip) async -> [Float]?

    /// Cancel waveform load for a clip
    func cancelLoad(for clip: VideoClip)

    /// Clear the waveform cache
    func clearCache()
}
