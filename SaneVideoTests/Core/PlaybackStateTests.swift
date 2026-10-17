import AVFoundation
import Foundation
@testable import SaneVideo
import Testing

@Suite("Playback State Tests")
@MainActor
struct PlaybackStateTests {
    @Test("Play/pause toggles are ignored when no player is loaded")
    func togglePlayPauseWithNoPlayer() {
        let playbackState = PlaybackState()
        playbackState.play()
        #expect(!playbackState.isPlaying)
        playbackState.togglePlayPause()
        #expect(!playbackState.isPlaying)
    }

    @Test("Seek without a player still moves the playhead")
    func seekWithNoPlayerMovesPlayhead() {
        let playbackState = PlaybackState()
        let seekTime = CMTime(seconds: 5, preferredTimescale: 600)
        playbackState.seek(to: seekTime)
        #expect(playbackState.currentTime == seekTime)
    }

    @Test("Rewind past the start clamps to zero")
    func rewindClampsAtZero() {
        let playbackState = PlaybackState()
        playbackState.duration = CMTime(seconds: 10, preferredTimescale: 600)
        playbackState.currentTime = CMTime(seconds: 2, preferredTimescale: 600)
        playbackState.rewind(by: 5.0)
        #expect(playbackState.currentTime.seconds == 0)
    }

    @Test("Forward past the end clamps to the duration")
    func forwardClampsAtDuration() {
        let playbackState = PlaybackState()
        playbackState.duration = CMTime(seconds: 10, preferredTimescale: 600)
        playbackState.currentTime = CMTime(seconds: 8, preferredTimescale: 600)
        playbackState.forward(by: 5.0)
        #expect(abs(playbackState.currentTime.seconds - 10.0) < 0.001)
    }

    @Test("Unload resets all states")
    func unloadResetsState() {
        let playbackState = PlaybackState()
        playbackState.isPlaying = true
        playbackState.currentTime = CMTime(seconds: 5, preferredTimescale: 600)
        playbackState.duration = CMTime(seconds: 10, preferredTimescale: 600)

        playbackState.unload()

        #expect(!playbackState.isPlaying)
        #expect(playbackState.currentTime == .zero)
        #expect(playbackState.duration == .zero)
        #expect(playbackState.player == nil)
    }
}
