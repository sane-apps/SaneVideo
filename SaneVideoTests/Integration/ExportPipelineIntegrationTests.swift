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

    /// Returns a variety of test assets for more comprehensive testing
    private func getAllTestAssets() -> [URL] {
        let assetNames = [
            "IMG_6091.MOV",
            "test_silence.mp4",
            "IMG_0422.MOV",
            "IMG_7668.MOV"
        ]

        return assetNames.compactMap { name in
            let url = TestEnvironment.testAsset(named: name)
            return FileManager.default.fileExists(atPath: url.path) ? url : nil
        }
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

    @MainActor
    func testExportResolution1080p() async throws {
        guard FileManager.default.fileExists(atPath: testAssetURL.path) else {
            throw XCTSkip("Test asset not available")
        }

        let (project, _) = try await createProjectWithClip()
        var settings = SaneExportSettings()
        settings.resolution = .hd1080

        let outputURL = try await exportEngine.export(
            project: project,
            settings: settings,
            outputURL: tempOutputURL
        ) { _ in }

        let exportedAsset = try await verifyExportedFile(at: outputURL)
        let dimensions = try await getVideoDimensions(from: exportedAsset)

        let expectedWidth: CGFloat = 1920
        let expectedHeight: CGFloat = 1080

        let matchesLandscape = abs(dimensions.width - expectedWidth) < 2 && abs(dimensions.height - expectedHeight) < 2
        let matchesPortrait = abs(dimensions.width - expectedHeight) < 2 && abs(dimensions.height - expectedWidth) < 2

        XCTAssertTrue(matchesLandscape || matchesPortrait,
                      "Expected 1080p resolution, got \(dimensions.width)x\(dimensions.height)")
    }

    @MainActor
    func testExportResolution720p() async throws {
        guard FileManager.default.fileExists(atPath: testAssetURL.path) else {
            throw XCTSkip("Test asset not available")
        }

        let (project, _) = try await createProjectWithClip()
        var settings = SaneExportSettings()
        settings.resolution = .hd720

        let outputURL = try await exportEngine.export(
            project: project,
            settings: settings,
            outputURL: tempOutputURL
        ) { _ in }

        let exportedAsset = try await verifyExportedFile(at: outputURL)
        let dimensions = try await getVideoDimensions(from: exportedAsset)

        let expectedWidth: CGFloat = 1280
        let expectedHeight: CGFloat = 720

        let matchesLandscape = abs(dimensions.width - expectedWidth) < 2 && abs(dimensions.height - expectedHeight) < 2
        let matchesPortrait = abs(dimensions.width - expectedHeight) < 2 && abs(dimensions.height - expectedWidth) < 2

        XCTAssertTrue(matchesLandscape || matchesPortrait,
                      "Expected 720p resolution, got \(dimensions.width)x\(dimensions.height)")
    }

    // MARK: - Codec Tests

    @MainActor
    func testExportWithH264Codec() async throws {
        guard FileManager.default.fileExists(atPath: testAssetURL.path) else {
            throw XCTSkip("Test asset not available")
        }

        let (project, _) = try await createProjectWithClip()
        var settings = SaneExportSettings()
        settings.codec = .h264

        let outputURL = try await exportEngine.export(
            project: project,
            settings: settings,
            outputURL: tempOutputURL
        ) { _ in }

        let exportedAsset = try await verifyExportedFile(at: outputURL)
        let isPlayable = try await exportedAsset.load(.isPlayable)
        XCTAssertTrue(isPlayable, "H.264 export should produce playable file")
    }

    @MainActor
    func testExportWithHEVCCodec() async throws {
        guard FileManager.default.fileExists(atPath: testAssetURL.path) else {
            throw XCTSkip("Test asset not available")
        }

        let (project, _) = try await createProjectWithClip()
        var settings = SaneExportSettings()
        settings.codec = .hevc

        let outputURL = try await exportEngine.export(
            project: project,
            settings: settings,
            outputURL: tempOutputURL
        ) { _ in }

        let exportedAsset = try await verifyExportedFile(at: outputURL)
        let isPlayable = try await exportedAsset.load(.isPlayable)
        XCTAssertTrue(isPlayable, "HEVC export should produce playable file")
    }

    // MARK: - Helper Types

    enum TestError: Error {
        case projectNotCreated
        case noVideoTrack
        case exportFailed
    }
}
