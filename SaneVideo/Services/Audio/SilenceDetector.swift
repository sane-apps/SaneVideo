import AVFoundation

/// Service for detecting silence in video clips
actor SilenceDetector {
    struct Configuration {
        /// Threshold in decibels (e.g. -50.0)
        var dbThreshold: Float
        /// Minimum duration of silence to detect (seconds)
        var minDuration: Double

        // -45dB = more sensitive to quiet pauses, -35dB = only very quiet
        static let `default` = Configuration(dbThreshold: -45.0, minDuration: 0.3)
    }

    /// Progress callback: (processedSeconds, totalSeconds)
    typealias ProgressHandler = @Sendable (Double, Double) -> Void

    /// Detects silent ranges in a video clip
    /// - Parameters:
    ///   - clip: The video clip to analyze
    ///   - config: Detection configuration
    ///   - progressHandler: Optional callback for progress updates
    /// - Returns: Array of time ranges where silence was detected
    func detectSilence(
        in clip: VideoClip,
        config: Configuration = .default,
        progressHandler: ProgressHandler? = nil
    ) async throws -> [CMTimeRange] {
        let totalDuration = clip.duration.seconds
        await MainActor.run {
            AppLogger.project.debug("Silence detection: threshold=\(config.dbThreshold)dB, minDuration=\(config.minDuration)s, duration=\(String(format: "%.1f", totalDuration))s")
        }
        
        // CRITICAL FIX: Use enhanced audio if available for better detection accuracy
        let audioURL = clip.enhancedAudioURL ?? clip.url
        await MainActor.run {
             AppLogger.project.debug("Silence detection using source: \(audioURL.lastPathComponent)")
        }
        
        let asset = AVURLAsset(url: audioURL)

        // Load audio track
        let tracks = try await asset.loadTracks(withMediaType: .audio)
        guard let track = tracks.first else {
            await MainActor.run {
                AppLogger.project.warning("⚠️ Silence detection: No audio track found - treating entire clip as silent")
            }
            return [CMTimeRange(start: .zero, duration: clip.duration)]
        }

        await MainActor.run {
            AppLogger.project.debug("Silence detection: Found audio track, setting up reader...")
        }

        // Setup Reader
        let settings: [String: Any] = [
            AVFormatIDKey: kAudioFormatLinearPCM,
            AVLinearPCMBitDepthKey: 16,
            AVLinearPCMIsBigEndianKey: false,
            AVLinearPCMIsFloatKey: false,
            AVLinearPCMIsNonInterleaved: false
        ]

        let reader = try AVAssetReader(asset: asset)
        let output = AVAssetReaderTrackOutput(track: track, outputSettings: settings)
        reader.add(output)

        guard reader.startReading() else {
            let errorMsg = reader.error?.localizedDescription ?? "Unknown error"
            await MainActor.run {
                AppLogger.project.error("❌ Silence detection: AVAssetReader failed to start: \(errorMsg)")
            }
            throw NSError(domain: "SilenceDetector", code: 1, userInfo: [NSLocalizedDescriptionKey: errorMsg])
        }

        await MainActor.run {
            AppLogger.project.debug("Silence detection: Reader started, processing \(String(format: "%.1f", totalDuration))s of audio...")
        }

        var silentRanges: [CMTimeRange] = []
        var silenceStart: CMTime?

        // Helper to convert linear amplitude to dB
        func toDB(_ amplitude: Float) -> Float {
            return 20.0 * log10(max(amplitude, 0.0001))
        }

        // Process samples
        var lastProgressUpdate = Date()
        var processedBuffers = 0
        let startTime = Date()
        let maxProcessingTime: TimeInterval = 300.0 // 5 minutes max
        AppLogger.project.debug("🔇 SilenceDetector: Starting buffer loop...")

        while reader.status == .reading {
            // ROBUSTNESS: Check for timeout
            if Date().timeIntervalSince(startTime) > maxProcessingTime {
                await MainActor.run {
                    AppLogger.project.warning("⚠️ Silence detection: Timeout after 5 minutes, stopping analysis")
                }
                break
            }
            
            // ROBUSTNESS: Check for cancellation
            if Task.isCancelled {
                await MainActor.run {
                    AppLogger.project.info("🔇 Silence detection: Cancelled by user")
                }
                break
            }
            
            // ROBUSTNESS: Yield periodically
            if processedBuffers % 1000 == 0 {
                await Task.yield()
            }
            guard let buffer = output.copyNextSampleBuffer() else { break }
            guard let blockBuffer = CMSampleBufferGetDataBuffer(buffer) else { continue }

            var length = 0
            var dataPointer: UnsafeMutablePointer<Int8>?

            guard CMBlockBufferGetDataPointer(blockBuffer, atOffset: 0, lengthAtOffsetOut: nil, totalLengthOut: &length, dataPointerOut: &dataPointer) == kCMBlockBufferNoErr,
                  let data = dataPointer else { continue }

            let sampleCount = length / 2
            let samples = data.withMemoryRebound(to: Int16.self, capacity: sampleCount) { $0 }

            // Check if this buffer is silent
            var isBufferSilent = true

            for i in stride(from: 0, to: sampleCount, by: 10) { // Check every 10th sample for speed
                let amp = Float(abs(samples[i])) / Float(Int16.max)
                if toDB(amp) > config.dbThreshold {
                    isBufferSilent = false
                    break
                }
            }

            // Time logic
            let bufferTime = CMSampleBufferGetPresentationTimeStamp(buffer)
            processedBuffers += 1
            if processedBuffers % 100 == 0 {
                 AppLogger.project.debug("🔇 SilenceDetector: Processed \(processedBuffers) buffers (at \(bufferTime.seconds)s)")
            }

            // Report progress periodically (every 2 seconds)
            let now = Date()
            if now.timeIntervalSince(lastProgressUpdate) >= 2.0 {
                lastProgressUpdate = now
                progressHandler?(bufferTime.seconds, totalDuration)
            }

            if isBufferSilent {
                if silenceStart == nil {
                    silenceStart = bufferTime
                }
            } else {
                if let start = silenceStart {
                    let duration = CMTimeSubtract(bufferTime, start)
                    if duration.seconds >= config.minDuration {
                        silentRanges.append(CMTimeRange(start: start, duration: duration))
                    }
                    silenceStart = nil
                }
            }
        }

        // Check finding silence at the end
        if let start = silenceStart {
            let end = clip.duration
            let duration = CMTimeSubtract(end, start)
            if duration.seconds >= config.minDuration {
                silentRanges.append(CMTimeRange(start: start, duration: duration))
            }
        }

        // Log result summary
        let readerStatus = reader.status
        let rangeCount = silentRanges.count
        let rangesEmpty = silentRanges.isEmpty

        await MainActor.run {
            AppLogger.project.info("Silence detection complete: found \(rangeCount) silent ranges, reader status: \(String(describing: readerStatus))")
            if rangesEmpty {
                AppLogger.project.debug("Silence detection: No silent segments found (threshold may be too low or audio has no pauses)")
            }
        }

        return silentRanges
    }
}
