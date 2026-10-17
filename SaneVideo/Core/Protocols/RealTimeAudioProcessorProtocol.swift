import AVFoundation
import Foundation

/// @mockable
@MainActor
protocol RealTimeAudioProcessorProtocol: AnyObject, Sendable {
    func setupForPlayerItem(_ item: AVPlayerItem, clip: VideoClip, videoPlayer: AVPlayer) async throws

    /// Play audio (synced with video)
    func play()

    func pause()

    /// Seek audio to match video
    func seek(to time: CMTime)

    /// Update effects in real-time (instant toggle)
    func updateEffects(for clip: VideoClip) async throws

    func cleanup()
}
