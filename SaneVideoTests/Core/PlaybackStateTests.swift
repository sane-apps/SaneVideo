import Testing
import AVFoundation
import Foundation
@testable import SaneVideo

@Suite("Playback State Tests")
@MainActor
struct PlaybackStateTests {
    
    // MARK: - Initial State Tests
    
    @Test("Initial state values")
    func initialState() {
        let playbackState = PlaybackState()
        #expect(!playbackState.isPlaying)
        #expect(playbackState.currentTime == .zero)
        #expect(playbackState.duration == .zero)
        #expect(playbackState.player == nil)
    }
    
    // MARK: - Play/Pause Tests
    
    @Test("Play behavior without player")
    func playWithNoPlayerDoesNotCrash() {
        let playbackState = PlaybackState()
        playbackState.play()
        playbackState.pause()
        playbackState.togglePlayPause()
        
        #expect(!playbackState.isPlaying)
    }
    
    @Test("Toggle play/pause without player")
    func togglePlayPauseWithNoPlayer() {
        let playbackState = PlaybackState()
        #expect(!playbackState.isPlaying)
        playbackState.togglePlayPause()
        #expect(!playbackState.isPlaying)
    }
    
    // MARK: - Seek Tests
    
    @Test("Seek behavior without player")
    func seekWithNoPlayerDoesNotCrash() {
        let playbackState = PlaybackState()
        let seekTime = CMTime(seconds: 5, preferredTimescale: 600)
        playbackState.seek(to: seekTime)
        #expect(playbackState.currentTime == seekTime)
    }
    
    @Test("Rewind behavior at start")
    func rewindFromZeroStaysAtZero() {
        let playbackState = PlaybackState()
        playbackState.currentTime = .zero
        playbackState.rewind(by: 5.0)
        #expect(playbackState.currentTime.seconds >= 0)
    }
    
    @Test("Forward behavior at end")
    func forwardDoesNotExceedDuration() {
        let playbackState = PlaybackState()
        playbackState.duration = CMTime(seconds: 10, preferredTimescale: 600)
        playbackState.currentTime = CMTime(seconds: 8, preferredTimescale: 600)
        playbackState.forward(by: 5.0)
        #expect(playbackState.currentTime.seconds <= 10.0)
    }
    
    // MARK: - Unload Tests
    
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
