//
//  SaneAudioEnhancementService.swift
//  SaneVideo
//
//  Created by SaneVideo Refactor
//

import AVFoundation
import Foundation

// MARK: - Audio Enhancement (Studio Sound)

/// Audio enhancement service
@MainActor
final class SaneAudioEnhancementService {

    init() {}

    enum EnhancementError: Error, @unchecked Sendable {
        case fileNotFound
        case processingFailed(String)
        case exportFailed
    }

    /// Wrapper to safely transfer AVAudioUnit across actor boundaries
    /// Swift 6 requires explicit Sendable conformance for cross-actor transfers
    private struct SendableAudioUnit: @unchecked Sendable {
        let unit: AVAudioUnit?
    }

    /// Enhances audio from a video/audio file and saves to a new location
    /// - Returns: URL of the enhanced audio file (.m4a)
    func enhanceAudio(from sourceURL: URL, onProgress: (@Sendable (Double) -> Void)? = nil) async throws -> URL {
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

        // Get voice isolation unit if already ready (don't wait - it can hang on some macOS versions)
        let isolationService = ServiceContainer.shared.voiceIsolationService
        let isolationUnit: AVAudioUnit?
        if isolationService.isReady {
            isolationUnit = isolationService.getAudioUnit()
            if isolationUnit != nil {
                AppLogger.recording.info("🎙️ AudioEnhancement: Using pre-initialized Isolation Unit")
                isolationService.setIntensity(1.0)
            } else {
                AppLogger.recording.warning("⚠️ AudioEnhancement: Isolation marked ready but unit is nil")
            }
        } else {
            // Don't wait for isolation - it can hang indefinitely on macOS 15+
            AppLogger.recording.warning("⚠️ AudioEnhancement: Voice isolation not ready, proceeding without it")
            isolationUnit = nil
        }

        // Run heavy audio processing on background thread to avoid UI freeze
        // Wrap AVAudioUnit in Sendable wrapper for safe cross-actor transfer
        let wrappedUnit = SendableAudioUnit(unit: isolationUnit)
        let result = try await Task.detached(priority: .userInitiated) { [sourceURL, wrappedUnit, onProgress] in
            try await Self.processAudioInBackground(
                sourceURL: sourceURL,
                isolationUnit: wrappedUnit.unit,
                onProgress: onProgress
            )
        }.value

        AppLogger.recording.info("🎙️ AudioEnhancement: Enhanced audio saved to: \(result.path)")
        return result
    }

    /// Heavy audio processing - runs on background thread
    private nonisolated static func processAudioInBackground(
        sourceURL: URL,
        isolationUnit: AVAudioUnit?,
        onProgress: (@Sendable (Double) -> Void)?
    ) async throws -> URL {
        // 1. Setup paths
        let fileManager = FileManager.default
        let folder = fileManager.temporaryDirectory.appendingPathComponent("EnhancedAudio", isDirectory: true)
        // CRITICAL FIX: Properly handle directory creation errors
        do {
            try fileManager.createDirectory(at: folder, withIntermediateDirectories: true)
        } catch {
            AppLogger.recording.error("🎙️ AudioEnhancement: Failed to create temp directory: \(error)")
            throw EnhancementError.processingFailed("Failed to create temporary directory: \(error.localizedDescription)")
        }

        let filename = sourceURL.deletingPathExtension().lastPathComponent + "_enhanced_\(UUID().uuidString).m4a"
        let outputURL = folder.appendingPathComponent(filename)

        // CRITICAL FIX: Check for cancellation before starting heavy work
        if Task.isCancelled {
            throw CancellationError()
        }

        // 2. Load Source File
        let engine = AVAudioEngine()
        let player = AVAudioPlayerNode()
        engine.attach(player)

        // 3. Create Effects

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

        // B. Voice Isolation - SKIP for offline rendering
        // CRITICAL FIX (2025-12-31): AUSoundIsolation does NOT support offline/manual rendering mode.
        // It's designed for real-time audio processing only. Using it in offline mode causes
        // scheduleSegment() to hang indefinitely on macOS 15+.
        // Voice isolation is applied during real-time playback, not during export.
        if isolationUnit != nil {
            AppLogger.recording.info("🎙️ AudioEnhancement: Skipping voice isolation (not compatible with offline rendering)")
        }

        AppLogger.recording.debug("🎙️ AudioEnhancement: Creating dynamics processor...")

        // C. Dynamics Processor (Legacy/Cleanup)
        let dynamics = AVAudioUnitEffect(audioComponentDescription: AudioComponentDescription(
            componentType: kAudioUnitType_Effect,
            componentSubType: kAudioUnitSubType_DynamicsProcessor,
            componentManufacturer: kAudioUnitManufacturer_Apple,
            componentFlags: 0,
            componentFlagsMask: 0
        ))
        engine.attach(dynamics)

        AppLogger.recording.debug("🎙️ AudioEnhancement: Loading source audio file...")

        // 5. Connect Nodes
        // Player -> EQ -> [VoiceIsolation if available] -> Dynamics -> MainMixer

        // CRITICAL FIX: Check for cancellation before loading file
        if Task.isCancelled {
            throw CancellationError()
        }

        let file = try AVAudioFile(forReading: sourceURL)
        AppLogger.recording.debug("🎙️ AudioEnhancement: Audio file loaded, connecting nodes...")

        // Connect: player -> eq -> dynamics (no voice isolation in offline mode)
        // Voice isolation is only for real-time playback, not offline rendering
        engine.connect(player, to: eq, format: file.processingFormat)
        engine.connect(eq, to: dynamics, format: file.processingFormat)

        engine.connect(dynamics, to: engine.mainMixerNode, format: file.processingFormat)

        // 6. Configure Offline Rendering
        let maxFrames: AVAudioFrameCount = 4096
        AppLogger.recording.debug("🎙️ AudioEnhancement: Enabling manual rendering mode...")
        try engine.enableManualRenderingMode(.offline, format: file.processingFormat, maximumFrameCount: maxFrames)
        AppLogger.recording.debug("🎙️ AudioEnhancement: Manual rendering mode enabled")

        // CRITICAL FIX: For manual rendering mode, we need to start the engine FIRST
        // Then schedule the file segment (not the whole file) for offline rendering
        // scheduleFile can hang in manual rendering mode if called before engine.start()
        AppLogger.recording.debug("🎙️ AudioEnhancement: Starting engine for manual rendering...")

        do {
            try engine.start()
            AppLogger.recording.debug("🎙️ AudioEnhancement: Engine started, scheduling audio segment...")
        } catch {
            AppLogger.recording.error("🎙️ AudioEnhancement: Failed to start engine: \(error)")
            throw error
        }

        // CRITICAL: Verify file is valid before scheduling
        guard file.length > 0 else {
            throw EnhancementError.processingFailed("Audio file has zero length")
        }

        // CRITICAL FIX (2025-12-31): Use completion-handler version for offline rendering
        // The async version (await scheduleSegment) waits for playback completion, which never
        // happens in manual rendering mode, causing an infinite hang.
        // Use completionHandler: nil to schedule immediately without waiting.
        AppLogger.recording.debug("🎙️ AudioEnhancement: File length: \(file.length) frames, format: \(file.processingFormat)")
        player.scheduleSegment(file, startingFrame: 0, frameCount: AVAudioFrameCount(file.length), at: nil, completionHandler: nil)
        AppLogger.recording.debug("🎙️ AudioEnhancement: Audio segment scheduled")

        // CRITICAL FIX: Use defer to ensure engine is ALWAYS stopped and cleaned up
        // This ensures cleanup happens even if render loop throws an error
        defer {
            AppLogger.recording.debug("🎙️ AudioEnhancement: Cleaning up engine...")
            player.stop()
            engine.stop()
            // Detach nodes (voice isolation is not used in offline rendering)
            engine.detach(player)
            engine.detach(eq)
            engine.detach(dynamics)
            AppLogger.recording.debug("🎙️ AudioEnhancement: Engine cleanup complete")
        }

        // Engine already started above, just start playback
        AppLogger.recording.debug("🎙️ AudioEnhancement: Starting playback for manual rendering...")
        player.play()
        AppLogger.recording.debug("🎙️ AudioEnhancement: Playback started")

        // 7. Render Loop
        // Output format: M4A AAC
        //
        // CRITICAL A/V SYNC:
        // Preserve the *source sample rate* to keep the enhanced file duration aligned with the original asset.
        // If we write 44.1kHz AAC from a 48kHz source without carefully mapping frames↔time,
        // the enhanced audio can end up with a slightly different duration, which causes sync drift
        // when the timeline is defined in the original video timebase.
        let outputSampleRate = file.processingFormat.sampleRate
        let outputChannels = Int(file.processingFormat.channelCount)

        let settings: [String: Any] = [
            AVFormatIDKey: kAudioFormatMPEG4AAC,
            AVSampleRateKey: outputSampleRate,
            AVNumberOfChannelsKey: max(1, outputChannels),
            AVEncoderBitRateKey: 192000
        ]

        AppLogger.recording.debug("🎙️ AudioEnhancement: Creating output file...")
        let outputFile = try AVAudioFile(forWriting: outputURL, settings: settings)
        AppLogger.recording.debug("🎙️ AudioEnhancement: Output file created")

        // Helper buffer for rendering
        AppLogger.recording.debug("🎙️ AudioEnhancement: Creating render buffer...")
        guard let renderBuffer = AVAudioPCMBuffer(pcmFormat: engine.manualRenderingFormat, frameCapacity: maxFrames) else {
            throw EnhancementError.processingFailed("Could not create render buffer")
        }
        AppLogger.recording.debug("🎙️ AudioEnhancement: Render buffer created")

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
                AppLogger.recording.error("🎙️ AudioEnhancement: Render failed: \(status.rawValue)")
                throw EnhancementError.processingFailed("Render status: \(status.rawValue)")
            }
        }

        // Render loop completed successfully
        // Defer block will handle cleanup (stop engine and detach nodes)

        AppLogger.recording.info("🎙️ AudioEnhancement: Enhanced audio saved to: \(outputURL.path)")
        return outputURL
    }
}
