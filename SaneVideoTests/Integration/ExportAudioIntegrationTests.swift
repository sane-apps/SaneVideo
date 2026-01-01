//
//  ExportAudioIntegrationTests.swift
//  SaneVideoTests
//
//  Audio-specific export integration tests.
//  Split from ExportPipelineIntegrationTests for maintainability.
//

import AVFoundation
import CoreMedia
import XCTest

@testable import SaneVideo

/// Integration tests for audio export functionality.
final class ExportAudioIntegrationTests: XCTestCase {

    // MARK: - Properties

    var projectState: ProjectState!
    var exportEngine: ExportEngine!
    var tempOutputURL: URL!
    var testAssetURL: URL!

    // MARK: - Setup & Teardown

    @MainActor
    override func setUp() {
        super.setUp()
        projectState = ProjectState()
        exportEngine = ExportEngine()
        let tempDir = FileManager.default.temporaryDirectory
        tempOutputURL = tempDir.appendingPathComponent("test_audio_export_\(UUID().uuidString).mp4")
        testAssetURL = getTestAssetURL()
    }

    override func tearDown() {
        if let url = tempOutputURL, FileManager.default.fileExists(atPath: url.path) {
            try? FileManager.default.removeItem(at: url)
        }
        projectState = nil
        exportEngine = nil
        super.tearDown()
    }

    // MARK: - Helpers

    private func getTestAssetURL() -> URL {
        let silenceAsset = TestEnvironment.testAsset(named: "test_silence.mp4")
        if FileManager.default.fileExists(atPath: silenceAsset.path) {
            return silenceAsset
        }
        return TestEnvironment.mockAssetURL
    }

    @MainActor
    private func createProjectWithClip() async throws -> (VideoProject, VideoClip) {
        let asset = AVURLAsset(url: testAssetURL)
        let duration = try await asset.load(.duration)

        let clip = VideoClip(
            url: testAssetURL,
            duration: duration,
            startTime: .zero
        )

        projectState.startNewProject()
        projectState.addTrack(type: .video, name: "Video Track 1")
        projectState.addClip(clip)

        guard let project = projectState.currentProject else {
            throw TestError.projectNotCreated
        }

        return (project, clip)
    }

    private func verifyExportedFile(at url: URL) async throws -> AVAsset {
        XCTAssertTrue(FileManager.default.fileExists(atPath: url.path))
        let fileSize = try FileManager.default.attributesOfItem(atPath: url.path)[.size] as? Int ?? 0
        XCTAssertGreaterThan(fileSize, 0)
        let asset = AVURLAsset(url: url)
        let isPlayable = try await asset.load(.isPlayable)
        XCTAssertTrue(isPlayable)
        return asset
    }

    // MARK: - Audio Preservation Tests

    @MainActor
    func testExportPreservesAudio() async throws {
        guard FileManager.default.fileExists(atPath: testAssetURL.path) else {
            throw XCTSkip("Test asset not available")
        }

        let sourceAsset = AVURLAsset(url: testAssetURL)
        let audioTracks = try await sourceAsset.loadTracks(withMediaType: .audio)

        guard !audioTracks.isEmpty else {
            throw XCTSkip("Test video has no audio track")
        }

        let (project, _) = try await createProjectWithClip()
        let settings = SaneExportSettings()

        let outputURL = try await exportEngine.export(
            project: project,
            settings: settings,
            outputURL: tempOutputURL
        ) { _ in }

        let exportedAsset = try await verifyExportedFile(at: outputURL)
        let exportedAudioTracks = try await exportedAsset.loadTracks(withMediaType: .audio)

        XCTAssertFalse(exportedAudioTracks.isEmpty, "Exported file should have audio track")
    }

    @MainActor
    func testExportWithVolumeChange() async throws {
        guard FileManager.default.fileExists(atPath: testAssetURL.path) else {
            throw XCTSkip("Test asset not available")
        }

        let (_, clip) = try await createProjectWithClip()
        projectState.updateClipVolume(clipId: clip.id, volume: 0.5)

        guard let project = projectState.currentProject else {
            throw TestError.projectNotCreated
        }

        let outputURL = try await exportEngine.export(
            project: project,
            settings: SaneExportSettings(),
            outputURL: tempOutputURL
        ) { _ in }

        let exportedAsset = try await verifyExportedFile(at: outputURL)
        let isPlayable = try await exportedAsset.load(.isPlayable)
        XCTAssertTrue(isPlayable, "Export with volume change should produce playable file")
    }

    @MainActor
    func testExportWithMutedClip() async throws {
        guard FileManager.default.fileExists(atPath: testAssetURL.path) else {
            throw XCTSkip("Test asset not available")
        }

        let (_, clip) = try await createProjectWithClip()
        projectState.updateClipVolume(clipId: clip.id, volume: 0.0)

        guard let project = projectState.currentProject else {
            throw TestError.projectNotCreated
        }

        let outputURL = try await exportEngine.export(
            project: project,
            settings: SaneExportSettings(),
            outputURL: tempOutputURL
        ) { _ in }

        let exportedAsset = try await verifyExportedFile(at: outputURL)
        let isPlayable = try await exportedAsset.load(.isPlayable)
        XCTAssertTrue(isPlayable, "Export with muted clip should produce playable file")
    }

    // MARK: - Volume Amplitude Verification

    @MainActor
    func testVolumeChangeAffectsAudioAmplitude() async throws {
        guard FileManager.default.fileExists(atPath: testAssetURL.path) else {
            throw XCTSkip("Test asset not available")
        }

        let sourceAsset = AVURLAsset(url: testAssetURL)
        let audioTracks = try await sourceAsset.loadTracks(withMediaType: .audio)

        guard !audioTracks.isEmpty else {
            throw XCTSkip("Test video has no audio track")
        }

        let duration = try await sourceAsset.load(.duration)

        // Export at full volume
        let clip1 = VideoClip(url: testAssetURL, duration: duration, startTime: .zero)
        projectState.startNewProject()
        projectState.addTrack(type: .video, name: "Video Track 1")
        projectState.addClip(clip1)
        projectState.updateClipVolume(clipId: clip1.id, volume: 1.0)

        guard let projectFull = projectState.currentProject else {
            throw TestError.projectNotCreated
        }

        let tempFull = tempOutputURL.deletingLastPathComponent()
            .appendingPathComponent("full_volume_\(UUID().uuidString).mp4")
        defer { try? FileManager.default.removeItem(at: tempFull) }

        _ = try await exportEngine.export(
            project: projectFull,
            settings: SaneExportSettings(),
            outputURL: tempFull
        ) { _ in }

        // Export at reduced volume
        let clip2 = VideoClip(url: testAssetURL, duration: duration, startTime: .zero)
        projectState.startNewProject()
        projectState.addTrack(type: .video, name: "Video Track 1")
        projectState.addClip(clip2)
        projectState.updateClipVolume(clipId: clip2.id, volume: 0.25)

        guard let projectReduced = projectState.currentProject else {
            throw TestError.projectNotCreated
        }

        let tempReduced = tempOutputURL.deletingLastPathComponent()
            .appendingPathComponent("reduced_volume_\(UUID().uuidString).mp4")
        defer { try? FileManager.default.removeItem(at: tempReduced) }

        _ = try await exportEngine.export(
            project: projectReduced,
            settings: SaneExportSettings(),
            outputURL: tempReduced
        ) { _ in }

        // Analyze audio peak amplitude
        let fullAmp = try await measurePeakAmplitude(at: tempFull)
        let reducedAmp = try await measurePeakAmplitude(at: tempReduced)

        if fullAmp > 0.01 {
            XCTAssertLessThan(
                reducedAmp,
                fullAmp * 0.75,
                "25% volume should reduce amplitude. Full: \(fullAmp), Reduced: \(reducedAmp)"
            )
        }
    }

    private func measurePeakAmplitude(at url: URL) async throws -> Float {
        let asset = AVURLAsset(url: url)
        let audioTracks = try await asset.loadTracks(withMediaType: .audio)

        guard let audioTrack = audioTracks.first else { return 0 }

        let reader = try AVAssetReader(asset: asset)
        let outputSettings: [String: Any] = [
            AVFormatIDKey: kAudioFormatLinearPCM,
            AVLinearPCMBitDepthKey: 16,
            AVLinearPCMIsBigEndianKey: false,
            AVLinearPCMIsFloatKey: false,
            AVLinearPCMIsNonInterleaved: false
        ]

        let output = AVAssetReaderTrackOutput(track: audioTrack, outputSettings: outputSettings)
        reader.add(output)
        reader.startReading()

        var peakAmplitude: Float = 0

        while reader.status == .reading {
            guard let sampleBuffer = output.copyNextSampleBuffer() else { break }
            defer { CMSampleBufferInvalidate(sampleBuffer) }

            guard let blockBuffer = CMSampleBufferGetDataBuffer(sampleBuffer) else { continue }

            var length = 0
            var dataPointer: UnsafeMutablePointer<Int8>?
            CMBlockBufferGetDataPointer(blockBuffer, atOffset: 0, lengthAtOffsetOut: nil, totalLengthOut: &length, dataPointerOut: &dataPointer)

            if let data = dataPointer {
                let samples = data.withMemoryRebound(to: Int16.self, capacity: length / 2) { ptr in
                    Array(UnsafeBufferPointer(start: ptr, count: length / 2))
                }

                for sample in samples {
                    let amplitude = Float(abs(sample)) / Float(Int16.max)
                    peakAmplitude = max(peakAmplitude, amplitude)
                }
            }
        }

        return peakAmplitude
    }

    // MARK: - Error Type

    enum TestError: Error {
        case projectNotCreated
    }
}
