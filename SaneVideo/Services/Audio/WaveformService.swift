@preconcurrency import AVFoundation
import CoreMedia
import SwiftUI

actor WaveformService: WaveformServiceProtocol {

    // Cache: ClipID -> [Float] (normalized samples)
    private var cache: [UUID: [Float]] = [:]
    // Cache key: ClipID -> URL used to generate cached waveform
    private var cacheURL: [UUID: URL] = [:]

    private var tasks: [UUID: Task<[Float], Error>] = [:]
    
    // Limit concurrent waveform loads to prevent UI freezes
    private var activeLoads: Set<UUID> = []
    private let maxConcurrentLoads = 5

    func waveform(for clip: VideoClip) async -> [Float]? {
        // Pick the audio URL that matches playback/export (enhanced audio when duration-aligned).
        let selectedURL = await selectAudioURL(for: clip)

        if let cached = cache[clip.id], cacheURL[clip.id] == selectedURL {
            return cached
        } else if cache[clip.id] != nil, cacheURL[clip.id] != selectedURL {
            // Clip audio source changed (e.g., enhanced audio created/cleared). Drop stale waveform.
            cache.removeValue(forKey: clip.id)
            cacheURL.removeValue(forKey: clip.id)
        }

        if let existingTask = tasks[clip.id] {
            return try? await existingTask.value
        }

        while activeLoads.count >= maxConcurrentLoads {
            try? await Task.sleep(nanoseconds: 50_000_000) // 50ms
            if Task.isCancelled {
                return nil
            }
        }

        // Mark the load active before creating the task so concurrent callers cannot start a duplicate.
        activeLoads.insert(clip.id)

        let clipId = clip.id
        let task = Task<[Float], Error> {
            let samples = try await generateWaveform(for: clip, audioURL: selectedURL)
            guard !Task.isCancelled else {
                return []
            }
            return samples
        }

        tasks[clip.id] = task
        
        do {
            let samples = try await task.value
            cache[clipId] = samples
            cacheURL[clipId] = selectedURL
            tasks.removeValue(forKey: clipId)
            activeLoads.remove(clipId)
            return samples
        } catch is CancellationError {
            tasks.removeValue(forKey: clipId)
            activeLoads.remove(clipId)
            return nil
        } catch {
            tasks.removeValue(forKey: clipId)
            activeLoads.remove(clipId)
            return nil
        }
    }
    
    /// Cancels the waveform load for a clip, for example when it scrolls off-screen.
    func cancelLoad(for clip: VideoClip) {
        if let task = tasks[clip.id] {
            task.cancel()
            tasks.removeValue(forKey: clip.id)
            activeLoads.remove(clip.id)
        }
    }

    private func generateWaveform(for clip: VideoClip, audioURL: URL) async throws -> [Float] {
        let asset = AVURLAsset(url: audioURL)

        let tracks = try await asset.loadTracks(withMediaType: .audio)
        guard let track = tracks.first else {
            await MainActor.run {
                AppLogger.timeline.warning("WaveformService: No audio track found for \(audioURL.lastPathComponent)")
            }
            return []
        }

        let duration = try await asset.load(.duration)
        let durationSeconds = duration.seconds

        let outputSettings: [String: Any] = [
            AVFormatIDKey: kAudioFormatLinearPCM,
            AVLinearPCMBitDepthKey: 16,
            AVLinearPCMIsBigEndianKey: false,
            AVLinearPCMIsFloatKey: false,
            AVLinearPCMIsNonInterleaved: false
        ]

        let reader = try AVAssetReader(asset: asset)
        let trackOutput = AVAssetReaderTrackOutput(track: track, outputSettings: outputSettings)
        reader.add(trackOutput)

        reader.startReading()

        var samples: [Float] = []

        // Target about 2000 samples: enough for the waveform, and bounded for multi-hour clips.
        let targetSampleCount = 2000
        // Prefer reading sample rate from the track's format description (avoid hardcoded 44.1k assumptions).
        let sampleRate: Double
        if let formatDescriptions = try? await track.load(.formatDescriptions),
           let formatDesc = formatDescriptions.first,
           let asbd = CMAudioFormatDescriptionGetStreamBasicDescription(formatDesc) {
            sampleRate = asbd.pointee.mSampleRate
        } else {
            sampleRate = 44_100
        }
        let totalAudioSamples = durationSeconds * sampleRate

        // Minimum of 800 for short clips to maintain performance
        let calculatedSkip = max(800, Int(totalAudioSamples / Double(targetSampleCount)))
        let accumulationWindow = max(10, calculatedSkip / 800)

        while reader.status == .reading {
            guard let sampleBuffer = trackOutput.copyNextSampleBuffer() else { break }
            guard let blockBuffer = CMSampleBufferGetDataBuffer(sampleBuffer) else { continue }

            // AVAssetReader supplies interleaved, little-endian signed PCM16.
            // CopyDataBytes handles noncontiguous blocks and keeps pointers scoped.
            let length = CMBlockBufferGetDataLength(blockBuffer)
            guard length > 0, length.isMultiple(of: MemoryLayout<Int16>.size) else { continue }
            let sampleCount = length / MemoryLayout<Int16>.size
            var pcm = [Int16](repeating: 0, count: sampleCount)
            let copyStatus = pcm.withUnsafeMutableBytes { bytes in
                CMBlockBufferCopyDataBytes(blockBuffer, atOffset: 0, dataLength: length,
                                           destination: bytes.baseAddress!)
            }
            guard copyStatus == kCMBlockBufferNoErr else { continue }

            // Downsample: keep the max amplitude in each chunk.
            var maxAmp: Float = 0
            var count = 0

            for i in stride(from: 0, to: sampleCount, by: calculatedSkip) {
                let val = min(1, abs(Float(Int16(littleEndian: pcm[i]))) / Float(Int16.max))
                if val > maxAmp {
                    maxAmp = val
                }
                count += 1

                if count >= accumulationWindow {
                    samples.append(maxAmp)
                    maxAmp = 0
                    count = 0
                }
            }
        }

        return samples
    }

    private func selectAudioURL(for clip: VideoClip) async -> URL {
        guard let enhancedURL = clip.enhancedAudioURL else { return clip.url }

        let asset = AVURLAsset(url: enhancedURL)
        let enhancedDuration = (try? await asset.load(.duration)) ?? .zero
        if AudioTrackBuilder.shouldUseEnhancedAudio(clipDuration: clip.duration, enhancedDuration: enhancedDuration) {
            return enhancedURL
        }

        await MainActor.run {
            AppLogger.timeline.warning(
                "⚠️ WaveformService: Enhanced audio duration mismatch for \(clip.url.lastPathComponent). " +
                    "clip=\(clip.duration.seconds)s enhanced=\(enhancedDuration.seconds)s. Using original audio for waveform."
            )
        }
        return clip.url
    }

    /// Clear the waveform cache (called during memory pressure)
    func clearCache() {
        for task in tasks.values {
            task.cancel()
        }
        cache.removeAll()
        cacheURL.removeAll()
        tasks.removeAll()
        activeLoads.removeAll()
        AppLogger.timeline.info("WaveformService: Cache cleared")
    }
}
