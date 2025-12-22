//
//  SaneAudioEnhancementService.swift
//  SaneVideo
//
//  Created by SaneVideo Refactor
//

import AVFoundation
import Foundation

// MARK: - Audio Enhancement (Studio Sound)

@MainActor
final class SaneAudioEnhancementService {
    
    init() {}
    
    enum EnhancementError: Error {
        case fileNotFound
        case processingFailed(String)
        case exportFailed
    }
    
    /// Enhances audio from a video/audio file and saves to a new location
    /// - Returns: URL of the enhanced audio file (.m4a)
    func enhanceAudio(from sourceURL: URL) async throws -> URL {
        // 1. Setup paths
        let fileManager = FileManager.default
        let folder = fileManager.temporaryDirectory.appendingPathComponent("EnhancedAudio", isDirectory: true)
        try? fileManager.createDirectory(at: folder, withIntermediateDirectories: true)
        
        let filename = sourceURL.deletingPathExtension().lastPathComponent + "_enhanced_\(UUID().uuidString).m4a"
        let outputURL = folder.appendingPathComponent(filename)
        
        // 2. Load Source File
        let engine = AVAudioEngine()
        let player = AVAudioPlayerNode()
        engine.attach(player)
        
        // 4. Create Effects
        
        // A. EQ (Vocal Presence)
        let eq = AVAudioUnitEQ(numberOfBands: 3)
        let bands = eq.bands
        
        // High Pass (Cut Rumble)
        bands[0].filterType = .highPass
        bands[0].frequency = 80.0
        bands[0].bypass = false
        
        // Low Cut / Warmth control
        bands[1].filterType = .parametric
        bands[1].frequency = 300.0
        bands[1].bandwidth = 1.0
        bands[1].gain = -3.0 // Cut muddy freqs
        bands[1].bypass = false
        
        // Presence Boost
        bands[2].filterType = .parametric
        bands[2].frequency = 3000.0 // Vocal clarity
        bands[2].bandwidth = 1.0
        bands[2].gain = 4.0
        bands[2].bypass = false
        
        engine.attach(eq)
        
        // B. Voice Isolation (Modern macOS 13+ ML-based isolation)
        let isolationService = ServiceContainer.shared.voiceIsolationService
        await isolationService.prepareIsolationUnit()
        
        guard let isolationUnit = isolationService.getAudioUnit() else {
            throw EnhancementError.processingFailed("Failed to load AUSoundIsolation unit")
        }
        
        isolationService.setIntensity(1.0)
        engine.attach(isolationUnit)
        
        // C. Dynamics Processor (Legacy/Cleanup)
        let dynamics = AVAudioUnitEffect(audioComponentDescription: AudioComponentDescription(
            componentType: kAudioUnitType_Effect,
            componentSubType: kAudioUnitSubType_DynamicsProcessor,
            componentManufacturer: kAudioUnitManufacturer_Apple,
            componentFlags: 0,
            componentFlagsMask: 0
        ))
        engine.attach(dynamics)
        
        // 5. Connect Nodes
        // Player -> EQ -> VoiceIsolation -> Dynamics -> MainMixer
        
        let file = try AVAudioFile(forReading: sourceURL)
        // Connect
        engine.connect(player, to: eq, format: file.processingFormat)
        engine.connect(eq, to: isolationUnit, format: file.processingFormat)
        engine.connect(isolationUnit, to: dynamics, format: file.processingFormat)
        engine.connect(dynamics, to: engine.mainMixerNode, format: file.processingFormat)
        
        // 6. Configure Offline Rendering
        let maxFrames: AVAudioFrameCount = 4096
        try engine.enableManualRenderingMode(.offline, format: file.processingFormat, maximumFrameCount: maxFrames)
        
        try engine.start()
        // Use async variant to avoid warning
        await player.scheduleFile(file, at: nil) // Fire and forget for offline render setup
        player.play()
        
        // 7. Render Loop
        // Output format: M4A AAC
        let settings: [String: Any] = [
            AVFormatIDKey: kAudioFormatMPEG4AAC,
            AVSampleRateKey: 44100.0,
            AVNumberOfChannelsKey: 2,
            AVEncoderBitRateKey: 192000
        ]
        
        let outputFile = try AVAudioFile(forWriting: outputURL, settings: settings)
        
        // Helper buffer for rendering
        guard let renderBuffer = AVAudioPCMBuffer(pcmFormat: engine.manualRenderingFormat, frameCapacity: maxFrames) else {
            throw EnhancementError.processingFailed("Could not create render buffer")
        }
        
        while engine.manualRenderingSampleTime < file.length {
            await Task.yield() // Keep UI responsive during render loop
            let remaining = file.length - engine.manualRenderingSampleTime
            let frameCount = min(maxFrames, AVAudioFrameCount(remaining))
            
            let status = try engine.renderOffline(frameCount, to: renderBuffer)
            
            if status == .success {
                try outputFile.write(from: renderBuffer)
            } else {
                // If it fails, log and break
                print("Render failed: \(status.rawValue)")
                throw EnhancementError.processingFailed("Render status: \(status.rawValue)")
            }
        }
        
        player.stop()
        engine.stop()
        
        print("Enhanced audio saved to: \(outputURL.path)")
        return outputURL
    }
}
