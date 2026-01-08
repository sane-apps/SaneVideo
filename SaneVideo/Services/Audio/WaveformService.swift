//
//  WaveformService.swift
//  SaneVideo
//
//  Created by SaneVideo Refactor
//

import AVFoundation
import CoreMedia
import SwiftUI

actor WaveformService: WaveformServiceProtocol {

    // Cache: ClipID -> [Float] (normalized samples)
    private var cache: [UUID: [Float]] = [:]
    // Cache key: ClipID -> URL used to generate cached waveform
    private var cacheURL: [UUID: URL] = [:]

    // In-progress tasks
    private var tasks: [UUID: Task<[Float], Error>] = [:]
    
    // CRITICAL FIX: Limit concurrent waveform loads to prevent UI freezes
    // Use a semaphore-like pattern with a task queue
    private var activeLoads: Set<UUID> = []
    private let maxConcurrentLoads = 5 // Limit to 5 concurrent waveform generations

    func waveform(for clip: VideoClip) async -> [Float]? {
        // Pick the audio URL that matches playback/export (enhanced audio when duration-aligned).
        let selectedURL = await selectAudioURL(for: clip)

        // CRITICAL FIX: Check cache first
        if let cached = cache[clip.id], cacheURL[clip.id] == selectedURL {
            return cached
        } else if cache[clip.id] != nil, cacheURL[clip.id] != selectedURL {
            // Clip audio source changed (e.g., enhanced audio created/cleared). Drop stale waveform.
            cache.removeValue(forKey: clip.id)
            cacheURL.removeValue(forKey: clip.id)
        }

        // CRITICAL FIX: Check if task already exists
        if let existingTask = tasks[clip.id] {
            return try? await existingTask.value
        }

        // CRITICAL FIX: Wait for available slot if at capacity
        while activeLoads.count >= maxConcurrentLoads {
            // Wait a bit before checking again
            try? await Task.sleep(nanoseconds: 50_000_000) // 50ms
            // Check if task was cancelled
            if Task.isCancelled {
                return nil
            }
        }

        // CRITICAL FIX: Mark as active load BEFORE creating task
        // This prevents race condition where multiple tasks could be created
        activeLoads.insert(clip.id)

        let clipId = clip.id
        let task = Task<[Float], Error> {
            let samples = try await generateWaveform(for: clip, audioURL: selectedURL)
            // CRITICAL FIX: Only cache if task wasn't cancelled
            guard !Task.isCancelled else {
                return []
            }
            return samples
        }

        tasks[clip.id] = task
        
        // CRITICAL FIX: Handle cancellation and cleanup properly
        do {
            let samples = try await task.value
            // CRITICAL FIX: Cache result and cleanup on success
            cache[clipId] = samples
            cacheURL[clipId] = selectedURL
            tasks.removeValue(forKey: clipId)
            activeLoads.remove(clipId)
            return samples
        } catch is CancellationError {
            // Task was cancelled, cleanup
            tasks.removeValue(forKey: clipId)
            activeLoads.remove(clipId)
            return nil
        } catch {
            // Other error, cleanup
            tasks.removeValue(forKey: clipId)
            activeLoads.remove(clipId)
            return nil
        }
    }
    
    /// CRITICAL FIX: Cancel waveform load for a clip (e.g., when off-screen)
    func cancelLoad(for clip: VideoClip) {
        if let task = tasks[clip.id] {
            task.cancel()
            tasks.removeValue(forKey: clip.id)
            activeLoads.remove(clip.id)
            // CRITICAL FIX: Also remove from cache if it was a partial load
            // (though typically we'd keep partial results, but for cancellation we clear)
        }
    }

    private func generateWaveform(for clip: VideoClip, audioURL: URL) async throws -> [Float] {
        let asset = AVURLAsset(url: audioURL)

        // Load tracks and duration
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

        // CRITICAL FIX: Dynamic downsampling based on clip duration
        // Target ~2000 samples for visualization (works well for most waveform widths)
        // This prevents memory explosion and processing delays for 2+ hour clips
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

        // Calculate how many audio samples to skip per output sample
        // Minimum of 800 for short clips to maintain performance
        let calculatedSkip = max(800, Int(totalAudioSamples / Double(targetSampleCount)))
        let accumulationWindow = max(10, calculatedSkip / 800) // Scale accumulation window with skip rate

        // Read samples
        while reader.status == .reading {
            guard let sampleBuffer = trackOutput.copyNextSampleBuffer() else { break }
            guard let blockBuffer = CMSampleBufferGetDataBuffer(sampleBuffer) else { continue }

            var length = 0
            var dataPointer: UnsafeMutablePointer<Int8>?

            guard CMBlockBufferGetDataPointer(
                blockBuffer,
                atOffset: 0,
                lengthAtOffsetOut: nil,
                totalLengthOut: &length,
                dataPointerOut: &dataPointer
            ) == kCMBlockBufferNoErr,
                let data = dataPointer else { continue }

            let sampleCount = length / 2 // 16-bit
            let ptr = data.withMemoryRebound(to: Int16.self, capacity: sampleCount) { $0 }

            // Downsample: Take max amplitude in chunk
            // Dynamic rate based on clip length to ensure ~2000 total samples
            var maxAmp: Float = 0
            var count = 0

            for i in stride(from: 0, to: sampleCount, by: calculatedSkip) {
                let val = Float(abs(ptr[i])) / Float(Int16.max)
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
        // CRITICAL FIX: Cancel all in-progress tasks before clearing
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
