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
    func enhanceAudio(from sourceURL: URL, onProgress: ((Double) -> Void)? = nil) async throws -> URL {
        AppLogger.recording.info("🎙️ AudioEnhancement: Starting for \(sourceURL.lastPathComponent)")

        // 0. Validate file size before loading into memory
        if !AppConstants.MagicFeatures.isFileSizeValid(sourceURL) {
            let sizeBytes = AppConstants.MagicFeatures.fileSize(sourceURL) ?? 0
            let sizeMB = sizeBytes / (1024 * 1024)
            let limitMB = AppConstants.MagicFeatures.maxAudioFileSize / (1024 * 1024)
            AppLogger.recording.error("🎙️ AudioEnhancement: File too large (\(sizeMB)MB > \(limitMB)MB limit)")
            throw NSError(domain: "SaneAudioEnhancementService", code: -1,
                          userInfo: [NSLocalizedDescriptionKey: "Audio file too large for enhancement (\(sizeMB)MB exceeds \(limitMB)MB limit)"])
        }

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
        // Note: Voice isolation is OPTIONAL - it may timeout or fail on macOS 26
        let isolationService = ServiceContainer.shared.voiceIsolationService
        AppLogger.recording.info("🎙️ AudioEnhancement: Preparing Isolation Unit...")
        await isolationService.prepareIsolationUnit()
        
        let isolationUnit = isolationService.getAudioUnit()
        if let unit = isolationUnit {
            AppLogger.recording.info("🎙️ AudioEnhancement: Isolation Unit Ready")
            isolationService.setIntensity(1.0)
            engine.attach(unit)
        } else {
            AppLogger.recording.warning("⚠️ AudioEnhancement: Voice isolation unavailable, continuing without it")            
        }
        
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
        // Player -> EQ -> [VoiceIsolation if available] -> Dynamics -> MainMixer
        
        let file = try AVAudioFile(forReading: sourceURL)
        
        // Connect: player -> eq always
        engine.connect(player, to: eq, format: file.processingFormat)
        
        // Conditionally include voice isolation in the chain
        if let unit = isolationUnit {
            engine.connect(eq, to: unit, format: file.processingFormat)
            engine.connect(unit, to: dynamics, format: file.processingFormat)
        } else {
            // Skip voice isolation: EQ -> Dynamics directly
            engine.connect(eq, to: dynamics, format: file.processingFormat)
        }
        
        engine.connect(dynamics, to: engine.mainMixerNode, format: file.processingFormat)
        
        // 6. Configure Offline Rendering
        let maxFrames: AVAudioFrameCount = 4096
        try engine.enableManualRenderingMode(.offline, format: file.processingFormat, maximumFrameCount: maxFrames)
        
        // CRITICAL FIX: Use defer to ensure engine is stopped on error
        do {
            try engine.start()
            // Use async variant to avoid warning
            await player.scheduleFile(file, at: nil) // Fire and forget for offline render setup
            player.play()
        } catch {
            // CRITICAL FIX: Stop engine on error to prevent resource leak
            engine.stop()
            // Detach nodes before stopping
            engine.detach(player)
            engine.detach(eq)
            if let unit = isolationUnit {
                engine.detach(unit)
            }
            engine.detach(dynamics)
            throw error
        }
        
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
        
        AppLogger.recording.info("🎙️ AudioEnhancement: Starting Render Loop")
        var lastProgressUpdate = Date()
        let startTime = Date()
        let maxProcessingTime: TimeInterval = 600.0 // 10 minutes max
        
        while engine.manualRenderingSampleTime < file.length {
            // ROBUSTNESS: Check for timeout
            if Date().timeIntervalSince(startTime) > maxProcessingTime {
                throw EnhancementError.processingFailed("Audio enhancement timed out after 10 minutes")
            }
            
            // Check for cancellation
            if Task.isCancelled {
                throw CancellationError()
            }
            
            // Yield to main thread periodically to prevent blocking
            if engine.manualRenderingSampleTime % Int64(maxFrames * 10) == 0 {
                 await Task.yield()
                 // ROBUSTNESS: Update progress more frequently
                 let progress = Double(engine.manualRenderingSampleTime) / Double(file.length)
                 Task { @MainActor in onProgress?(progress) }
            }
            
            let remaining = file.length - engine.manualRenderingSampleTime
            let frameCount = min(maxFrames, AVAudioFrameCount(remaining))
            
            let status = try engine.renderOffline(frameCount, to: renderBuffer)
            
            if status == .success {
                try outputFile.write(from: renderBuffer)
                
                // Update Progress (Memoize to avoid flooding MainActor)
                if Date().timeIntervalSince(lastProgressUpdate) > 0.1 {
                    let progress = Double(engine.manualRenderingSampleTime) / Double(file.length)
                    Task { @MainActor in onProgress?(progress) }
                    lastProgressUpdate = Date()
                }
            } else {
                // If it fails, log and break
                AppLogger.recording.error("Render failed: \(status.rawValue)")
                throw EnhancementError.processingFailed("Render status: \(status.rawValue)")
            }
        }
        
        player.stop()
        engine.stop()
        
        // CRITICAL FIX: Detach nodes before stopping engine
        engine.detach(player)
        engine.detach(eq)
        if let unit = isolationUnit {
            engine.detach(unit)
        }
        engine.detach(dynamics)
        
        AppLogger.recording.info("🎙️ AudioEnhancement: Enhanced audio saved to: \(outputURL.path)")
        return outputURL
    }
}
