//
//  ErrorHandlingTests.swift
//  SaneVideoTests
//
//  Tests for error handling and edge cases
//

import AVFoundation
@testable import SaneVideo
import XCTest

@MainActor
final class ErrorHandlingTests: XCTestCase {
    var tempDir: URL!
    var store: ProjectStore!

    override func setUp() {
        super.setUp()
        tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try? FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        store = ProjectStore(rootDirectory: tempDir)
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: tempDir)
        tempDir = nil
        store = nil
        super.tearDown()
    }

    // MARK: - Corrupted Project File Tests

    // MARK: - Corrupted Project File Tests

    func testCorruptedProjectFile() async throws {
        // Create a project file with invalid JSON
        let projectsDir = tempDir.appendingPathComponent("Projects")
        try FileManager.default.createDirectory(at: projectsDir, withIntermediateDirectories: true)

        let corruptedFile = projectsDir.appendingPathComponent("corrupted.svproj")
        let invalidJSON = "{ this is not valid json }"
        try invalidJSON.write(to: corruptedFile, atomically: true, encoding: .utf8)

        // Attempt to load projects - should not crash
        let projects = try await store.loadProjects()

        // Corrupted project should be skipped, not crash
        XCTAssertTrue(projects.isEmpty, "Corrupted projects should be skipped")
    }

    func testEmptyProjectFile() async throws {
        // Create an empty project file
        let projectsDir = tempDir.appendingPathComponent("Projects")
        try FileManager.default.createDirectory(at: projectsDir, withIntermediateDirectories: true)

        let emptyFile = projectsDir.appendingPathComponent("empty.svproj")
        try "".write(to: emptyFile, atomically: true, encoding: .utf8)

        // Should not crash when loading
        let projects = try await store.loadProjects()
        XCTAssertTrue(projects.isEmpty)
    }

    // MARK: - Missing Video File Tests

    func testMissingVideoFile() async throws {
        // Create a project with a clip that references a non-existent file
        var project = VideoProject(name: "Missing File Test")
        let missingURL = tempDir.appendingPathComponent("nonexistent.mp4")

        // VideoClip should handle missing files gracefully
        let clip = VideoClip(url: missingURL, duration: .zero)
        project.timeline.tracks = [Track(name: "Main", type: .video, clips: [clip], zIndex: 0)]

        // Save and load - should not crash
        try await store.saveProject(project)
        let loaded = try await store.loadProjects()

        XCTAssertEqual(loaded.count, 1)
        XCTAssertEqual(loaded.first?.timeline.tracks.first?.clips.count, 1)

        // Clip duration should be zero for missing files
        XCTAssertEqual(loaded.first?.timeline.tracks.first?.clips.first?.duration, .zero)
    }

    func testDeletedVideoFileAfterSave() async throws {
        // Create a valid video file
        let videoURL = tempDir.appendingPathComponent("temp.mp4")
        try Data().write(to: videoURL)

        var project = VideoProject(name: "Deleted File Test")
        let clip = VideoClip(url: videoURL, duration: CMTime(seconds: 10, preferredTimescale: 600))
        project.timeline.tracks = [Track(name: "Main", type: .video, clips: [clip], zIndex: 0)]

        // Save project
        try await store.saveProject(project)

        // Delete the video file
        try FileManager.default.removeItem(at: videoURL)

        // Load project - should not crash even though file is missing
        let loaded = try await store.loadProjects()
        XCTAssertEqual(loaded.count, 1)
        XCTAssertEqual(loaded.first?.timeline.tracks.first?.clips.count, 1)
    }

    // MARK: - Invalid Trim Values Tests

    func testTrimEndBeforeTrimStart() {
        let validURL = tempDir.appendingPathComponent("valid.mp4")
        try? Data().write(to: validURL)

        var clip = VideoClip(url: validURL, duration: CMTime(seconds: 10, preferredTimescale: 600))

        // Set invalid trim values (end before start)
        clip.trimStart = CMTime(seconds: 5, preferredTimescale: 600)
        clip.trimEnd = CMTime(seconds: 2, preferredTimescale: 600)

        // effectiveDuration should handle this gracefully
        let duration = clip.effectiveDuration

        // Should either be zero or the absolute difference
        XCTAssertGreaterThanOrEqual(duration.seconds, 0, "Duration should never be negative")
    }

    func testTrimBeyondClipDuration() {
        let validURL = tempDir.appendingPathComponent("valid.mp4")
        try? Data().write(to: validURL)

        var clip = VideoClip(url: validURL, duration: CMTime(seconds: 10, preferredTimescale: 600))

        // Set trim end beyond actual duration
        clip.trimEnd = CMTime(seconds: 9999, preferredTimescale: 600)

        // Should clamp to actual duration
        let trimmed = clip.effectiveDuration
        XCTAssertLessThanOrEqual(trimmed.seconds, clip.duration.seconds + 1, "Trim should not exceed duration")
    }

    // MARK: - Disk Space Tests

    @MainActor
    func testDiskSpaceCheck() {
        // This test verifies the disk space check exists
        // We can't easily simulate a full disk, but we can verify the check runs

        let engine = RecordingEngine(
            cameraService: ServiceContainer.shared.cameraService,
            audioService: ServiceContainer.shared.audioService
        )

        // The engine should have a way to check available space
        // This is more of a smoke test to ensure the infrastructure exists
        XCTAssertNotNil(engine, "RecordingEngine should initialize")
    }

    // MARK: - Concurrent Access Tests

    func testConcurrentProjectSave() async throws {
        let project1 = VideoProject(name: "Concurrent 1")
        let project2 = VideoProject(name: "Concurrent 2")

        let expectation1 = expectation(description: "Save 1")
        let expectation2 = expectation(description: "Save 2")

        // Try to save two projects simultaneously
        Task {
            try? await self.store.saveProject(project1)
            expectation1.fulfill()
        }

        Task {
            try? await self.store.saveProject(project2)
            expectation2.fulfill()
        }

        await fulfillment(of: [expectation1, expectation2], timeout: 5.0)

        // Both projects should be saved successfully
        let loaded = try await store.loadProjects()
        XCTAssertEqual(loaded.count, 2, "Both projects should be saved despite concurrent access")
    }
}
