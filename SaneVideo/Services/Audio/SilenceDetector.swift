@preconcurrency import AVFoundation
import Accelerate

actor SilenceDetector {
    struct Configuration {
        /// Threshold in decibels (e.g. -50.0)
        var dbThreshold: Float
        /// Minimum duration of silence to detect (seconds)
        var minDuration: Double
        /// Padding (seconds) shrunk from each side of detected silence ranges
        var margin: Double = 0.1
        /// Fraction of loud samples allowed within a "silent" region (0.0-1.0)
        var tolerance: Double = 0.1

        // -45dB = more sensitive to quiet pauses, -35dB = only very quiet
        static let `default` = Configuration(
            dbThreshold: -45.0, minDuration: 0.3
        )
    }

    /// Progress callback: (processedSeconds, totalSeconds)
    typealias ProgressHandler = @Sendable (Double, Double) -> Void

    func detectSilence(
        in clip: VideoClip,
        config: Configuration = .default,
        progressHandler: ProgressHandler? = nil
    ) async throws -> [CMTimeRange] {
        let totalDuration = clip.duration.seconds
        await MainActor.run {
            AppLogger.project.debug("Silence detection: threshold=\(config.dbThreshold)dB, minDuration=\(config.minDuration)s, duration=\(String(format: "%.1f", totalDuration))s")
        }
        
        // Use enhanced audio if available for better detection accuracy
        let audioURL = clip.enhancedAudioURL ?? clip.url
        await MainActor.run {
             AppLogger.project.debug("Silence detection using source: \(audioURL.lastPathComponent)")
        }
        
        let asset = AVURLAsset(url: audioURL)

        let tracks = try await asset.loadTracks(withMediaType: .audio)
        guard let track = tracks.first else {
            await MainActor.run {
                AppLogger.project.warning("⚠️ Silence detection: No audio track found - skipping silence detection")
            }
            return []
        }

        await MainActor.run {
            AppLogger.project.debug("Silence detection: Found audio track, setting up reader...")
        }

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
        var regionBufferCount = 0
        var regionLoudCount = 0

        func toDB(_ amplitude: Float) -> Float {
            return 20.0 * log10(max(amplitude, 0.0001))
        }

        var lastProgressUpdate = Date()
        var processedBuffers = 0
        let startTime = Date()
        let maxProcessingTime: TimeInterval = 300.0
        AppLogger.project.debug("🔇 SilenceDetector: Starting buffer loop...")

        while reader.status == .reading {
            if Date().timeIntervalSince(startTime) > maxProcessingTime {
                await MainActor.run {
                    AppLogger.project.warning("⚠️ Silence detection: Timeout after 5 minutes, stopping analysis")
                }
                break
            }
            
            if Task.isCancelled {
                await MainActor.run {
                    AppLogger.project.info("🔇 Silence detection: Cancelled by user")
                }
                break
            }
            
            if processedBuffers % 1000 == 0 {
                await Task.yield()
            }
            guard let buffer = output.copyNextSampleBuffer() else { break }
            guard let pcmBuffer = AVAudioPCMBuffer(sampleBuffer: buffer),
                  pcmBuffer.format.commonFormat == .pcmFormatInt16,
                  pcmBuffer.format.isInterleaved,
                  let channels = pcmBuffer.int16ChannelData else { continue }
            let sampleCount = Int(pcmBuffer.frameLength) * Int(pcmBuffer.format.channelCount)

            // Keep the native PCM storage alive through the existing conversion.
            var floatSamples = [Float](repeating: 0, count: sampleCount)
            withExtendedLifetime(pcmBuffer) {
                vDSP_vflt16(channels[0], 1, &floatSamples, 1, vDSP_Length(sampleCount))
            }

            // Normalize to -1.0 to 1.0 range
            var normalized = [Float](repeating: 0, count: sampleCount)
            var scale: Float = 1.0 / Float(Int16.max)
            vDSP_vsmul(floatSamples, 1, &scale, &normalized, 1, vDSP_Length(sampleCount))
            
            var rms: Float = 0
            vDSP_rmsqv(normalized, 1, &rms, vDSP_Length(sampleCount))
            
            let db = toDB(rms)
            
            let isBufferSilent = db <= config.dbThreshold

            let bufferTime = CMSampleBufferGetPresentationTimeStamp(buffer)
            processedBuffers += 1
            if processedBuffers % 100 == 0 {
                 AppLogger.project.debug("🔇 SilenceDetector: Processed \(processedBuffers) buffers (at \(bufferTime.seconds)s)")
            }

            let now = Date()
            if now.timeIntervalSince(lastProgressUpdate) >= 2.0 {
                lastProgressUpdate = now
                progressHandler?(bufferTime.seconds, totalDuration)
            }

            if isBufferSilent {
                if silenceStart == nil {
                    silenceStart = bufferTime
                    regionBufferCount = 0
                    regionLoudCount = 0
                }
                regionBufferCount += 1
            } else {
                if silenceStart != nil {
                    regionBufferCount += 1
                    regionLoudCount += 1
                    // Check if loud ratio exceeds tolerance — if so, end the region
                    let loudRatio = regionBufferCount > 0 ? Double(regionLoudCount) / Double(regionBufferCount) : 1.0
                    if loudRatio > config.tolerance {
                        if let start = silenceStart {
                            let duration = CMTimeSubtract(bufferTime, start)
                            if duration.seconds >= config.minDuration {
                                silentRanges.append(CMTimeRange(start: start, duration: duration))
                            }
                        }
                        silenceStart = nil
                        regionBufferCount = 0
                        regionLoudCount = 0
                    }
                }
            }
        }

        // Close a silence region still open at the end.
        if let start = silenceStart {
            let end = clip.duration
            let duration = CMTimeSubtract(end, start)
            if duration.seconds >= config.minDuration {
                silentRanges.append(CMTimeRange(start: start, duration: duration))
            }
        }

        if config.margin > 0 {
            silentRanges = Self.applyMargin(silentRanges, margin: config.margin)
        }

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

    /// Shrinks each range by `margin` seconds on both sides, dropping any that collapse
    static func applyMargin(_ ranges: [CMTimeRange], margin: Double) -> [CMTimeRange] {
        let marginTime = CMTime(seconds: margin, preferredTimescale: 600)
        return ranges.compactMap { range in
            let newStart = CMTimeAdd(range.start, marginTime)
            let newEnd = CMTimeSubtract(range.end, marginTime)
            guard newEnd > newStart else { return nil }
            return CMTimeRange(start: newStart, end: newEnd)
        }
    }

    static func hasAudioTrack(url: URL) async -> Bool {
        let asset = AVURLAsset(url: url)
        let tracks = try? await asset.loadTracks(withMediaType: .audio)
        return !(tracks ?? []).isEmpty
    }
}
