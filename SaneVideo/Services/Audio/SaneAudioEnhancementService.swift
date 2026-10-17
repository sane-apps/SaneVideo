import AVFoundation
import Foundation

// MARK: - Audio Enhancement (Studio Sound)

@MainActor
final class SaneAudioEnhancementService {

    init() {}

    enum EnhancementError: Error, @unchecked Sendable {
        case fileNotFound
        case processingFailed(String)
        case exportFailed
    }

    /// Carries AVAudioUnit across actor boundaries; AVAudioUnit is not Sendable.
    private struct SendableAudioUnit: @unchecked Sendable {
        let unit: AVAudioUnit?
    }

    /// Enhances audio from a video/audio file and saves to a new location
    /// - Returns: URL of the enhanced audio file (.m4a)
    func enhanceAudio(from sourceURL: URL, onProgress: (@Sendable (Double) -> Void)? = nil) async throws -> URL {
        AppLogger.recording.info("🎙️ AudioEnhancement: Starting for \(sourceURL.lastPathComponent)")

        if !AppConstants.MagicFeatures.isFileSizeValid(sourceURL) {
            let sizeBytes = AppConstants.MagicFeatures.fileSize(sourceURL) ?? 0
            let sizeMB = sizeBytes / (1024 * 1024)
            let limitMB = AppConstants.MagicFeatures.maxAudioFileSize / (1024 * 1024)
            AppLogger.recording.error("🎙️ AudioEnhancement: File too large (\(sizeMB)MB > \(limitMB)MB limit)")
            throw NSError(domain: "SaneAudioEnhancementService", code: -1,
                          userInfo: [NSLocalizedDescriptionKey: "Audio file too large for enhancement (\(sizeMB)MB exceeds \(limitMB)MB limit)"])
        }

        // Use the isolation unit only if it is already ready; waiting can hang on some macOS versions.
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
            AppLogger.recording.warning("⚠️ AudioEnhancement: Voice isolation not ready, proceeding without it")
            isolationUnit = nil
        }

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

    private nonisolated static func processAudioInBackground(
        sourceURL: URL,
        isolationUnit: AVAudioUnit?,
        onProgress: (@Sendable (Double) -> Void)?
    ) async throws -> URL {
        let fileManager = FileManager.default
        let folder = fileManager.temporaryDirectory.appendingPathComponent("EnhancedAudio", isDirectory: true)
        do {
            try fileManager.createDirectory(at: folder, withIntermediateDirectories: true)
        } catch {
            AppLogger.recording.error("🎙️ AudioEnhancement: Failed to create temp directory: \(error)")
            throw EnhancementError.processingFailed("Failed to create temporary directory: \(error.localizedDescription)")
        }

        let filename = sourceURL.deletingPathExtension().lastPathComponent + "_enhanced_\(UUID().uuidString).m4a"
        let outputURL = folder.appendingPathComponent(filename)

        if Task.isCancelled {
            throw CancellationError()
        }

        let engine = AVAudioEngine()
        let player = AVAudioPlayerNode()
        engine.attach(player)

        // EQ (vocal presence)
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

        // AUSoundIsolation cannot render offline (scheduleSegment hangs on macOS 15+), so isolation applies only during real-time playback.
        if isolationUnit != nil {
            AppLogger.recording.info("🎙️ AudioEnhancement: Skipping voice isolation (not compatible with offline rendering)")
        }

        AppLogger.recording.debug("🎙️ AudioEnhancement: Creating dynamics processor...")

        let dynamics = AVAudioUnitEffect(audioComponentDescription: AudioComponentDescription(
            componentType: kAudioUnitType_Effect,
            componentSubType: kAudioUnitSubType_DynamicsProcessor,
            componentManufacturer: kAudioUnitManufacturer_Apple,
            componentFlags: 0,
            componentFlagsMask: 0
        ))
        engine.attach(dynamics)

        AppLogger.recording.debug("🎙️ AudioEnhancement: Loading source audio file...")

        if Task.isCancelled {
            throw CancellationError()
        }

        let file = try AVAudioFile(forReading: sourceURL)
        AppLogger.recording.debug("🎙️ AudioEnhancement: Audio file loaded, connecting nodes...")

        // player -> eq -> dynamics; no voice isolation offline.
        engine.connect(player, to: eq, format: file.processingFormat)
        engine.connect(eq, to: dynamics, format: file.processingFormat)

        engine.connect(dynamics, to: engine.mainMixerNode, format: file.processingFormat)

        let maxFrames: AVAudioFrameCount = 4096
        AppLogger.recording.debug("🎙️ AudioEnhancement: Enabling manual rendering mode...")
        try engine.enableManualRenderingMode(.offline, format: file.processingFormat, maximumFrameCount: maxFrames)
        AppLogger.recording.debug("🎙️ AudioEnhancement: Manual rendering mode enabled")

        // In manual rendering mode, start the engine before scheduling; scheduling first can hang.
        AppLogger.recording.debug("🎙️ AudioEnhancement: Starting engine for manual rendering...")

        do {
            try engine.start()
            AppLogger.recording.debug("🎙️ AudioEnhancement: Engine started, scheduling audio segment...")
        } catch {
            AppLogger.recording.error("🎙️ AudioEnhancement: Failed to start engine: \(error)")
            throw error
        }

        guard file.length > 0 else {
            throw EnhancementError.processingFailed("Audio file has zero length")
        }

        // Use the completion-handler form: the async form waits for playback to finish, which never happens in manual rendering mode.
        AppLogger.recording.debug("🎙️ AudioEnhancement: File length: \(file.length) frames, format: \(file.processingFormat)")
        player.scheduleSegment(file, startingFrame: 0, frameCount: AVAudioFrameCount(file.length), at: nil, completionHandler: nil)
        AppLogger.recording.debug("🎙️ AudioEnhancement: Audio segment scheduled")

        defer {
            AppLogger.recording.debug("🎙️ AudioEnhancement: Cleaning up engine...")
            player.stop()
            engine.stop()
            engine.detach(player)
            engine.detach(eq)
            engine.detach(dynamics)
            AppLogger.recording.debug("🎙️ AudioEnhancement: Engine cleanup complete")
        }

        AppLogger.recording.debug("🎙️ AudioEnhancement: Starting playback for manual rendering...")
        player.play()
        AppLogger.recording.debug("🎙️ AudioEnhancement: Playback started")

        // Keep the source sample rate so the enhanced file matches the original duration; writing 44.1 kHz from a 48 kHz source drifts out of sync with the original timeline.
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

        AppLogger.recording.debug("🎙️ AudioEnhancement: Creating render buffer...")
        guard let renderBuffer = AVAudioPCMBuffer(pcmFormat: engine.manualRenderingFormat, frameCapacity: maxFrames) else {
            throw EnhancementError.processingFailed("Could not create render buffer")
        }
        AppLogger.recording.debug("🎙️ AudioEnhancement: Render buffer created")

        AppLogger.recording.info("🎙️ AudioEnhancement: Starting Render Loop")
        var lastProgressUpdate = Date()
        let startTime = Date()
        let maxProcessingTime: TimeInterval = 600.0

        while engine.manualRenderingSampleTime < file.length {
            if Date().timeIntervalSince(startTime) > maxProcessingTime {
                throw EnhancementError.processingFailed("Audio enhancement timed out after 10 minutes")
            }

            if Task.isCancelled {
                throw CancellationError()
            }

            // Yield to main thread periodically to prevent blocking
            if engine.manualRenderingSampleTime % Int64(maxFrames * 10) == 0 {
                 await Task.yield()
                 let progress = Double(engine.manualRenderingSampleTime) / Double(file.length)
                 Task { @MainActor in onProgress?(progress) }
            }

            let remaining = file.length - engine.manualRenderingSampleTime
            let frameCount = min(maxFrames, AVAudioFrameCount(remaining))

            let status = try engine.renderOffline(frameCount, to: renderBuffer)

            if status == .success {
                try outputFile.write(from: renderBuffer)

                // Throttle progress updates to avoid flooding the main actor.
                if Date().timeIntervalSince(lastProgressUpdate) > 0.1 {
                    let progress = Double(engine.manualRenderingSampleTime) / Double(file.length)
                    Task { @MainActor in onProgress?(progress) }
                    lastProgressUpdate = Date()
                }
            } else {
                AppLogger.recording.error("🎙️ AudioEnhancement: Render failed: \(status.rawValue)")
                throw EnhancementError.processingFailed("Render status: \(status.rawValue)")
            }
        }

        AppLogger.recording.info("🎙️ AudioEnhancement: Enhanced audio saved to: \(outputURL.path)")
        return outputURL
    }
}
