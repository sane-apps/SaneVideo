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

    func waveform(for clip: VideoClip) async -> [Float]? {
        if let cached = cache[clip.id] {
            return cached
        }

        if let existingTask = tasks[clip.id] {
            return try? await existingTask.value
        }

        let task = Task {
            // CRITICAL FIX: Use defer to clean up task even on failure
            defer { tasks[clip.id] = nil }

            let samples = try await generateWaveform(for: clip)
            cache[clip.id] = samples
            return samples
        }

        tasks[clip.id] = task
        return try? await task.value
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
        cache.removeAll()
        tasks.removeAll()
        AppLogger.timeline.info("WaveformService: Cache cleared")
    }
}
