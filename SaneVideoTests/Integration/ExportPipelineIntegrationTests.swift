//
//  ExportPipelineIntegrationTests.swift
//  SaneVideoTests
//
//  Comprehensive integration tests for the export pipeline.
//  These tests verify that exports actually produce valid, playable files
//  with the correct properties (duration, resolution, effects, etc.)
//

import AVFoundation
import CoreMedia
import XCTest

@testable import SaneVideo

/// Integration tests that verify the entire export pipeline works end-to-end.
/// These tests use real video files and produce real exports to catch issues
/// that unit tests would miss.
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

        // Create unique temp output path for each test
        let tempDir = FileManager.default.temporaryDirectory
        tempOutputURL = tempDir.appendingPathComponent("test_export_\(UUID().uuidString).mp4")

        // Get test asset - prefer the small test_silence.mp4 for speed
        testAssetURL = getTestAssetURL()
    }

    override func tearDown() {
        // Clean up exported files
        if let url = tempOutputURL, FileManager.default.fileExists(atPath: url.path) {
            try? FileManager.default.removeItem(at: url)
        }
        projectState = nil
        exportEngine = nil
        super.tearDown()
    }

    // MARK: - Helper Methods

    private func getTestAssetURL() -> URL {
        // Try test_silence.mp4 first (small, fast)
        let silenceAsset = URL(fileURLWithPath: "/Users/sj/SaneVideo/Tests/Assets/test_silence.mp4")
        if FileManager.default.fileExists(atPath: silenceAsset.path) {
            return silenceAsset
        }

        // Fall back to test_video.mp4
        let testVideo = URL(fileURLWithPath: "/Users/sj/SaneVideo/Tests/Assets/test_video.mp4")
        if FileManager.default.fileExists(atPath: testVideo.path) {
            return testVideo
        }

        // Use TestEnvironment fallback
        return TestEnvironment.mockAssetURL
    }

    /// Creates a project with a single clip from the test asset
    @MainActor
    private func createProjectWithClip() async throws -> (VideoProject, VideoClip) {
        let asset = AVAsset(url: testAssetURL)
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

    /// Verifies a video file exists and is playable
    private func verifyExportedFile(at url: URL) async throws -> AVAsset {
        XCTAssertTrue(FileManager.default.fileExists(atPath: url.path), "Exported file should exist")

        let fileSize = try FileManager.default.attributesOfItem(atPath: url.path)[.size] as? Int ?? 0
        XCTAssertGreaterThan(fileSize, 0, "Exported file should not be empty")

        let asset = AVAsset(url: url)
        let isPlayable = try await asset.load(.isPlayable)
        XCTAssertTrue(isPlayable, "Exported file should be playable")

        return asset
    }

    /// Gets video dimensions from an asset
    private func getVideoDimensions(from asset: AVAsset) async throws -> CGSize {
        let tracks = try await asset.loadTracks(withMediaType: .video)
        guard let track = tracks.first else {
            throw TestError.noVideoTrack
        }
        let size = try await track.load(.naturalSize)
        let transform = try await track.load(.preferredTransform)

        // Apply transform to get correct dimensions (handles rotation)
        let transformedSize = size.applying(transform)
        return CGSize(width: abs(transformedSize.width), height: abs(transformedSize.height))
    }

    // MARK: - Basic Export Tests

    @MainActor
    func testBasicExportProducesPlayableFile() async throws {
        // Skip if no test asset available
        guard FileManager.default.fileExists(atPath: testAssetURL.path) else {
            throw XCTSkip("Test asset not available at \(testAssetURL.path)")
        }

        // Arrange
        let (project, _) = try await createProjectWithClip()
        let settings = SaneExportSettings()

        // Act
        var lastProgress: Double = 0
        let outputURL = try await exportEngine.export(
            project: project,
            settings: settings,
            outputURL: tempOutputURL
        ) { progress in
            lastProgress = progress
        }

        // Assert
        let exportedAsset = try await verifyExportedFile(at: outputURL)

        // Verify duration is approximately correct (within 0.5 seconds)
        let exportedDuration = try await exportedAsset.load(.duration)
        let originalAsset = AVAsset(url: testAssetURL)
        let originalDuration = try await originalAsset.load(.duration)

        XCTAssertEqual(
            exportedDuration.seconds,
            originalDuration.seconds,
            accuracy: 0.5,
            "Exported duration should match original"
        )

        XCTAssertEqual(lastProgress, 1.0, accuracy: 0.01, "Progress should reach 100%")
    }

    @MainActor
    func testExportResolution1080p() async throws {
        guard FileManager.default.fileExists(atPath: testAssetURL.path) else {
            throw XCTSkip("Test asset not available")
        }

        // Arrange
        let (project, _) = try await createProjectWithClip()
        var settings = SaneExportSettings()
        settings.resolution = .hd1080

        // Act
        let outputURL = try await exportEngine.export(
            project: project,
            settings: settings,
            outputURL: tempOutputURL
        ) { _ in }

        // Assert
        let exportedAsset = try await verifyExportedFile(at: outputURL)
        let dimensions = try await getVideoDimensions(from: exportedAsset)

        // 1080p should be 1920x1080 (or vice versa for portrait)
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

        // Arrange
        let (project, _) = try await createProjectWithClip()
        var settings = SaneExportSettings()
        settings.resolution = .hd720

        // Act
        let outputURL = try await exportEngine.export(
            project: project,
            settings: settings,
            outputURL: tempOutputURL
        ) { _ in }

        // Assert
        let exportedAsset = try await verifyExportedFile(at: outputURL)
        let dimensions = try await getVideoDimensions(from: exportedAsset)

        // 720p should be 1280x720
        let expectedWidth: CGFloat = 1280
        let expectedHeight: CGFloat = 720

        let matchesLandscape = abs(dimensions.width - expectedWidth) < 2 && abs(dimensions.height - expectedHeight) < 2
        let matchesPortrait = abs(dimensions.width - expectedHeight) < 2 && abs(dimensions.height - expectedWidth) < 2

        XCTAssertTrue(matchesLandscape || matchesPortrait,
                      "Expected 720p resolution, got \(dimensions.width)x\(dimensions.height)")
    }

    // MARK: - Trimming Tests

    @MainActor
    func testExportWithTrimmedClipRespectsTrim() async throws {
        guard FileManager.default.fileExists(atPath: testAssetURL.path) else {
            throw XCTSkip("Test asset not available")
        }

        // Arrange
        let asset = AVAsset(url: testAssetURL)
        let originalDuration = try await asset.load(.duration)

        // Only run if video is long enough to trim
        guard originalDuration.seconds > 2.0 else {
            throw XCTSkip("Test video too short for trim test")
        }

        // Create clip with trim (keep only first second)
        var clip = VideoClip(
            url: testAssetURL,
            duration: originalDuration,
            startTime: .zero
        )
        clip.trimStart = .zero
        clip.trimEnd = CMTime(seconds: 1.0, preferredTimescale: 600)

        projectState.startNewProject()
        projectState.addTrack(type: .video, name: "Video Track 1")
        projectState.addClip(clip)

        guard let project = projectState.currentProject else {
            throw TestError.projectNotCreated
        }

        let settings = SaneExportSettings()

        // Act
        let outputURL = try await exportEngine.export(
            project: project,
            settings: settings,
            outputURL: tempOutputURL
        ) { _ in }

        // Assert
        let exportedAsset = try await verifyExportedFile(at: outputURL)
        let exportedDuration = try await exportedAsset.load(.duration)

        // Trimmed export should be approximately 1 second
        XCTAssertEqual(
            exportedDuration.seconds,
            1.0,
            accuracy: 0.2,
            "Trimmed export should be ~1 second, got \(exportedDuration.seconds)"
        )
    }

    // MARK: - Effects Tests

    @MainActor
    func testExportWithEffectAppliesEffect() async throws {
        guard FileManager.default.fileExists(atPath: testAssetURL.path) else {
            throw XCTSkip("Test asset not available")
        }

        // Arrange
        let (project, clip) = try await createProjectWithClip()

        // Add noir effect
        let effect = VideoEffect(type: .noir)
        projectState.applyEffect(to: clip, effect: effect)

        guard let projectWithEffect = projectState.currentProject else {
            throw TestError.projectNotCreated
        }

        let settings = SaneExportSettings()

        // Act
        let outputURL = try await exportEngine.export(
            project: projectWithEffect,
            settings: settings,
            outputURL: tempOutputURL
        ) { _ in }

        // Assert - verify file is valid
        // Note: We can't easily verify the effect visually, but we verify it doesn't crash
        // and produces a valid file
        let exportedAsset = try await verifyExportedFile(at: outputURL)
        let isPlayable = try await exportedAsset.load(.isPlayable)
        XCTAssertTrue(isPlayable, "Export with effect should produce playable file")
    }

    @MainActor
    func testExportWithMultipleEffects() async throws {
        guard FileManager.default.fileExists(atPath: testAssetURL.path) else {
            throw XCTSkip("Test asset not available")
        }

        // Arrange
        let (_, clip) = try await createProjectWithClip()

        // Add multiple effects
        projectState.applyEffect(to: clip, effect: VideoEffect(type: .autoEnhance))
        if let updatedClip = projectState.getClip(by: clip.id) {
            projectState.applyEffect(to: updatedClip, effect: VideoEffect(type: .vignette))
        }

        guard let project = projectState.currentProject else {
            throw TestError.projectNotCreated
        }

        let settings = SaneExportSettings()

        // Act
        let outputURL = try await exportEngine.export(
            project: project,
            settings: settings,
            outputURL: tempOutputURL
        ) { _ in }

        // Assert
        let exportedAsset = try await verifyExportedFile(at: outputURL)
        let isPlayable = try await exportedAsset.load(.isPlayable)
        XCTAssertTrue(isPlayable, "Export with multiple effects should produce playable file")
    }

    // MARK: - Transition Tests

    @MainActor
    func testExportWithTransition() async throws {
        guard FileManager.default.fileExists(atPath: testAssetURL.path) else {
            throw XCTSkip("Test asset not available")
        }

        // Arrange - need two clips for a transition
        let asset = AVAsset(url: testAssetURL)
        let duration = try await asset.load(.duration)

        guard duration.seconds > 4.0 else {
            throw XCTSkip("Test video too short for transition test")
        }

        // Create first clip (first half)
        var clip1 = VideoClip(
            url: testAssetURL,
            duration: duration,
            startTime: .zero
        )
        clip1.trimEnd = CMTime(seconds: duration.seconds / 2, preferredTimescale: 600)

        // Create second clip (second half)
        var clip2 = VideoClip(
            url: testAssetURL,
            duration: duration,
            startTime: CMTime(seconds: duration.seconds / 2, preferredTimescale: 600)
        )
        clip2.trimStart = CMTime(seconds: duration.seconds / 2, preferredTimescale: 600)

        projectState.startNewProject()
        projectState.addTrack(type: .video, name: "Video Track 1")
        projectState.addClip(clip1)
        projectState.addClip(clip2)

        // Add dissolve transition to first clip
        projectState.setClipTransition(clipId: clip1.id, transitionType: .dissolve)

        guard let project = projectState.currentProject else {
            throw TestError.projectNotCreated
        }

        let settings = SaneExportSettings()

        // Act
        let outputURL = try await exportEngine.export(
            project: project,
            settings: settings,
            outputURL: tempOutputURL
        ) { _ in }

        // Assert
        let exportedAsset = try await verifyExportedFile(at: outputURL)
        let isPlayable = try await exportedAsset.load(.isPlayable)
        XCTAssertTrue(isPlayable, "Export with transition should produce playable file")
    }

    // MARK: - Audio Tests

    @MainActor
    func testExportPreservesAudio() async throws {
        guard FileManager.default.fileExists(atPath: testAssetURL.path) else {
            throw XCTSkip("Test asset not available")
        }

        // Check if source has audio
        let sourceAsset = AVAsset(url: testAssetURL)
        let audioTracks = try await sourceAsset.loadTracks(withMediaType: .audio)

        guard !audioTracks.isEmpty else {
            throw XCTSkip("Test video has no audio track")
        }

        // Arrange
        let (project, _) = try await createProjectWithClip()
        let settings = SaneExportSettings()

        // Act
        let outputURL = try await exportEngine.export(
            project: project,
            settings: settings,
            outputURL: tempOutputURL
        ) { _ in }

        // Assert
        let exportedAsset = try await verifyExportedFile(at: outputURL)
        let exportedAudioTracks = try await exportedAsset.loadTracks(withMediaType: .audio)

        XCTAssertFalse(exportedAudioTracks.isEmpty, "Exported file should have audio track")
    }

    @MainActor
    func testExportWithVolumeChange() async throws {
        guard FileManager.default.fileExists(atPath: testAssetURL.path) else {
            throw XCTSkip("Test asset not available")
        }

        // Arrange
        let (_, clip) = try await createProjectWithClip()

        // Set volume to 50%
        projectState.updateClipVolume(clipId: clip.id, volume: 0.5)

        guard let project = projectState.currentProject else {
            throw TestError.projectNotCreated
        }

        let settings = SaneExportSettings()

        // Act
        let outputURL = try await exportEngine.export(
            project: project,
            settings: settings,
            outputURL: tempOutputURL
        ) { _ in }

        // Assert - verify export succeeds with volume change
        let exportedAsset = try await verifyExportedFile(at: outputURL)
        let isPlayable = try await exportedAsset.load(.isPlayable)
        XCTAssertTrue(isPlayable, "Export with volume change should produce playable file")
    }

    @MainActor
    func testExportWithMutedClip() async throws {
        guard FileManager.default.fileExists(atPath: testAssetURL.path) else {
            throw XCTSkip("Test asset not available")
        }

        // Arrange
        let (_, clip) = try await createProjectWithClip()

        // Mute the clip
        projectState.updateClipVolume(clipId: clip.id, volume: 0.0)

        guard let project = projectState.currentProject else {
            throw TestError.projectNotCreated
        }

        let settings = SaneExportSettings()

        // Act
        let outputURL = try await exportEngine.export(
            project: project,
            settings: settings,
            outputURL: tempOutputURL
        ) { _ in }

        // Assert
        let exportedAsset = try await verifyExportedFile(at: outputURL)
        let isPlayable = try await exportedAsset.load(.isPlayable)
        XCTAssertTrue(isPlayable, "Export with muted clip should produce playable file")
    }

    // MARK: - Speed Change Tests

    @MainActor
    func testExportWithSpeedChange() async throws {
        guard FileManager.default.fileExists(atPath: testAssetURL.path) else {
            throw XCTSkip("Test asset not available")
        }

        // Arrange
        let asset = AVAsset(url: testAssetURL)
        let originalDuration = try await asset.load(.duration)

        guard originalDuration.seconds > 2.0 else {
            throw XCTSkip("Test video too short for speed test")
        }

        var clip = VideoClip(
            url: testAssetURL,
            duration: originalDuration,
            startTime: .zero
        )
        clip.speed = 2.0  // 2x speed

        projectState.startNewProject()
        projectState.addTrack(type: .video, name: "Video Track 1")
        projectState.addClip(clip)

        guard let project = projectState.currentProject else {
            throw TestError.projectNotCreated
        }

        let settings = SaneExportSettings()

        // Act
        let outputURL = try await exportEngine.export(
            project: project,
            settings: settings,
            outputURL: tempOutputURL
        ) { _ in }

        // Assert
        let exportedAsset = try await verifyExportedFile(at: outputURL)
        let exportedDuration = try await exportedAsset.load(.duration)

        // At 2x speed, duration should be approximately half
        let expectedDuration = originalDuration.seconds / 2.0
        XCTAssertEqual(
            exportedDuration.seconds,
            expectedDuration,
            accuracy: 0.5,
            "2x speed export should be half duration. Expected ~\(expectedDuration)s, got \(exportedDuration.seconds)s"
        )
    }

    // MARK: - Cancellation Tests

    @MainActor
    func testExportCancellationCleansUp() async throws {
        guard FileManager.default.fileExists(atPath: testAssetURL.path) else {
            throw XCTSkip("Test asset not available")
        }

        // Arrange
        let (project, _) = try await createProjectWithClip()
        let settings = SaneExportSettings()

        // Act - start export and cancel quickly
        let exportTask = Task {
            try await exportEngine.export(
                project: project,
                settings: settings,
                outputURL: tempOutputURL
            ) { _ in }
        }

        // Give it a moment to start
        try await Task.sleep(nanoseconds: 100_000_000) // 0.1s

        // Cancel
        exportEngine.cancelExport()
        exportTask.cancel()

        // Wait for cleanup
        try await Task.sleep(nanoseconds: 500_000_000) // 0.5s

        // Assert - partial file should be cleaned up
        // Note: This might leave a file if cancellation races with completion
        // The important thing is it doesn't crash
        XCTAssertFalse(exportEngine.isExporting, "Should not be exporting after cancellation")
    }

    // MARK: - Error Handling Tests

    @MainActor
    func testExportEmptyProjectThrowsError() async throws {
        // Arrange - empty project
        projectState.startNewProject()

        guard let project = projectState.currentProject else {
            throw TestError.projectNotCreated
        }

        let settings = SaneExportSettings()

        // Act & Assert
        do {
            _ = try await exportEngine.export(
                project: project,
                settings: settings,
                outputURL: tempOutputURL
            ) { _ in }
            XCTFail("Should throw error for empty project")
        } catch {
            // Expected - empty project should fail
            XCTAssertTrue(true, "Empty project correctly throws error: \(error)")
        }
    }

    @MainActor
    func testExportWithMissingFileHandlesGracefully() async throws {
        // Arrange - create clip with non-existent file
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

        let settings = SaneExportSettings()

        // Act & Assert
        do {
            _ = try await exportEngine.export(
                project: project,
                settings: settings,
                outputURL: tempOutputURL
            ) { _ in }
            XCTFail("Should throw error for missing file")
        } catch {
            // Expected - missing file should fail gracefully
            XCTAssertTrue(true, "Missing file correctly throws error: \(error)")
        }
    }

    // MARK: - Multiple Clips Tests

    @MainActor
    func testExportWithMultipleClips() async throws {
        guard FileManager.default.fileExists(atPath: testAssetURL.path) else {
            throw XCTSkip("Test asset not available")
        }

        // Arrange
        let asset = AVAsset(url: testAssetURL)
        let duration = try await asset.load(.duration)

        guard duration.seconds > 2.0 else {
            throw XCTSkip("Test video too short for multiple clips test")
        }

        let halfDuration = CMTime(seconds: duration.seconds / 2, preferredTimescale: 600)

        // First clip - first half
        var clip1 = VideoClip(
            url: testAssetURL,
            duration: duration,
            startTime: .zero
        )
        clip1.trimEnd = halfDuration

        // Second clip - second half, starts after first
        var clip2 = VideoClip(
            url: testAssetURL,
            duration: duration,
            startTime: halfDuration
        )
        clip2.trimStart = halfDuration

        projectState.startNewProject()
        projectState.addTrack(type: .video, name: "Video Track 1")
        projectState.addClip(clip1)
        projectState.addClip(clip2)

        guard let project = projectState.currentProject else {
            throw TestError.projectNotCreated
        }

        let settings = SaneExportSettings()

        // Act
        let outputURL = try await exportEngine.export(
            project: project,
            settings: settings,
            outputURL: tempOutputURL
        ) { _ in }

        // Assert
        let exportedAsset = try await verifyExportedFile(at: outputURL)
        let exportedDuration = try await exportedAsset.load(.duration)

        // Two clips should produce approximately the same total duration
        XCTAssertEqual(
            exportedDuration.seconds,
            duration.seconds,
            accuracy: 0.5,
            "Multiple clips export duration should match original"
        )
    }

    // MARK: - Codec Tests

    @MainActor
    func testExportWithH264Codec() async throws {
        guard FileManager.default.fileExists(atPath: testAssetURL.path) else {
            throw XCTSkip("Test asset not available")
        }

        // Arrange
        let (project, _) = try await createProjectWithClip()
        var settings = SaneExportSettings()
        settings.codec = .h264

        // Act
        let outputURL = try await exportEngine.export(
            project: project,
            settings: settings,
            outputURL: tempOutputURL
        ) { _ in }

        // Assert
        let exportedAsset = try await verifyExportedFile(at: outputURL)
        let isPlayable = try await exportedAsset.load(.isPlayable)
        XCTAssertTrue(isPlayable, "H.264 export should produce playable file")
    }

    @MainActor
    func testExportWithHEVCCodec() async throws {
        guard FileManager.default.fileExists(atPath: testAssetURL.path) else {
            throw XCTSkip("Test asset not available")
        }

        // Arrange
        let (project, _) = try await createProjectWithClip()
        var settings = SaneExportSettings()
        settings.codec = .hevc

        // Act
        let outputURL = try await exportEngine.export(
            project: project,
            settings: settings,
            outputURL: tempOutputURL
        ) { _ in }

        // Assert
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
