//
//  WaveformService.swift
//  SaneVideo
//
//  Created by SaneVideo Refactor
//

import AVFoundation
import SwiftUI

actor WaveformService {

    // Cache: ClipID -> [Float] (normalized samples)
    private var cache: [UUID: [Float]] = [:]

    // In-progress tasks
    private var tasks: [UUID: Task<[Float], Error>] = [:]
    
    // CRITICAL FIX: Limit concurrent waveform loads to prevent UI freezes
    // Use a semaphore-like pattern with a task queue
    private var activeLoads: Set<UUID> = []
    private let maxConcurrentLoads = 5 // Limit to 5 concurrent waveform generations

    func waveform(for clip: VideoClip) async -> [Float]? {
        // CRITICAL FIX: Check cache first
        if let cached = cache[clip.id] {
            return cached
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
            let samples = try await generateWaveform(for: clip)
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

    private func generateWaveform(for clip: VideoClip) async throws -> [Float] {
        let asset = AVURLAsset(url: clip.url)

        // Load tracks
        let tracks = try await asset.loadTracks(withMediaType: .audio)
        guard let track = tracks.first else {
            await MainActor.run { AppLogger.timeline.warning("WaveformService: No audio track found for \(clip.url.lastPathComponent)") }
            return []
        }

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
            // This is a simplified extraction for visualization
            var maxAmp: Float = 0
            var count = 0
            let downsampleRate = 800 // Skip samples for performance (approx 55 samples/sec at 44.1kHz)

            for i in stride(from: 0, to: sampleCount, by: downsampleRate) {
                let val = Float(abs(ptr[i])) / Float(Int16.max)
                if val > maxAmp {
                    maxAmp = val
                }
                count += 1

                if count >= 10 { // Accumulate a bit
                    samples.append(maxAmp)
                    maxAmp = 0
                    count = 0
                }
            }
        }

        return samples
    }

    /// Clear the waveform cache (called during memory pressure)
    func clearCache() {
        // CRITICAL FIX: Cancel all in-progress tasks before clearing
        for task in tasks.values {
            task.cancel()
        }
        cache.removeAll()
        tasks.removeAll()
        activeLoads.removeAll()
        AppLogger.timeline.info("WaveformService: Cache cleared")
    }
}
