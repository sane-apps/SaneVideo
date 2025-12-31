//
//  RealTimeAudioProcessor.swift
//  SaneVideo
//
//  Real-time audio processing for instant effect preview during playback
//  Uses AVAudioEngine to process audio in real-time, just like Apple Photos
//  Allows instant toggling of all audio effects without pre-rendering
//

import AVFoundation
import Foundation

/// Real-time audio processor that applies effects during playback
/// Taps AVPlayer audio and processes it through effects in real-time
@MainActor
final class RealTimeAudioProcessor: RealTimeAudioProcessorProtocol {
    
    // MARK: - Properties
    
    private var engine: AVAudioEngine?
    private var playerNode: AVAudioPlayerNode?
    private var playerItem: AVPlayerItem?
    private var audioFile: AVAudioFile?
    private var isolationUnit: AVAudioUnit?
    private var eqUnit: AVAudioUnitEQ?
    private var dynamicsUnit: AVAudioUnitEffect?
    
    // Current clip settings
    private var currentClipSettings: ClipAudioSettings?
    
    // Sync with video player
    private var videoPlayer: AVPlayer?
    
    // MARK: - Types
    
    struct ClipAudioSettings {
        let isVoiceIsolationEnabled: Bool
        let volume: Float
        let isGatingEnabled: Bool
    }
    
    // MARK: - Public Interface
    
    /// Setup real-time audio processing for a player item
    /// This processes audio in real-time, allowing instant effect toggling
    func setupForPlayerItem(_ item: AVPlayerItem, clip: VideoClip, videoPlayer: AVPlayer) async throws {
        cleanup()
        
        playerItem = item
        self.videoPlayer = videoPlayer
        currentClipSettings = ClipAudioSettings(
            isVoiceIsolationEnabled: clip.isVoiceIsolationEnabled,
            volume: clip.volume,
            isGatingEnabled: clip.isGatingEnabled
        )
        
        // Load audio file for playback through engine
        let audioURL = clip.enhancedAudioURL ?? clip.url
        let file = try AVAudioFile(forReading: audioURL)
        self.audioFile = file
        let audioFormat = file.processingFormat
        
        // Create engine and player node
        let newEngine = AVAudioEngine()
        let newPlayerNode = AVAudioPlayerNode()
        
        newEngine.attach(newPlayerNode)
        self.playerNode = newPlayerNode
        
        // Setup effects based on clip settings
        try await setupEffects(for: clip, engine: newEngine, format: audioFormat)
        
        // Connect audio graph: PlayerNode -> Effects -> MainMixer
        connectAudioGraph(engine: newEngine, playerNode: newPlayerNode, format: audioFormat)
        
        self.engine = newEngine
        
        // CRITICAL FIX: Use defer to ensure engine is stopped on error
        do {
            // Start engine
            try newEngine.start()
            
            // Mute AVPlayer audio (we'll play through engine instead)
            videoPlayer.volume = 0.0
            
            // Schedule and play audio file
            await newPlayerNode.scheduleFile(file, at: nil)
            
            // Sync with video player
            syncWithVideoPlayer()
            
            AppLogger.audio.info("Real-time audio processor setup complete for clip \(clip.id)")
        } catch {
            // CRITICAL FIX: Stop engine on error to prevent resource leak
            newEngine.stop()
            throw error
        }
    }
    
    /// Sync audio playback with video player
    private func syncWithVideoPlayer() {
        guard let videoPlayer = videoPlayer, let playerNode = playerNode, let audioFile = audioFile else { return }
        
        // Get current video time
        let videoTime = videoPlayer.currentTime()
        
        // Calculate frame position to match video
        let sampleRate = audioFile.processingFormat.sampleRate
        let framePosition = AVAudioFramePosition(videoTime.seconds * sampleRate)
        
        // Schedule from current video position
        let remainingFrames = max(0, AVAudioFrameCount(audioFile.length - framePosition))
        if remainingFrames > 0 {
            Task {
                await playerNode.scheduleSegment(audioFile, startingFrame: framePosition, frameCount: remainingFrames, at: nil)
                
                // Start if video is playing
                if videoPlayer.rate != 0 {
                    playerNode.play()
                }
            }
        }
    }
    
    /// Play audio (synced with video)
    func play() {
        playerNode?.play()
    }
    
    /// Pause audio
    func pause() {
        playerNode?.pause()
    }
    
    /// Seek audio to match video
    func seek(to time: CMTime) {
        guard let playerNode = playerNode, let audioFile = audioFile, let videoPlayer = videoPlayer else { return }
        
        // Stop current playback
        playerNode.stop()
        
        // Calculate frame position
        let sampleRate = audioFile.processingFormat.sampleRate
        let framePosition = AVAudioFramePosition(time.seconds * sampleRate)
        // FIX: max() BEFORE converting to UInt32 to prevent negative-to-unsigned crash
        let remainingFrames = AVAudioFrameCount(max(0, audioFile.length - framePosition))
        
        // Schedule from new position
        Task {
            await playerNode.scheduleSegment(audioFile, startingFrame: framePosition, frameCount: remainingFrames, at: nil)
            
            // Resume if video is playing
            if videoPlayer.rate != 0 {
                playerNode.play()
            }
        }
    }
    
    /// Update effects in real-time (instant toggle)
    func updateEffects(for clip: VideoClip) async throws {
        let newSettings = ClipAudioSettings(
            isVoiceIsolationEnabled: clip.isVoiceIsolationEnabled,
            volume: clip.volume,
            isGatingEnabled: clip.isGatingEnabled
        )
        
        // Check if settings changed
        guard newSettings != currentClipSettings else { return }
        
        currentClipSettings = newSettings
        
        guard let engine = engine else {
            // Not set up yet - will be set up on next load
            return
        }
        
        // Update effects in real-time
        try await updateEffectStates(for: clip, engine: engine)
        
        AppLogger.audio.debug("Real-time effects updated instantly for clip \(clip.id)")
    }
    
    /// Stop and cleanup
    func cleanup() {
        // CRITICAL FIX: Detach nodes before stopping engine to prevent memory leaks
        if let engine = engine {
            // Detach all nodes before stopping
            if let playerNode = playerNode {
                playerNode.stop()
                engine.detach(playerNode)
            }
            if let isolationUnit = isolationUnit {
                engine.detach(isolationUnit)
            }
            if let eqUnit = eqUnit {
                engine.detach(eqUnit)
            }
            if let dynamicsUnit = dynamicsUnit {
                engine.detach(dynamicsUnit)
            }
            engine.stop()
        }
        
        engine = nil
        playerNode = nil
        audioFile = nil
        isolationUnit = nil
        eqUnit = nil
        dynamicsUnit = nil
        playerItem = nil
        videoPlayer = nil
        currentClipSettings = nil
        
        // Restore video player volume (if still exists)
        if let player = videoPlayer {
            player.volume = 1.0
        }
    }
    
    // MARK: - Private Helpers
    
    private func setupEffects(for clip: VideoClip, engine: AVAudioEngine, format: AVAudioFormat) async throws {
        // Voice Isolation
        if clip.isVoiceIsolationEnabled {
            let isolationService = ServiceContainer.shared.voiceIsolationService
            await isolationService.prepareIsolationUnit()
            
            if let unit = isolationService.getAudioUnit() {
                isolationService.setIntensity(1.0)
                engine.attach(unit)
                self.isolationUnit = unit
            }
        }
        
        // EQ (always attached for vocal presence)
        let eq = AVAudioUnitEQ(numberOfBands: 3)
        let bands = eq.bands
        
        // High Pass (Cut Rumble)
        bands[0].filterType = .highPass
        bands[0].frequency = 80.0
        bands[0].bypass = false
        
        // Presence Boost
        bands[1].filterType = .parametric
        bands[1].frequency = 3000.0
        bands[1].bandwidth = 1.0
        bands[1].gain = 4.0
        bands[1].bypass = false
        
        // Low Cut
        bands[2].filterType = .parametric
        bands[2].frequency = 300.0
        bands[2].bandwidth = 1.0
        bands[2].gain = -3.0
        bands[2].bypass = false
        
        engine.attach(eq)
        self.eqUnit = eq
        
        // Dynamics Processor
        let dynamics = AVAudioUnitEffect(audioComponentDescription: AudioComponentDescription(
            componentType: kAudioUnitType_Effect,
            componentSubType: kAudioUnitSubType_DynamicsProcessor,
            componentManufacturer: kAudioUnitManufacturer_Apple,
            componentFlags: 0,
            componentFlagsMask: 0
        ))
        engine.attach(dynamics)
        self.dynamicsUnit = dynamics
    }
    
    private func connectAudioGraph(engine: AVAudioEngine, playerNode: AVAudioPlayerNode, format: AVAudioFormat) {
        guard let eq = eqUnit, let dynamics = dynamicsUnit else { return }
        
        // Connect: PlayerNode -> EQ -> [Isolation if enabled] -> Dynamics -> MainMixer
        engine.connect(playerNode, to: eq, format: format)
        
        if let isolation = isolationUnit {
            engine.connect(eq, to: isolation, format: format)
            engine.connect(isolation, to: dynamics, format: format)
        } else {
            engine.connect(eq, to: dynamics, format: format)
        }
        
        engine.connect(dynamics, to: engine.mainMixerNode, format: format)
        
        // Set volume
        engine.mainMixerNode.volume = currentClipSettings?.volume ?? 1.0
    }
    
    private func updateEffectStates(for clip: VideoClip, engine: AVAudioEngine) async throws {
        // Update voice isolation in real-time
        if clip.isVoiceIsolationEnabled, isolationUnit == nil {
            // Need to add isolation
            let isolationService = ServiceContainer.shared.voiceIsolationService
            await isolationService.prepareIsolationUnit()
            
            if let unit = isolationService.getAudioUnit() {
                isolationService.setIntensity(1.0)
                engine.attach(unit)
                self.isolationUnit = unit
                
                // Reconnect graph with isolation
                reconnectAudioGraph(engine: engine)
            }
        } else if !clip.isVoiceIsolationEnabled, let unit = isolationUnit {
            // Remove isolation
            engine.detach(unit)
            isolationUnit = nil
            
            // Reconnect graph without isolation
            reconnectAudioGraph(engine: engine)
        }
        
        // Update volume (via main mixer) - INSTANT
        let volume = clip.isMuted ? 0.0 : clip.volume
        engine.mainMixerNode.volume = volume
        
        // Update current settings
        currentClipSettings = ClipAudioSettings(
            isVoiceIsolationEnabled: clip.isVoiceIsolationEnabled,
            volume: volume,
            isGatingEnabled: clip.isGatingEnabled
        )
    }
    
    private func reconnectAudioGraph(engine: AVAudioEngine) {
        guard let eq = eqUnit, let dynamics = dynamicsUnit, let playerNode = playerNode else { return }
        
        // Disconnect all
        engine.disconnectNodeInput(engine.mainMixerNode)
        engine.disconnectNodeInput(dynamics)
        if let isolation = isolationUnit {
            engine.disconnectNodeInput(isolation)
            engine.disconnectNodeInput(eq)
        } else {
            engine.disconnectNodeInput(eq)
        }
        
        // Get format from audio file
        guard let format = audioFile?.processingFormat else { return }
        
        // Reconnect: PlayerNode -> EQ -> [Isolation if enabled] -> Dynamics -> MainMixer
        engine.connect(playerNode, to: eq, format: format)
        
        if let isolation = isolationUnit {
            engine.connect(eq, to: isolation, format: format)
            engine.connect(isolation, to: dynamics, format: format)
        } else {
            engine.connect(eq, to: dynamics, format: format)
        }
        
        engine.connect(dynamics, to: engine.mainMixerNode, format: format)
        
        // Update volume
        engine.mainMixerNode.volume = currentClipSettings?.volume ?? 1.0
    }
}

extension RealTimeAudioProcessor.ClipAudioSettings: Equatable {}
