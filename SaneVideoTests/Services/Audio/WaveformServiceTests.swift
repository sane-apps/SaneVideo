//
//  WaveformServiceTests.swift
//  SaneVideoTests
//
//  Unit tests for WaveformService waveform generation.
//

import AVFoundation
import XCTest

@testable import SaneVideo

final class WaveformServiceTests: XCTestCase {

    @MainActor
    func testPreviewCacheClearPreservesMediaAndInvalidatesRealCaches() async throws {
        let fileManager = FileManager.default
        let root = fileManager.temporaryDirectory.appendingPathComponent("SaneVideo-CacheSafety-\(UUID().uuidString)")
        try fileManager.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? fileManager.removeItem(at: root) }

        var repo = URL(fileURLWithPath: #filePath)
        for _ in 0..<4 { repo.deleteLastPathComponent() }
        let fixture = repo.appendingPathComponent("Tests/Assets/test_video.mp4")
        let bytes = try Data(contentsOf: fixture)
        XCTAssertLessThan(bytes.count, 1024 * 1024)
        let duration = try await AVURLAsset(url: fixture).load(.duration)
        XCTAssertGreaterThan(duration.seconds, 0)

        let fallbackProjects = ProjectStore.defaultProjectsDirectory(
            moviesDirectory: nil, applicationSupportDirectory: nil,
            temporaryDirectory: root.appendingPathComponent("Temp")
        )
        let recording = root.appendingPathComponent("Movies/SaneVideo/Recordings/small-valid.mp4")
        let enhancedAudio = root.appendingPathComponent("Temp/EnhancedAudio/saved-enhanced.m4a")
        let project = fallbackProjects.appendingPathComponent("saved-project.json")
        let unrelated = root.appendingPathComponent("Temp/unrelated.txt")
        let protectedFiles: [(URL, Data)] = [
            (recording, bytes), (enhancedAudio, bytes), (unrelated, Data("unrelated temp data".utf8)),
            (project, try JSONSerialization.data(withJSONObject: [
                "recordingURL": recording.absoluteString, "enhancedAudioURL": enhancedAudio.absoluteString
            ]))
        ]
        for (url, data) in protectedFiles {
            try fileManager.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try data.write(to: url)
        }
        let thumbnailService = ThumbnailService()
        let waveformService = WaveformService()
        let prefs = UserPreferences()
        let probe = root.appendingPathComponent("cache-probe.mp4")
        try bytes.write(to: probe)
        let clip = VideoClip(url: probe, duration: duration)
        let size = CGSize(width: 160, height: 90)
        let initialThumbnail = await thumbnailService.thumbnail(for: clip, time: .zero, size: size)
        let firstImage = try XCTUnwrap(initialThumbnail)
        let initialWaveform = await waveformService.waveform(for: clip)
        let firstWaveform = try XCTUnwrap(initialWaveform)
        XCTAssertFalse(firstWaveform.isEmpty)

        await prefs.clearCache(thumbnailService: thumbnailService, waveformService: waveformService)
        for (url, data) in protectedFiles {
            XCTAssertEqual(try Data(contentsOf: url), data, "Cache clearing changed \(url.lastPathComponent)")
        }
        let regeneratedThumbnail = await thumbnailService.thumbnail(for: clip, time: .zero, size: size)
        let nextImage = try XCTUnwrap(regeneratedThumbnail)
        XCTAssertFalse(firstImage.value === nextImage.value, "Thumbnail cache was not invalidated")

        // Warm a real waveform, then remove only this disposable test probe.
        let warmed = await waveformService.waveform(for: clip)
        let warmWaveform = try XCTUnwrap(warmed)
        XCTAssertFalse(warmWaveform.isEmpty)
        try fileManager.removeItem(at: probe)
        let cachedWaveform = await waveformService.waveform(for: clip)
        XCTAssertEqual(cachedWaveform, warmWaveform)
        await prefs.clearCache(thumbnailService: thumbnailService, waveformService: waveformService)
        let afterClear = await waveformService.waveform(for: clip)
        XCTAssertNil(afterClear, "Waveform cache returned stale data after clearing")
    }

    func testRealPCMNegativeExtremeIsFiniteAndStableAfterCacheClear() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("SaneVideo-PCM-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let url = root.appendingPathComponent("negative-extreme.wav")
        let sampleRate: UInt32 = 48_000
        let pcm = [Int16](repeating: Int16.min.littleEndian, count: Int(sampleRate) * 2)
        let dataSize = UInt32(pcm.count * MemoryLayout<Int16>.size)
        var wave = Data()
        func appendLittleEndian<T: FixedWidthInteger>(_ value: T) {
            var littleEndian = value.littleEndian
            withUnsafeBytes(of: &littleEndian) { wave.append(contentsOf: $0) }
        }
        wave.append(contentsOf: "RIFF".utf8)
        appendLittleEndian(UInt32(36) + dataSize)
        wave.append(contentsOf: "WAVEfmt ".utf8)
        appendLittleEndian(UInt32(16))
        appendLittleEndian(UInt16(1)) // Linear PCM
        appendLittleEndian(UInt16(1)) // Mono
        appendLittleEndian(sampleRate)
        appendLittleEndian(sampleRate * 2)
        appendLittleEndian(UInt16(2))
        appendLittleEndian(UInt16(16))
        wave.append(contentsOf: "data".utf8)
        appendLittleEndian(dataSize)
        pcm.withUnsafeBytes { wave.append(contentsOf: $0) }
        try wave.write(to: url)

        let duration = try await AVURLAsset(url: url).load(.duration)
        XCTAssertEqual(duration.seconds, 2, accuracy: 0.001)
        let clip = VideoClip(url: url, duration: duration)
        let service = WaveformService()
        let generated = await service.waveform(for: clip)
        let first = try XCTUnwrap(generated)
        XCTAssertFalse(first.isEmpty, "Real PCM must generate waveform samples")
        XCTAssertTrue(first.allSatisfy { $0.isFinite && $0 == 1 },
                      "Int16.min must produce a bounded full-scale amplitude without overflow")
        await service.clearCache()
        let regenerated = await service.waveform(for: clip)
        XCTAssertEqual(regenerated, first, "Identical PCM must remain stable after regenerating")
    }
}
