//
//  ExportPipelineIntegrationTests.swift
//  SaneVideoTests
//
//  Core export pipeline integration tests: basic exports, resolution, codecs.
//  Additional tests split into:
//  - ExportAudioIntegrationTests.swift
//  - ExportEffectsIntegrationTests.swift
//  - ExportEdgeCaseIntegrationTests.swift
//

import AVFoundation
import CoreMedia
import XCTest

@testable import SaneVideo

/// Core integration tests for the export pipeline.
final class ExportPipelineIntegrationTests: XCTestCase {

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
        tempOutputURL = tempDir.appendingPathComponent("test_export_\(UUID().uuidString).mp4")
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

    // MARK: - Helper Methods

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
        XCTAssertTrue(FileManager.default.fileExists(atPath: url.path), "Exported file should exist")

        let fileSize = try FileManager.default.attributesOfItem(atPath: url.path)[.size] as? Int ?? 0
        XCTAssertGreaterThan(fileSize, 0, "Exported file should not be empty")

        let asset = AVURLAsset(url: url)
        let isPlayable = try await asset.load(.isPlayable)
        XCTAssertTrue(isPlayable, "Exported file should be playable")

        return asset
    }

    private func getVideoDimensions(from asset: AVAsset) async throws -> CGSize {
        let tracks = try await asset.loadTracks(withMediaType: .video)
        guard let track = tracks.first else {
            throw TestError.noVideoTrack
        }
        let size = try await track.load(.naturalSize)
        let transform = try await track.load(.preferredTransform)

        let transformedSize = size.applying(transform)
        return CGSize(width: abs(transformedSize.width), height: abs(transformedSize.height))
    }

    // MARK: - Basic Export Tests

    @MainActor
    func testBasicExportProducesPlayableFile() async throws {
        guard FileManager.default.fileExists(atPath: testAssetURL.path) else {
            throw XCTSkip("Test asset not available at \(testAssetURL.path)")
        }

        let (project, _) = try await createProjectWithClip()
        let settings = SaneExportSettings()

        var lastProgress: Double = 0
        let outputURL = try await exportEngine.export(
            project: project,
            settings: settings,
            outputURL: tempOutputURL
        ) { progress in
            lastProgress = progress
        }

        let exportedAsset = try await verifyExportedFile(at: outputURL)

        let exportedDuration = try await exportedAsset.load(.duration)
        let originalAsset = AVURLAsset(url: testAssetURL)
        let originalDuration = try await originalAsset.load(.duration)

        XCTAssertEqual(
            exportedDuration.seconds,
            originalDuration.seconds,
            accuracy: 0.5,
            "Exported duration should match original"
        )

        XCTAssertEqual(lastProgress, 1.0, accuracy: 0.01, "Progress should reach 100%")
    }

    // MARK: - Resolution Tests

    /// Exports to a fresh temp file and deletes it when the test ends.
    @MainActor
    private func export(_ project: VideoProject, settings: SaneExportSettings) async throws -> (AVAsset, URL) {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("pipeline_\(UUID().uuidString).mp4")
        addTeardownBlock { try? FileManager.default.removeItem(at: url) }
        let outputURL = try await exportEngine.export(
            project: project,
            settings: settings,
            outputURL: url
        ) { _ in }
        return (try await verifyExportedFile(at: outputURL), outputURL)
    }

    @MainActor
    func testExportMatchesRequestedResolution() async throws {
        guard FileManager.default.fileExists(atPath: testAssetURL.path) else {
            throw XCTSkip("Test asset not available")
        }

        let (project, _) = try await createProjectWithClip()
        let cases: [SaneExportSettings.ExportResolution] = [.hd1080, .hd720]

        for resolution in cases {
            var settings = SaneExportSettings()
            settings.resolution = resolution
            let (exportedAsset, _) = try await export(project, settings: settings)
            let dimensions = try await getVideoDimensions(from: exportedAsset)

            let expected = resolution.size
            let matchesLandscape = abs(dimensions.width - expected.width) < 2
                && abs(dimensions.height - expected.height) < 2
            let matchesPortrait = abs(dimensions.width - expected.height) < 2
                && abs(dimensions.height - expected.width) < 2

            XCTAssertTrue(
                matchesLandscape || matchesPortrait,
                "Expected \(resolution.rawValue), got \(dimensions.width)x\(dimensions.height)"
            )
        }
    }

    // MARK: - Codec Tests

    @MainActor
    func testExportUsesRequestedCodec() async throws {
        guard FileManager.default.fileExists(atPath: testAssetURL.path) else {
            throw XCTSkip("Test asset not available")
        }

        let (project, _) = try await createProjectWithClip()
        let cases: [(AVVideoCodecType, CMVideoCodecType)] = [
            (.h264, kCMVideoCodecType_H264),
            (.hevc, kCMVideoCodecType_HEVC)
        ]

        for (codec, expectedSubtype) in cases {
            var settings = SaneExportSettings()
            settings.codec = codec
            let (exportedAsset, _) = try await export(project, settings: settings)

            guard let track = try await exportedAsset.loadTracks(withMediaType: .video).first,
                  let format = try await track.load(.formatDescriptions).first else {
                throw TestError.noVideoTrack
            }
            XCTAssertEqual(
                CMFormatDescriptionGetMediaSubType(format),
                expectedSubtype,
                "Export with \(codec.rawValue) wrote the wrong codec"
            )
        }
    }

    // MARK: - Helper Types

    enum TestError: Error {
        case projectNotCreated
        case noVideoTrack
        case exportFailed
    }
}
