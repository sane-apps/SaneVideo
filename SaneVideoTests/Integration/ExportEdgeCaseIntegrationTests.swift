//
//  ExportEdgeCaseIntegrationTests.swift
//  SaneVideoTests
//
//  Edge case export integration tests: trimming, speed, cancellation, errors.
//  Split from ExportPipelineIntegrationTests for maintainability.
//

import AVFoundation
import CoreMedia
import XCTest

@testable import SaneVideo

/// Integration tests for export edge cases.
final class ExportEdgeCaseIntegrationTests: XCTestCase {

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
        tempOutputURL = tempDir.appendingPathComponent("test_edge_export_\(UUID().uuidString).mp4")
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

    // MARK: - Trimming Tests

    @MainActor
    func testExportWithTrimmedClipRespectsTrim() async throws {
        guard FileManager.default.fileExists(atPath: testAssetURL.path) else {
            throw XCTSkip("Test asset not available")
        }

        let asset = AVURLAsset(url: testAssetURL)
        let originalDuration = try await asset.load(.duration)

        guard originalDuration.seconds > 2.0 else {
            throw XCTSkip("Test video too short for trim test")
        }

        var clip = VideoClip(url: testAssetURL, duration: originalDuration, startTime: .zero)
        clip.trimStart = .zero
        clip.trimEnd = CMTime(seconds: 1.0, preferredTimescale: 600)

        projectState.startNewProject()
        projectState.addTrack(type: .video, name: "Video Track 1")
        projectState.addClip(clip)

        guard let project = projectState.currentProject else {
            throw TestError.projectNotCreated
        }

        let outputURL = try await exportEngine.export(
            project: project,
            settings: SaneExportSettings(),
            outputURL: tempOutputURL
        ) { _ in }

        let exportedAsset = try await verifyExportedFile(at: outputURL)
        let exportedDuration = try await exportedAsset.load(.duration)

        XCTAssertEqual(
            exportedDuration.seconds,
            1.0,
            accuracy: 0.2,
            "Trimmed export should be ~1 second, got \(exportedDuration.seconds)"
        )
    }

    @MainActor
    func testTrimPointsRespectedExactFrameCount() async throws {
        guard FileManager.default.fileExists(atPath: testAssetURL.path) else {
            throw XCTSkip("Test asset not available")
        }

        let asset = AVURLAsset(url: testAssetURL)
        let originalDuration = try await asset.load(.duration)

        guard originalDuration.seconds > 3.0 else {
            throw XCTSkip("Test video too short for exact trim test")
        }

        let trimDuration = CMTime(seconds: 1.0, preferredTimescale: 600)

        var clip = VideoClip(url: testAssetURL, duration: originalDuration, startTime: .zero)
        clip.trimStart = .zero
        clip.trimEnd = trimDuration

        projectState.startNewProject()
        projectState.addTrack(type: .video, name: "Video Track 1")
        projectState.addClip(clip)

        guard let project = projectState.currentProject else {
            throw TestError.projectNotCreated
        }

        var settings = SaneExportSettings()
        settings.frameRate = 30.0

        let outputURL = try await exportEngine.export(
            project: project,
            settings: settings,
            outputURL: tempOutputURL
        ) { _ in }

        let exportedAsset = try await verifyExportedFile(at: outputURL)
        let exportedDuration = try await exportedAsset.load(.duration)

        let frameTolerance = 1.0 / settings.frameRate
        XCTAssertEqual(
            exportedDuration.seconds,
            1.0,
            accuracy: frameTolerance,
            "Trim should be exact to within 1 frame. Expected 1.0s ± \(frameTolerance), got \(exportedDuration.seconds)s"
        )
    }

    // MARK: - Speed Change Tests

    @MainActor
    func testExportWithSpeedChange() async throws {
        guard FileManager.default.fileExists(atPath: testAssetURL.path) else {
            throw XCTSkip("Test asset not available")
        }

        let asset = AVURLAsset(url: testAssetURL)
        let originalDuration = try await asset.load(.duration)

        guard originalDuration.seconds > 2.0 else {
            throw XCTSkip("Test video too short for speed test")
        }

        var clip = VideoClip(url: testAssetURL, duration: originalDuration, startTime: .zero)
        clip.speed = 2.0

        projectState.startNewProject()
        projectState.addTrack(type: .video, name: "Video Track 1")
        projectState.addClip(clip)

        guard let project = projectState.currentProject else {
            throw TestError.projectNotCreated
        }

        let outputURL = try await exportEngine.export(
            project: project,
            settings: SaneExportSettings(),
            outputURL: tempOutputURL
        ) { _ in }

        let exportedAsset = try await verifyExportedFile(at: outputURL)
        let exportedDuration = try await exportedAsset.load(.duration)

        let expectedDuration = originalDuration.seconds / 2.0
        XCTAssertEqual(
            exportedDuration.seconds,
            expectedDuration,
            accuracy: 0.5,
            "2x speed export should be half duration. Expected ~\(expectedDuration)s, got \(exportedDuration.seconds)s"
        )
    }

    // MARK: - Multiple Clips Tests

    @MainActor
    func testExportWithMultipleClips() async throws {
        guard FileManager.default.fileExists(atPath: testAssetURL.path) else {
            throw XCTSkip("Test asset not available")
        }

        let asset = AVURLAsset(url: testAssetURL)
        let duration = try await asset.load(.duration)

        guard duration.seconds > 2.0 else {
            throw XCTSkip("Test video too short for multiple clips test")
        }

        let halfDuration = CMTime(seconds: duration.seconds / 2, preferredTimescale: 600)

        var clip1 = VideoClip(url: testAssetURL, duration: duration, startTime: .zero)
        clip1.trimEnd = halfDuration

        var clip2 = VideoClip(url: testAssetURL, duration: duration, startTime: halfDuration)
        clip2.trimStart = halfDuration

        projectState.startNewProject()
        projectState.addTrack(type: .video, name: "Video Track 1")
        projectState.addClip(clip1)
        projectState.addClip(clip2)

        guard let project = projectState.currentProject else {
            throw TestError.projectNotCreated
        }

        let outputURL = try await exportEngine.export(
            project: project,
            settings: SaneExportSettings(),
            outputURL: tempOutputURL
        ) { _ in }

        let exportedAsset = try await verifyExportedFile(at: outputURL)
        let exportedDuration = try await exportedAsset.load(.duration)

        XCTAssertEqual(
            exportedDuration.seconds,
            duration.seconds,
            accuracy: 0.5,
            "Multiple clips export duration should match original"
        )
    }

    // MARK: - Cancellation Tests

    @MainActor
    func testExportCancellationCleansUp() async throws {
        guard FileManager.default.fileExists(atPath: testAssetURL.path) else {
            throw XCTSkip("Test asset not available")
        }

        let (project, _) = try await createProjectWithClip()

        let exportTask = Task {
            try await exportEngine.export(
                project: project,
                settings: SaneExportSettings(),
                outputURL: tempOutputURL
            ) { _ in }
        }

        try await Task.sleep(nanoseconds: 100_000_000)

        exportEngine.cancelExport()
        exportTask.cancel()

        try await Task.sleep(nanoseconds: 500_000_000)

        XCTAssertFalse(exportEngine.isExporting, "Should not be exporting after cancellation")
    }

    // MARK: - Error Handling Tests

    @MainActor
    func testExportEmptyProjectThrowsError() async throws {
        projectState.startNewProject()

        guard let project = projectState.currentProject else {
            throw TestError.projectNotCreated
        }

        do {
            _ = try await exportEngine.export(
                project: project,
                settings: SaneExportSettings(),
                outputURL: tempOutputURL
            ) { _ in }
            XCTFail("Should throw error for empty project")
        } catch {
            XCTAssertTrue(true, "Empty project correctly throws error: \(error)")
        }
    }

    @MainActor
    func testExportWithMissingFileHandlesGracefully() async throws {
        let fakeURL = URL(fileURLWithPath: "/nonexistent/fake_video.mp4")
        let clip = VideoClip(
            url: fakeURL,
            duration: CMTime(seconds: 10, preferredTimescale: 600),
            startTime: .zero
        )

        projectState.startNewProject()
        projectState.addTrack(type: .video, name: "Video Track 1")
        projectState.addClip(clip)

        guard let project = projectState.currentProject else {
            throw TestError.projectNotCreated
        }

        do {
            _ = try await exportEngine.export(
                project: project,
                settings: SaneExportSettings(),
                outputURL: tempOutputURL
            ) { _ in }
            XCTFail("Should throw error for missing file")
        } catch {
            XCTAssertTrue(true, "Missing file correctly throws error: \(error)")
        }
    }

    // MARK: - Frame Rate Tests

    @MainActor
    func testExportFrameRateMatchesSettings() async throws {
        guard FileManager.default.fileExists(atPath: testAssetURL.path) else {
            throw XCTSkip("Test asset not available")
        }

        let (project, _) = try await createProjectWithClip()
        var settings = SaneExportSettings()
        settings.frameRate = 30.0

        let outputURL = try await exportEngine.export(
            project: project,
            settings: settings,
            outputURL: tempOutputURL
        ) { _ in }

        let exportedAsset = try await verifyExportedFile(at: outputURL)
        let videoTracks = try await exportedAsset.loadTracks(withMediaType: .video)

        guard let videoTrack = videoTracks.first else {
            throw TestError.noVideoTrack
        }

        let nominalFrameRate = try await videoTrack.load(.nominalFrameRate)

        XCTAssertEqual(
            Double(nominalFrameRate),
            settings.frameRate,
            accuracy: 1.0,
            "Frame rate should match settings. Expected \(settings.frameRate), got \(nominalFrameRate)"
        )
    }

    // MARK: - Error Type

    enum TestError: Error {
        case projectNotCreated
        case noVideoTrack
    }
}
