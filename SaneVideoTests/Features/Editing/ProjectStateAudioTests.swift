//
//  ProjectStateAudioTests.swift
//  SaneVideoTests
//
//  Tests for ProjectState+Audio: volume, voice isolation, gating, silence/filler removal
//

import AVFoundation
import CoreMedia
import XCTest

@testable import SaneVideo

final class ProjectStateAudioTests: XCTestCase {

    var projectState: ProjectState!

    @MainActor
    override func setUp() {
        super.setUp()
        projectState = ProjectState()
        projectState.startNewProject()
        // Add a default video track for tests
        projectState.addTrack(type: .video, name: "Video Track 1")
    }

    override func tearDown() {
        projectState = nil
        super.tearDown()
    }

    // MARK: - Helper Methods

    @MainActor
    private func addTestClip() -> VideoClip? {
        // Create a mock clip
        let tempURL = FileManager.default.temporaryDirectory.appendingPathComponent("test_audio.mp4")

        let clip = VideoClip(
            url: tempURL,
            duration: CMTime(seconds: 10, preferredTimescale: 600),
            startTime: .zero
        )

        // Add to timeline
        guard var project = projectState.currentProject,
              !project.timeline.tracks.isEmpty else {
            return nil
        }

        var track = project.timeline.tracks[0]
        track.clips.append(clip)
        project.timeline.tracks[0] = track
        projectState.currentProject = project

        return clip
    }

    // MARK: - Volume Tests

    @MainActor
    func testUpdateClipVolume() {
        guard let clip = addTestClip() else {
            XCTFail("Failed to add test clip")
            return
        }

        // Default volume is 1.0
        XCTAssertEqual(clip.volume, 1.0, accuracy: 0.01)

        projectState.updateClipVolume(clipId: clip.id, volume: 0.5)

        // Verify volume was updated
        let updatedClip = projectState.getClip(by: clip.id)
        XCTAssertEqual(updatedClip?.volume ?? 0, 0.5, accuracy: 0.01)
    }

    @MainActor
    func testUpdateClipVolumeToZero() {
        guard let clip = addTestClip() else {
            XCTFail("Failed to add test clip")
            return
        }

        projectState.updateClipVolume(clipId: clip.id, volume: 0.0)

        let updatedClip = projectState.getClip(by: clip.id)
        XCTAssertEqual(updatedClip?.volume ?? 1, 0.0, accuracy: 0.01, "Volume should be muted")
    }

    @MainActor
    func testUpdateClipVolumeToMax() {
        guard let clip = addTestClip() else {
            XCTFail("Failed to add test clip")
            return
        }

        projectState.updateClipVolume(clipId: clip.id, volume: 2.0)

        let updatedClip = projectState.getClip(by: clip.id)
        XCTAssertEqual(updatedClip?.volume ?? 0, 2.0, accuracy: 0.01, "Volume should support boost")
    }

    @MainActor
    func testUpdateVolumeOnLockedTrack() {
        guard let clip = addTestClip() else {
            XCTFail("Failed to add test clip")
            return
        }

        // Lock the track
        if let track = projectState.currentProject?.timeline.tracks.first {
            projectState.toggleTrackLock(track)
        }

        let originalVolume = clip.volume

        // Try to update volume on locked track
        projectState.updateClipVolume(clipId: clip.id, volume: 0.5)

        // Volume should not change on locked track
        let updatedClip = projectState.getClip(by: clip.id)
        XCTAssertEqual(updatedClip?.volume ?? 0, originalVolume, accuracy: 0.01, "Volume should not change on locked track")
    }

    // MARK: - Voice Isolation Tests

    @MainActor
    func testUpdateClipVoiceIsolation() {
        guard let clip = addTestClip() else {
            XCTFail("Failed to add test clip")
            return
        }

        // Default is off
        XCTAssertFalse(clip.isVoiceIsolationEnabled)

        projectState.updateClipVoiceIsolation(clipId: clip.id, enabled: true)

        let updatedClip = projectState.getClip(by: clip.id)
        XCTAssertTrue(updatedClip?.isVoiceIsolationEnabled ?? false, "Voice isolation should be enabled")
    }

    @MainActor
    func testToggleVoiceIsolationOff() {
        guard let clip = addTestClip() else {
            XCTFail("Failed to add test clip")
            return
        }

        // Enable first
        projectState.updateClipVoiceIsolation(clipId: clip.id, enabled: true)
        XCTAssertTrue(projectState.getClip(by: clip.id)?.isVoiceIsolationEnabled ?? false)

        // Then disable
        projectState.updateClipVoiceIsolation(clipId: clip.id, enabled: false)

        let updatedClip = projectState.getClip(by: clip.id)
        XCTAssertFalse(updatedClip?.isVoiceIsolationEnabled ?? true, "Voice isolation should be disabled")
    }

    // MARK: - AI Gating Tests

    @MainActor
    func testUpdateClipGating() {
        guard let clip = addTestClip() else {
            XCTFail("Failed to add test clip")
            return
        }

        // Default is off
        XCTAssertFalse(clip.isGatingEnabled)

        projectState.updateClipGating(clipId: clip.id, enabled: true)

        let updatedClip = projectState.getClip(by: clip.id)
        XCTAssertTrue(updatedClip?.isGatingEnabled ?? false, "AI gating should be enabled")
    }

    @MainActor
    func testToggleGatingOff() {
        guard let clip = addTestClip() else {
            XCTFail("Failed to add test clip")
            return
        }

        // Enable first
        projectState.updateClipGating(clipId: clip.id, enabled: true)

        // Then disable
        projectState.updateClipGating(clipId: clip.id, enabled: false)

        let updatedClip = projectState.getClip(by: clip.id)
        XCTAssertFalse(updatedClip?.isGatingEnabled ?? true, "AI gating should be disabled")
    }

    // MARK: - Operations Blocked During Processing Tests

    @MainActor
    func testVolumeBlockedDuringProcessing() {
        guard let clip = addTestClip() else {
            XCTFail("Failed to add test clip")
            return
        }

        // Start a transaction (simulates processing)
        _ = projectState.beginTransaction()

        let originalVolume = clip.volume

        // Try to update volume while processing
        projectState.updateClipVolume(clipId: clip.id, volume: 0.5)

        // Should be blocked
        let updatedClip = projectState.getClip(by: clip.id)
        XCTAssertEqual(updatedClip?.volume ?? 0, originalVolume, accuracy: 0.01, "Volume update should be blocked during processing")

        projectState.cancelAllTransactions()
    }

    @MainActor
    func testVolumeAllowedWithTransactionId() {
        guard let clip = addTestClip() else {
            XCTFail("Failed to add test clip")
            return
        }

        let transactionId = projectState.beginTransaction()

        // Update volume with transaction ID
        projectState.updateClipVolume(clipId: clip.id, volume: 0.5, transactionId: transactionId)

        // Should be allowed
        let updatedClip = projectState.getClip(by: clip.id)
        XCTAssertEqual(updatedClip?.volume ?? 0, 0.5, accuracy: 0.01, "Volume update should be allowed with valid transaction ID")

        projectState.endTransaction(transactionId)
    }

    // MARK: - Get Clip Tests

    @MainActor
    func testGetClipById() {
        guard let clip = addTestClip() else {
            XCTFail("Failed to add test clip")
            return
        }

        let foundClip = projectState.getClip(by: clip.id)
        XCTAssertNotNil(foundClip, "Should find clip by ID")
        XCTAssertEqual(foundClip?.id, clip.id)
    }

    @MainActor
    func testGetClipByInvalidId() {
        let foundClip = projectState.getClip(by: UUID())
        XCTAssertNil(foundClip, "Should not find clip with invalid ID")
    }

    // MARK: - Multiple Clips Tests

    @MainActor
    func testUpdateVolumeCorrectClip() {
        guard let clip1 = addTestClip(),
              let clip2 = addTestClip() else {
            XCTFail("Failed to add test clips")
            return
        }

        projectState.updateClipVolume(clipId: clip1.id, volume: 0.3)
        projectState.updateClipVolume(clipId: clip2.id, volume: 0.7)

        let updatedClip1 = projectState.getClip(by: clip1.id)
        let updatedClip2 = projectState.getClip(by: clip2.id)

        XCTAssertEqual(updatedClip1?.volume ?? 0, 0.3, accuracy: 0.01, "Clip 1 should have volume 0.3")
        XCTAssertEqual(updatedClip2?.volume ?? 0, 0.7, accuracy: 0.01, "Clip 2 should have volume 0.7")
    }
}
