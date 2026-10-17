import AVFoundation
import Foundation

/// Real-time audio processor that applies effects during playback
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
    
    private var currentClipSettings: ClipAudioSettings?
    
    private var videoPlayer: AVPlayer?
    
    // MARK: - Types
    
    struct ClipAudioSettings {
        let isVoiceIsolationEnabled: Bool
        let volume: Float
        let isGatingEnabled: Bool
    }
    
    // MARK: - Public Interface
    
    func setupForPlayerItem(_ item: AVPlayerItem, clip: VideoClip, videoPlayer: AVPlayer) async throws {
        cleanup()
        
        playerItem = item
        self.videoPlayer = videoPlayer
        currentClipSettings = ClipAudioSettings(
            isVoiceIsolationEnabled: clip.isVoiceIsolationEnabled,
            volume: clip.volume,
            isGatingEnabled: clip.isGatingEnabled
        )
        
        let audioURL = clip.enhancedAudioURL ?? clip.url
        let file = try AVAudioFile(forReading: audioURL)
        self.audioFile = file
        let audioFormat = file.processingFormat
        
        let newEngine = AVAudioEngine()
        let newPlayerNode = AVAudioPlayerNode()
        
        newEngine.attach(newPlayerNode)
        self.playerNode = newPlayerNode
        
        try await setupEffects(for: clip, engine: newEngine, format: audioFormat)
        
        connectAudioGraph(engine: newEngine, playerNode: newPlayerNode, format: audioFormat)
        
        self.engine = newEngine
        
        do {
            try newEngine.start()

            // Mute AVPlayer; audio plays through the engine instead.
            videoPlayer.volume = 0.0

            // Use the completion-handler form: the async form waits for playback to finish, not for scheduling.
            newPlayerNode.scheduleFile(file, at: nil, completionHandler: nil)

            syncWithVideoPlayer()
            
            AppLogger.audio.info("Real-time audio processor setup complete for clip \(clip.id)")
        } catch {
            newEngine.stop()
            throw error
        }
    }
    
    private func syncWithVideoPlayer() {
        guard let videoPlayer = videoPlayer, let playerNode = playerNode, let audioFile = audioFile else { return }

        let videoTime = videoPlayer.currentTime()

        let sampleRate = audioFile.processingFormat.sampleRate
        let framePosition = AVAudioFramePosition(videoTime.seconds * sampleRate)

        let remainingFrames = max(0, AVAudioFrameCount(audioFile.length - framePosition))
        if remainingFrames > 0 {
            // Use the completion-handler form: the async form waits for playback to finish, not for scheduling.
            playerNode.scheduleSegment(audioFile, startingFrame: framePosition, frameCount: remainingFrames, at: nil, completionHandler: nil)

            if videoPlayer.rate != 0 {
                playerNode.play()
            }
        }
    }
    
    func play() {
        playerNode?.play()
    }
    
    func pause() {
        playerNode?.pause()
    }
    
    func seek(to time: CMTime) {
        guard let playerNode = playerNode, let audioFile = audioFile, let videoPlayer = videoPlayer else { return }

        playerNode.stop()

        let sampleRate = audioFile.processingFormat.sampleRate
        let framePosition = AVAudioFramePosition(time.seconds * sampleRate)
        // Clamp before converting to unsigned; a negative value would crash.
        let remainingFrames = AVAudioFrameCount(max(0, audioFile.length - framePosition))

        // Use the completion-handler form: the async form waits for playback to finish, not for scheduling.
        playerNode.scheduleSegment(audioFile, startingFrame: framePosition, frameCount: remainingFrames, at: nil, completionHandler: nil)

        if videoPlayer.rate != 0 {
            playerNode.play()
        }
    }
    
    func updateEffects(for clip: VideoClip) async throws {
        let newSettings = ClipAudioSettings(
            isVoiceIsolationEnabled: clip.isVoiceIsolationEnabled,
            volume: clip.volume,
            isGatingEnabled: clip.isGatingEnabled
        )
        
        guard newSettings != currentClipSettings else { return }
        
        currentClipSettings = newSettings
        
        guard let engine = engine else {
            // Not set up yet - will be set up on next load
            return
        }
        
        try await updateEffectStates(for: clip, engine: engine)
        
        AppLogger.audio.debug("Real-time effects updated instantly for clip \(clip.id)")
    }
    
    func cleanup() {
        // Detach nodes before stopping engine to prevent memory leaks
        if let engine = engine {
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
        
        if let player = videoPlayer {
            player.volume = 1.0
        }
    }
    
    // MARK: - Private Helpers
    
    private func setupEffects(for clip: VideoClip, engine: AVAudioEngine, format: AVAudioFormat) async throws {
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
        
        engine.mainMixerNode.volume = currentClipSettings?.volume ?? 1.0
    }
    
    private func updateEffectStates(for clip: VideoClip, engine: AVAudioEngine) async throws {
        if clip.isVoiceIsolationEnabled, isolationUnit == nil {
            let isolationService = ServiceContainer.shared.voiceIsolationService
            await isolationService.prepareIsolationUnit()
            
            if let unit = isolationService.getAudioUnit() {
                isolationService.setIntensity(1.0)
                engine.attach(unit)
                self.isolationUnit = unit
                
                reconnectAudioGraph(engine: engine)
            }
        } else if !clip.isVoiceIsolationEnabled, let unit = isolationUnit {
            engine.detach(unit)
            isolationUnit = nil
            
            reconnectAudioGraph(engine: engine)
        }
        
        let volume = clip.isMuted ? 0.0 : clip.volume
        engine.mainMixerNode.volume = volume
        
        currentClipSettings = ClipAudioSettings(
            isVoiceIsolationEnabled: clip.isVoiceIsolationEnabled,
            volume: volume,
            isGatingEnabled: clip.isGatingEnabled
        )
    }
    
    private func reconnectAudioGraph(engine: AVAudioEngine) {
        guard let eq = eqUnit, let dynamics = dynamicsUnit, let playerNode = playerNode else { return }
        
        engine.disconnectNodeInput(engine.mainMixerNode)
        engine.disconnectNodeInput(dynamics)
        if let isolation = isolationUnit {
            engine.disconnectNodeInput(isolation)
            engine.disconnectNodeInput(eq)
        } else {
            engine.disconnectNodeInput(eq)
        }
        
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
        
        engine.mainMixerNode.volume = currentClipSettings?.volume ?? 1.0
    }
}

extension RealTimeAudioProcessor.ClipAudioSettings: Equatable {}
