import Foundation

/// @mockable
protocol WaveformServiceProtocol: Actor {
    /// Get waveform samples for a clip (cached or generated)
    func waveform(for clip: VideoClip) async -> [Float]?

    func cancelLoad(for clip: VideoClip)

    func clearCache()
}
