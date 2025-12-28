//
//  RealTimeAudioProcessorProtocol.swift
//  SaneVideo
//
//  Protocol for real-time audio processing during playback
//

import AVFoundation
import Foundation

/// @mockable
@MainActor
protocol RealTimeAudioProcessorProtocol: AnyObject, Sendable {
    /// Setup real-time audio processing for a player item
    func setupForPlayerItem(_ item: AVPlayerItem, clip: VideoClip, videoPlayer: AVPlayer) async throws

    /// Play audio (synced with video)
    func play()

    /// Pause audio
    func pause()

    /// Seek audio to match video
    func seek(to time: CMTime)

    /// Update effects in real-time (instant toggle)
    func updateEffects(for clip: VideoClip) async throws

    /// Stop and cleanup
    func cleanup()
}
