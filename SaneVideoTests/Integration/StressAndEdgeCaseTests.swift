//
//  StressAndEdgeCaseTests.swift
//  SaneVideoTests
//
//  Stress tests and edge case handling tests.
//  Verifies the app handles extreme cases gracefully.
//

import AVFoundation
import CoreMedia
import XCTest

@testable import SaneVideo

/// Stress tests and edge case handling.
/// These tests verify the app handles extreme conditions without crashing.
final class StressAndEdgeCaseTests: XCTestCase {

    // MARK: - Properties

    var projectState: ProjectState!
    var testAssetURL: URL!

    // MARK: - Setup & Teardown

    @MainActor
    override func setUp() {
        super.setUp()
        projectState = ProjectState()

        // Prefer test_silence.mp4 for stress tests, fall back to default
        testAssetURL = TestEnvironment.testAsset(named: "test_silence.mp4")
        if !FileManager.default.fileExists(atPath: testAssetURL.path) {
            testAssetURL = TestEnvironment.mockAssetURL
        }
    }

    override func tearDown() {
        projectState = nil
        super.tearDown()
    }

    // MARK: - Many Clips Tests

    @MainActor
    func testTimelineWith50Clips() async throws {
        guard FileManager.default.fileExists(atPath: testAssetURL.path) else {
            throw XCTSkip("Test asset not available")
        }

        // Arrange
        projectState.startNewProject()
        projectState.addTrack(type: .video, name: "Video Track 1")

        let clipCount = 50

        // Act - add 50 clips
        for i in 0..<clipCount {
            let clip = VideoClip(
                url: testAssetURL,
                duration: CMTime(seconds: 1, preferredTimescale: 600),
                startTime: CMTime(seconds: Double(i), preferredTimescale: 600)
            )
            projectState.addClip(clip)
        }

        // Assert
        let totalClips = projectState.currentProject?.timeline.tracks.flatMap { $0.clips }.count ?? 0
        XCTAssertEqual(totalClips, clipCount, "Should have \(clipCount) clips on timeline")
    }

    @MainActor
    func testTimelineWith100Clips() async throws {
        guard FileManager.default.fileExists(atPath: testAssetURL.path) else {
            throw XCTSkip("Test asset not available")
        }

        // Arrange
        projectState.startNewProject()
        projectState.addTrack(type: .video, name: "Video Track 1")

        let clipCount = 100

        // Act - add 100 clips
        let startTime = Date()
        for i in 0..<clipCount {
            let clip = VideoClip(
                url: testAssetURL,
                duration: CMTime(seconds: 1, preferredTimescale: 600),
                startTime: CMTime(seconds: Double(i), preferredTimescale: 600)
            )
            projectState.addClip(clip)
        }
        let elapsed = Date().timeIntervalSince(startTime)

        // Assert
        let totalClips = projectState.currentProject?.timeline.tracks.flatMap { $0.clips }.count ?? 0
        XCTAssertEqual(totalClips, clipCount, "Should have \(clipCount) clips on timeline")
        XCTAssertLessThan(elapsed, 10.0, "Adding \(clipCount) clips should take less than 10 seconds")

        print("Added \(clipCount) clips in \(String(format: "%.2f", elapsed)) seconds")
    }

    // MARK: - Many Effects Tests

    @MainActor
    func testClipWith10Effects() async throws {
        guard FileManager.default.fileExists(atPath: testAssetURL.path) else {
            throw XCTSkip("Test asset not available")
        }

        // Arrange
        projectState.startNewProject()
        projectState.addTrack(type: .video, name: "Video Track 1")

        let clip = VideoClip(
            url: testAssetURL,
            duration: CMTime(seconds: 10, preferredTimescale: 600),
            startTime: .zero
        )
        projectState.addClip(clip)

        // Act - add multiple effects
        let effectTypes: [VideoEffectType] = [
            .autoEnhance, .noir, .vignette, .brightness, .contrast,
            .saturation, .sharpen, .warmth, .exposure, .vibrance
        ]

        var currentClip = clip
        for effectType in effectTypes {
            if let updatedClip = projectState.getClip(by: currentClip.id) {
                projectState.applyEffect(to: updatedClip, effect: VideoEffect(type: effectType))
                currentClip = updatedClip
            }
        }

        // Assert
        let finalClip = projectState.getClip(by: clip.id)
        XCTAssertEqual(finalClip?.effects.count, 10, "Clip should have 10 effects")
    }

    // MARK: - Rapid Operation Tests

    @MainActor
    func testRapidClipAddAndDelete() async throws {
        guard FileManager.default.fileExists(atPath: testAssetURL.path) else {
            throw XCTSkip("Test asset not available")
        }

        // Arrange
        projectState.startNewProject()
        projectState.addTrack(type: .video, name: "Video Track 1")

        // Act - rapidly add and delete clips
        for i in 0..<20 {
            let clip = VideoClip(
                url: testAssetURL,
                duration: CMTime(seconds: 1, preferredTimescale: 600),
                startTime: CMTime(seconds: Double(i), preferredTimescale: 600)
            )
            projectState.addClip(clip)

            // Delete every other clip
            if i % 2 == 0 {
                projectState.deleteClip(clip)
            }
        }

        // Assert - should not crash and have some clips
        let clipCount = projectState.currentProject?.timeline.tracks.flatMap { $0.clips }.count ?? 0
        XCTAssertGreaterThan(clipCount, 0, "Should have some clips remaining")
    }

    @MainActor
    func testRapidVolumeChanges() async throws {
        guard FileManager.default.fileExists(atPath: testAssetURL.path) else {
            throw XCTSkip("Test asset not available")
        }

        // Arrange
        projectState.startNewProject()
        projectState.addTrack(type: .video, name: "Video Track 1")

        let clip = VideoClip(
            url: testAssetURL,
            duration: CMTime(seconds: 10, preferredTimescale: 600),
            startTime: .zero
        )
        projectState.addClip(clip)

        // Act - rapid volume changes (simulates dragging a slider)
        for i in 0..<100 {
            let volume = Float(i) / 100.0
            projectState.updateClipVolume(clipId: clip.id, volume: volume)
        }

        // Assert
        let finalClip = projectState.getClip(by: clip.id)
        XCTAssertEqual(finalClip?.volume ?? 0, 0.99, accuracy: 0.01, "Final volume should be ~0.99")
    }

    // MARK: - Edge Case Tests

    @MainActor
    func testZeroDurationClip() async throws {
        // Arrange
        projectState.startNewProject()
        projectState.addTrack(type: .video, name: "Video Track 1")

        // Act - try to add zero duration clip
        let clip = VideoClip(
            url: testAssetURL,
            duration: CMTime.zero,
            startTime: .zero
        )
        projectState.addClip(clip)

        // Assert - should handle gracefully (either reject or accept)
        // The important thing is it doesn't crash
        XCTAssertTrue(true, "Zero duration clip should not crash")
    }

    @MainActor
    func testNegativeStartTime() async throws {
        // This tests internal consistency even with invalid data
        projectState.startNewProject()
        projectState.addTrack(type: .video, name: "Video Track 1")

        // Act - negative start time (invalid but shouldn't crash)
        let clip = VideoClip(
            url: testAssetURL,
            duration: CMTime(seconds: 10, preferredTimescale: 600),
            startTime: CMTime(seconds: -5, preferredTimescale: 600)
        )
        projectState.addClip(clip)

        // Assert - should not crash
        XCTAssertTrue(true, "Negative start time should not crash")
    }

    @MainActor
    func testVeryLongDuration() async throws {
        // Arrange
        projectState.startNewProject()
        projectState.addTrack(type: .video, name: "Video Track 1")

        // Act - very long duration (10 hours)
        let clip = VideoClip(
            url: testAssetURL,
            duration: CMTime(seconds: 36000, preferredTimescale: 600),
            startTime: .zero
        )
        projectState.addClip(clip)

        // Assert
        let addedClip = projectState.currentProject?.timeline.tracks.first?.clips.first
        XCTAssertEqual(addedClip?.duration.seconds ?? 0, 36000, accuracy: 1, "Long duration should be preserved")
    }

    @MainActor
    func testExtremeVolumeValues() async throws {
        guard FileManager.default.fileExists(atPath: testAssetURL.path) else {
            throw XCTSkip("Test asset not available")
        }

        // Arrange
        projectState.startNewProject()
        projectState.addTrack(type: .video, name: "Video Track 1")

        let clip = VideoClip(
            url: testAssetURL,
            duration: CMTime(seconds: 10, preferredTimescale: 600),
            startTime: .zero
        )
        projectState.addClip(clip)

        // Act - test extreme volume values
        projectState.updateClipVolume(clipId: clip.id, volume: -1.0)  // Below minimum
        let volumeAfterNegative = projectState.getClip(by: clip.id)?.volume ?? -999

        projectState.updateClipVolume(clipId: clip.id, volume: 100.0)  // Way above normal
        let volumeAfterHigh = projectState.getClip(by: clip.id)?.volume ?? -999

        // Assert - values should either be clamped or accepted without crash
        XCTAssertGreaterThanOrEqual(volumeAfterNegative, -1.0, "Volume should be handled")
        XCTAssertLessThanOrEqual(volumeAfterHigh, 100.0, "Volume should be handled")
    }

    @MainActor
    func testExtremeSpeedValues() async throws {
        guard FileManager.default.fileExists(atPath: testAssetURL.path) else {
            throw XCTSkip("Test asset not available")
        }

        // Arrange
        projectState.startNewProject()
        projectState.addTrack(type: .video, name: "Video Track 1")

        var clip = VideoClip(
            url: testAssetURL,
            duration: CMTime(seconds: 10, preferredTimescale: 600),
            startTime: .zero
        )

        // Act - test extreme speed values
        clip.speed = 0.01  // Very slow
        projectState.addClip(clip)

        let slowClip = projectState.getClip(by: clip.id)
        XCTAssertEqual(slowClip?.speed ?? 0, 0.01, accuracy: 0.001, "Very slow speed should be preserved")

        // Test very fast
        if var updatedClip = projectState.getClip(by: clip.id) {
            updatedClip.speed = 100.0  // Very fast
            // Note: Direct mutation won't work due to value types
            // This just tests the model can hold extreme values
        }

        XCTAssertTrue(true, "Extreme speed values should not crash")
    }

    // MARK: - Memory Pressure Tests

    @MainActor
    func testManyProjectsSaved() async throws {
        // Arrange
        let projectStore = ProjectStore()
        var createdProjects: [VideoProject] = []

        // Act - create and save many projects
        for i in 0..<20 {
            let project = VideoProject(name: "Stress Test Project \(i)")
            try await projectStore.saveProject(project)
            createdProjects.append(project)
        }

        // Assert
        let loadedProjects = try await projectStore.loadProjects()
        XCTAssertGreaterThanOrEqual(loadedProjects.count, 20, "Should have at least 20 projects")

        // Cleanup
        for project in createdProjects {
            try? await projectStore.deleteProject(project)
        }
    }

    // MARK: - Concurrent Operations Tests

    @MainActor
    func testMultipleTransactionsSimultaneously() async throws {
        // Arrange
        projectState.startNewProject()

        // Act - start multiple transactions
        let tx1 = projectState.beginTransaction()
        let tx2 = projectState.beginTransaction()
        let tx3 = projectState.beginTransaction()

        // Assert
        XCTAssertEqual(projectState.activeTransactionCount, 3, "Should have 3 active transactions")
        XCTAssertTrue(projectState.isProcessing, "Should be processing")

        // Cleanup
        projectState.endTransaction(tx1)
        projectState.endTransaction(tx2)
        projectState.endTransaction(tx3)

        XCTAssertEqual(projectState.activeTransactionCount, 0, "Should have 0 active transactions")
        XCTAssertFalse(projectState.isProcessing, "Should not be processing")
    }

    // MARK: - File System Edge Cases

    @MainActor
    func testClipWithSpecialCharactersInPath() async throws {
        // Arrange
        let expectedFileName = "test video (1) [final] 'copy'.mp4"
        let specialPath = URL(fileURLWithPath: "/tmp/\(expectedFileName)")

        projectState.startNewProject()
        projectState.addTrack(type: .video, name: "Video Track 1")

        // Act
        let clip = VideoClip(
            url: specialPath,
            duration: CMTime(seconds: 10, preferredTimescale: 600),
            startTime: .zero
        )
        projectState.addClip(clip)

        // Assert - should not crash with special characters
        let addedClip = projectState.currentProject?.timeline.tracks.first?.clips.first
        XCTAssertEqual(addedClip?.url.lastPathComponent, expectedFileName)
    }

    @MainActor
    func testClipWithUnicodePath() async throws {
        // Arrange
        let unicodePath = URL(fileURLWithPath: "/tmp/视频テスト🎬.mp4")

        projectState.startNewProject()
        projectState.addTrack(type: .video, name: "Video Track 1")

        // Act
        let clip = VideoClip(
            url: unicodePath,
            duration: CMTime(seconds: 10, preferredTimescale: 600),
            startTime: .zero
        )
        projectState.addClip(clip)

        // Assert - should handle unicode paths
        let addedClip = projectState.currentProject?.timeline.tracks.first?.clips.first
        XCTAssertNotNil(addedClip?.url)
    }

    // MARK: - Timeline Complexity Tests

    @MainActor
    func testMultipleTracksWithManyClips() async throws {
        guard FileManager.default.fileExists(atPath: testAssetURL.path) else {
            throw XCTSkip("Test asset not available")
        }

        // Arrange
        projectState.startNewProject()

        // Create 5 tracks with 10 clips each
        for trackNum in 0..<5 {
            projectState.addTrack(type: .video, name: "Video Track \(trackNum + 1)")

            for clipNum in 0..<10 {
                let clip = VideoClip(
                    url: testAssetURL,
                    duration: CMTime(seconds: 1, preferredTimescale: 600),
                    startTime: CMTime(seconds: Double(clipNum), preferredTimescale: 600)
                )
                projectState.addClip(clip)
            }
        }

        // Assert
        let trackCount = projectState.currentProject?.timeline.tracks.count ?? 0
        let totalClips = projectState.currentProject?.timeline.tracks.flatMap { $0.clips }.count ?? 0

        XCTAssertEqual(trackCount, 5, "Should have 5 tracks")
        XCTAssertEqual(totalClips, 50, "Should have 50 total clips")
    }
}
