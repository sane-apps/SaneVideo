//
//  ProjectIntegrityTests.swift
//  SaneVideoTests
//
//  Integration tests for project data integrity.
//  Verifies that projects can be saved, loaded, and maintain all data correctly.
//

import AVFoundation
import CoreMedia
import XCTest

@testable import SaneVideo

/// Integration tests for project save/load integrity.
/// Verifies that all project data survives the save/load cycle.
final class ProjectIntegrityTests: XCTestCase {

    // MARK: - Properties

    var projectStore: ProjectStore!
    var projectState: ProjectState!
    var testAssetURL: URL!

    // MARK: - Setup & Teardown

    @MainActor
    override func setUp() {
        super.setUp()
        projectStore = ProjectStore()
        projectState = ProjectState()

        testAssetURL = URL(fileURLWithPath: "/Users/sj/SaneVideo/Tests/Assets/test_silence.mp4")
        if !FileManager.default.fileExists(atPath: testAssetURL.path) {
            testAssetURL = TestEnvironment.mockAssetURL
        }
    }

    override func tearDown() {
        projectStore = nil
        projectState = nil
        super.tearDown()
    }

    // MARK: - Basic Save/Load Tests

    func testProjectSaveAndLoadPreservesName() async throws {
        // Arrange
        let originalName = "Test Project \(UUID().uuidString)"
        var project = VideoProject(name: originalName)

        // Act
        try await projectStore.saveProject(project)
        let loadedProjects = try await projectStore.loadProjects()

        // Assert
        let loadedProject = loadedProjects.first { $0.id == project.id }
        XCTAssertNotNil(loadedProject, "Project should be found after save/load")
        XCTAssertEqual(loadedProject?.name, originalName, "Project name should be preserved")

        // Cleanup
        try? await projectStore.deleteProject(project)
    }

    func testProjectSaveAndLoadPreservesTimeline() async throws {
        // Arrange
        var project = VideoProject(name: "Timeline Test")
        let track = Track(name: "Video 1", type: .video, zIndex: 0)
        project.timeline.tracks.append(track)

        // Act
        try await projectStore.saveProject(project)
        let loadedProjects = try await projectStore.loadProjects()

        // Assert
        let loadedProject = loadedProjects.first { $0.id == project.id }
        XCTAssertNotNil(loadedProject)
        XCTAssertEqual(loadedProject?.timeline.tracks.count, 1, "Track count should be preserved")
        XCTAssertEqual(loadedProject?.timeline.tracks.first?.name, "Video 1", "Track name should be preserved")
        XCTAssertEqual(loadedProject?.timeline.tracks.first?.type, .video, "Track type should be preserved")

        // Cleanup
        try? await projectStore.deleteProject(project)
    }

    // MARK: - Clip Data Preservation Tests

    func testProjectPreservesClipData() async throws {
        // Arrange
        var project = VideoProject(name: "Clip Test")
        var track = Track(name: "Video 1", type: .video, zIndex: 0)

        let clip = VideoClip(
            url: testAssetURL,
            duration: CMTime(seconds: 10, preferredTimescale: 600),
            startTime: CMTime(seconds: 5, preferredTimescale: 600)
        )
        track.clips.append(clip)
        project.timeline.tracks.append(track)

        // Act
        try await projectStore.saveProject(project)
        let loadedProjects = try await projectStore.loadProjects()

        // Assert
        let loadedProject = loadedProjects.first { $0.id == project.id }
        let loadedClip = loadedProject?.timeline.tracks.first?.clips.first

        XCTAssertNotNil(loadedClip, "Clip should be preserved")
        XCTAssertEqual(loadedClip?.id, clip.id, "Clip ID should be preserved")
        XCTAssertEqual(loadedClip?.duration.seconds ?? -1, 10, accuracy: 0.01, "Duration should be preserved")
        XCTAssertEqual(loadedClip?.startTime.seconds ?? -1, 5, accuracy: 0.01, "Start time should be preserved")

        // Cleanup
        try? await projectStore.deleteProject(project)
    }

    func testProjectPreservesClipVolume() async throws {
        // Arrange
        var project = VideoProject(name: "Volume Test")
        var track = Track(name: "Video 1", type: .video, zIndex: 0)

        var clip = VideoClip(
            url: testAssetURL,
            duration: CMTime(seconds: 10, preferredTimescale: 600),
            startTime: .zero
        )
        clip.volume = 0.75

        track.clips.append(clip)
        project.timeline.tracks.append(track)

        // Act
        try await projectStore.saveProject(project)
        let loadedProjects = try await projectStore.loadProjects()

        // Assert
        let loadedClip = loadedProjects.first { $0.id == project.id }?.timeline.tracks.first?.clips.first
        XCTAssertEqual(loadedClip?.volume ?? 0, 0.75, accuracy: 0.01, "Volume should be preserved")

        // Cleanup
        try? await projectStore.deleteProject(project)
    }

    func testProjectPreservesClipSpeed() async throws {
        // Arrange
        var project = VideoProject(name: "Speed Test")
        var track = Track(name: "Video 1", type: .video, zIndex: 0)

        var clip = VideoClip(
            url: testAssetURL,
            duration: CMTime(seconds: 10, preferredTimescale: 600),
            startTime: .zero
        )
        clip.speed = 2.0

        track.clips.append(clip)
        project.timeline.tracks.append(track)

        // Act
        try await projectStore.saveProject(project)
        let loadedProjects = try await projectStore.loadProjects()

        // Assert
        let loadedClip = loadedProjects.first { $0.id == project.id }?.timeline.tracks.first?.clips.first
        XCTAssertEqual(loadedClip?.speed ?? 0, 2.0, accuracy: 0.01, "Speed should be preserved")

        // Cleanup
        try? await projectStore.deleteProject(project)
    }

    func testProjectPreservesTrimPoints() async throws {
        // Arrange
        var project = VideoProject(name: "Trim Test")
        var track = Track(name: "Video 1", type: .video, zIndex: 0)

        var clip = VideoClip(
            url: testAssetURL,
            duration: CMTime(seconds: 10, preferredTimescale: 600),
            startTime: .zero
        )
        clip.trimStart = CMTime(seconds: 2, preferredTimescale: 600)
        clip.trimEnd = CMTime(seconds: 8, preferredTimescale: 600)

        track.clips.append(clip)
        project.timeline.tracks.append(track)

        // Act
        try await projectStore.saveProject(project)
        let loadedProjects = try await projectStore.loadProjects()

        // Assert
        let loadedClip = loadedProjects.first { $0.id == project.id }?.timeline.tracks.first?.clips.first
        XCTAssertEqual(loadedClip?.trimStart.seconds ?? 0, 2.0, accuracy: 0.01, "Trim start should be preserved")
        XCTAssertEqual(loadedClip?.trimEnd.seconds ?? 0, 8.0, accuracy: 0.01, "Trim end should be preserved")

        // Cleanup
        try? await projectStore.deleteProject(project)
    }

    // MARK: - Effects Preservation Tests

    func testProjectPreservesVideoEffects() async throws {
        // Arrange
        var project = VideoProject(name: "Effects Test")
        var track = Track(name: "Video 1", type: .video, zIndex: 0)

        var clip = VideoClip(
            url: testAssetURL,
            duration: CMTime(seconds: 10, preferredTimescale: 600),
            startTime: .zero
        )
        clip.effects = [
            VideoEffect(type: .noir),
            VideoEffect(type: .vignette, intensity: 0.7)
        ]

        track.clips.append(clip)
        project.timeline.tracks.append(track)

        // Act
        try await projectStore.saveProject(project)
        let loadedProjects = try await projectStore.loadProjects()

        // Assert
        let loadedClip = loadedProjects.first { $0.id == project.id }?.timeline.tracks.first?.clips.first
        XCTAssertEqual(loadedClip?.effects.count, 2, "Effect count should be preserved")

        let noirEffect = loadedClip?.effects.first { $0.type == .noir }
        XCTAssertNotNil(noirEffect, "Noir effect should be preserved")

        let vignetteEffect = loadedClip?.effects.first { $0.type == .vignette }
        XCTAssertNotNil(vignetteEffect, "Vignette effect should be preserved")
        XCTAssertEqual(vignetteEffect?.intensity ?? 0, 0.7, accuracy: 0.01, "Effect intensity should be preserved")

        // Cleanup
        try? await projectStore.deleteProject(project)
    }

    func testProjectPreservesTransitions() async throws {
        // Arrange
        var project = VideoProject(name: "Transition Test")
        var track = Track(name: "Video 1", type: .video, zIndex: 0)

        var clip = VideoClip(
            url: testAssetURL,
            duration: CMTime(seconds: 10, preferredTimescale: 600),
            startTime: .zero
        )
        clip.transition = VideoTransition(type: .dissolve, duration: CMTime(seconds: 1, preferredTimescale: 600))

        track.clips.append(clip)
        project.timeline.tracks.append(track)

        // Act
        try await projectStore.saveProject(project)
        let loadedProjects = try await projectStore.loadProjects()

        // Assert
        let loadedClip = loadedProjects.first { $0.id == project.id }?.timeline.tracks.first?.clips.first
        XCTAssertNotNil(loadedClip?.transition, "Transition should be preserved")
        XCTAssertEqual(loadedClip?.transition?.type, .dissolve, "Transition type should be preserved")
        XCTAssertEqual(loadedClip?.transition?.duration.seconds ?? 0, 1.0, accuracy: 0.01, "Transition duration should be preserved")

        // Cleanup
        try? await projectStore.deleteProject(project)
    }

    // MARK: - Captions Preservation Tests

    func testProjectPreservesCaptions() async throws {
        // Arrange
        var project = VideoProject(name: "Caption Test")
        var track = Track(name: "Video 1", type: .video, zIndex: 0)

        var clip = VideoClip(
            url: testAssetURL,
            duration: CMTime(seconds: 10, preferredTimescale: 600),
            startTime: .zero
        )
        clip.captions = [
            Caption(
                text: "Hello world",
                startTime: CMTime(seconds: 0, preferredTimescale: 600),
                endTime: CMTime(seconds: 2, preferredTimescale: 600)
            ),
            Caption(
                text: "This is a test",
                startTime: CMTime(seconds: 2, preferredTimescale: 600),
                endTime: CMTime(seconds: 5, preferredTimescale: 600)
            )
        ]

        track.clips.append(clip)
        project.timeline.tracks.append(track)

        // Act
        try await projectStore.saveProject(project)
        let loadedProjects = try await projectStore.loadProjects()

        // Assert
        let loadedClip = loadedProjects.first { $0.id == project.id }?.timeline.tracks.first?.clips.first
        XCTAssertEqual(loadedClip?.captions.count, 2, "Caption count should be preserved")

        let firstCaption = loadedClip?.captions.first
        XCTAssertEqual(firstCaption?.text, "Hello world", "Caption text should be preserved")
        XCTAssertEqual(firstCaption?.startTime.seconds ?? -1, 0.0, accuracy: 0.01, "Caption start time should be preserved")

        // Cleanup
        try? await projectStore.deleteProject(project)
    }

    // MARK: - Audio Settings Preservation Tests

    func testProjectPreservesVoiceIsolationSetting() async throws {
        // Arrange
        var project = VideoProject(name: "Voice Isolation Test")
        var track = Track(name: "Video 1", type: .video, zIndex: 0)

        var clip = VideoClip(
            url: testAssetURL,
            duration: CMTime(seconds: 10, preferredTimescale: 600),
            startTime: .zero
        )
        clip.isVoiceIsolationEnabled = true

        track.clips.append(clip)
        project.timeline.tracks.append(track)

        // Act
        try await projectStore.saveProject(project)
        let loadedProjects = try await projectStore.loadProjects()

        // Assert
        let loadedClip = loadedProjects.first { $0.id == project.id }?.timeline.tracks.first?.clips.first
        XCTAssertTrue(loadedClip?.isVoiceIsolationEnabled ?? false, "Voice isolation setting should be preserved")

        // Cleanup
        try? await projectStore.deleteProject(project)
    }

    func testProjectPreservesGatingSetting() async throws {
        // Arrange
        var project = VideoProject(name: "Gating Test")
        var track = Track(name: "Video 1", type: .video, zIndex: 0)

        var clip = VideoClip(
            url: testAssetURL,
            duration: CMTime(seconds: 10, preferredTimescale: 600),
            startTime: .zero
        )
        clip.isGatingEnabled = true

        track.clips.append(clip)
        project.timeline.tracks.append(track)

        // Act
        try await projectStore.saveProject(project)
        let loadedProjects = try await projectStore.loadProjects()

        // Assert
        let loadedClip = loadedProjects.first { $0.id == project.id }?.timeline.tracks.first?.clips.first
        XCTAssertTrue(loadedClip?.isGatingEnabled ?? false, "Gating setting should be preserved")

        // Cleanup
        try? await projectStore.deleteProject(project)
    }

    // MARK: - Clip Operations Tests

    @MainActor
    func testDeleteClipRemovesFromTimeline() async throws {
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

        // Get clip count before delete
        let clipsBeforeDelete = projectState.currentProject?.timeline.tracks.flatMap { $0.clips }.count ?? 0
        XCTAssertEqual(clipsBeforeDelete, 1, "Should have 1 clip before delete")

        // Act - delete clip
        projectState.deleteClip(clip)

        // Assert
        let clipsAfterDelete = projectState.currentProject?.timeline.tracks.flatMap { $0.clips }.count ?? 0
        XCTAssertEqual(clipsAfterDelete, 0, "Should have 0 clips after delete")
    }

    @MainActor
    func testAddMultipleClipsToTimeline() async throws {
        guard FileManager.default.fileExists(atPath: testAssetURL.path) else {
            throw XCTSkip("Test asset not available")
        }

        // Arrange
        projectState.startNewProject()
        projectState.addTrack(type: .video, name: "Video Track 1")

        // Act - add multiple clips
        for i in 0..<5 {
            let clip = VideoClip(
                url: testAssetURL,
                duration: CMTime(seconds: 10, preferredTimescale: 600),
                startTime: CMTime(seconds: Double(i * 10), preferredTimescale: 600)
            )
            projectState.addClip(clip)
        }

        // Assert
        let clipCount = projectState.currentProject?.timeline.tracks.flatMap { $0.clips }.count ?? 0
        XCTAssertEqual(clipCount, 5, "Should have 5 clips after adding")
    }

    // MARK: - Multiple Tracks Tests

    func testProjectPreservesMultipleTracks() async throws {
        // Arrange
        var project = VideoProject(name: "Multi Track Test")
        project.timeline.tracks = [
            Track(name: "Video 1", type: .video, zIndex: 0),
            Track(name: "Video 2", type: .video, zIndex: 1),
            Track(name: "Audio 1", type: .audio, zIndex: 2)
        ]

        // Act
        try await projectStore.saveProject(project)
        let loadedProjects = try await projectStore.loadProjects()

        // Assert
        let loadedProject = loadedProjects.first { $0.id == project.id }
        XCTAssertEqual(loadedProject?.timeline.tracks.count, 3, "All tracks should be preserved")

        let videoTracks = loadedProject?.timeline.tracks.filter { $0.type == .video }
        let audioTracks = loadedProject?.timeline.tracks.filter { $0.type == .audio }
        XCTAssertEqual(videoTracks?.count, 2, "Video tracks should be preserved")
        XCTAssertEqual(audioTracks?.count, 1, "Audio tracks should be preserved")

        // Cleanup
        try? await projectStore.deleteProject(project)
    }

    // MARK: - Track Properties Tests

    func testProjectPreservesTrackMuteState() async throws {
        // Arrange
        var project = VideoProject(name: "Mute Test")
        var track = Track(name: "Video 1", type: .video, zIndex: 0)
        track.isMuted = true
        project.timeline.tracks.append(track)

        // Act
        try await projectStore.saveProject(project)
        let loadedProjects = try await projectStore.loadProjects()

        // Assert
        let loadedTrack = loadedProjects.first { $0.id == project.id }?.timeline.tracks.first
        XCTAssertTrue(loadedTrack?.isMuted ?? false, "Track mute state should be preserved")

        // Cleanup
        try? await projectStore.deleteProject(project)
    }

    func testProjectPreservesTrackLockState() async throws {
        // Arrange
        var project = VideoProject(name: "Lock Test")
        var track = Track(name: "Video 1", type: .video, zIndex: 0)
        track.isLocked = true
        project.timeline.tracks.append(track)

        // Act
        try await projectStore.saveProject(project)
        let loadedProjects = try await projectStore.loadProjects()

        // Assert
        let loadedTrack = loadedProjects.first { $0.id == project.id }?.timeline.tracks.first
        XCTAssertTrue(loadedTrack?.isLocked ?? false, "Track lock state should be preserved")

        // Cleanup
        try? await projectStore.deleteProject(project)
    }

    // MARK: - Complex Project Tests

    func testComplexProjectPreservesAllData() async throws {
        // Arrange - create a complex project with multiple features
        var project = VideoProject(name: "Complex Project Test")

        // Multiple tracks
        var videoTrack = Track(name: "Video 1", type: .video, zIndex: 0)
        var audioTrack = Track(name: "Audio 1", type: .audio, zIndex: 1)

        // Clip with many properties
        var clip = VideoClip(
            url: testAssetURL,
            duration: CMTime(seconds: 10, preferredTimescale: 600),
            startTime: .zero
        )
        clip.volume = 0.8
        clip.speed = 1.5
        clip.trimStart = CMTime(seconds: 1, preferredTimescale: 600)
        clip.trimEnd = CMTime(seconds: 9, preferredTimescale: 600)
        clip.isVoiceIsolationEnabled = true
        clip.effects = [VideoEffect(type: .autoEnhance), VideoEffect(type: .vignette, intensity: 0.5)]
        clip.transition = VideoTransition(type: .dissolve, duration: CMTime(seconds: 0.5, preferredTimescale: 600))
        clip.captions = [
            Caption(
                text: "Test caption",
                startTime: CMTime(seconds: 2, preferredTimescale: 600),
                endTime: CMTime(seconds: 4, preferredTimescale: 600)
            )
        ]

        videoTrack.clips.append(clip)
        project.timeline.tracks = [videoTrack, audioTrack]

        // Act
        try await projectStore.saveProject(project)
        let loadedProjects = try await projectStore.loadProjects()

        // Assert
        let loadedProject = loadedProjects.first { $0.id == project.id }
        XCTAssertNotNil(loadedProject)

        let loadedClip = loadedProject?.timeline.tracks.first?.clips.first
        XCTAssertNotNil(loadedClip)

        // Verify all properties
        XCTAssertEqual(loadedClip?.volume ?? 0, 0.8, accuracy: 0.01)
        XCTAssertEqual(loadedClip?.speed ?? 0, 1.5, accuracy: 0.01)
        XCTAssertEqual(loadedClip?.trimStart.seconds ?? 0, 1.0, accuracy: 0.01)
        XCTAssertEqual(loadedClip?.trimEnd.seconds ?? 0, 9.0, accuracy: 0.01)
        XCTAssertTrue(loadedClip?.isVoiceIsolationEnabled ?? false)
        XCTAssertEqual(loadedClip?.effects.count, 2)
        XCTAssertNotNil(loadedClip?.transition)
        XCTAssertEqual(loadedClip?.captions.count, 1)

        // Cleanup
        try? await projectStore.deleteProject(project)
    }
}
