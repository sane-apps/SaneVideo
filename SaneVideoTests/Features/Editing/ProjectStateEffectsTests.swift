//
//  ProjectStateEffectsTests.swift
//  SaneVideoTests
//
//  Tests for ProjectState+Effects: transitions, effects application
//

import CoreMedia
import XCTest

@testable import SaneVideo

final class ProjectStateEffectsTests: XCTestCase {

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
        let tempURL = FileManager.default.temporaryDirectory.appendingPathComponent("test_effects.mp4")

        let clip = VideoClip(
            url: tempURL,
            duration: CMTime(seconds: 10, preferredTimescale: 600),
            startTime: .zero
        )

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

    // MARK: - Transition Tests

    @MainActor
    func testSetClipTransitionDissolve() {
        guard let clip = addTestClip() else {
            XCTFail("Failed to add test clip")
            return
        }

        // Default is no transition
        XCTAssertNil(clip.transition)

        projectState.setClipTransition(clipId: clip.id, transitionType: .dissolve)

        let updatedClip = projectState.getClip(by: clip.id)
        XCTAssertNotNil(updatedClip?.transition, "Transition should be set")
        XCTAssertEqual(updatedClip?.transition?.type, .dissolve)
    }

    @MainActor
    func testSetClipTransitionFadeToBlack() {
        guard let clip = addTestClip() else {
            XCTFail("Failed to add test clip")
            return
        }

        projectState.setClipTransition(clipId: clip.id, transitionType: .fadeToBlack)

        let updatedClip = projectState.getClip(by: clip.id)
        XCTAssertEqual(updatedClip?.transition?.type, .fadeToBlack)
    }

    @MainActor
    func testSetClipTransitionWipeRight() {
        guard let clip = addTestClip() else {
            XCTFail("Failed to add test clip")
            return
        }

        projectState.setClipTransition(clipId: clip.id, transitionType: .wipeRight)

        let updatedClip = projectState.getClip(by: clip.id)
        XCTAssertEqual(updatedClip?.transition?.type, .wipeRight)
    }

    @MainActor
    func testRemoveTransition() {
        guard let clip = addTestClip() else {
            XCTFail("Failed to add test clip")
            return
        }

        // First add a transition
        projectState.setClipTransition(clipId: clip.id, transitionType: .dissolve)
        XCTAssertNotNil(projectState.getClip(by: clip.id)?.transition)

        // Then remove it
        projectState.setClipTransition(clipId: clip.id, transitionType: .none)

        let updatedClip = projectState.getClip(by: clip.id)
        XCTAssertNil(updatedClip?.transition, "Transition should be removed")
    }

    @MainActor
    func testTransitionOnLockedTrack() {
        guard let clip = addTestClip() else {
            XCTFail("Failed to add test clip")
            return
        }

        // Lock the track
        if let track = projectState.currentProject?.timeline.tracks.first {
            projectState.toggleTrackLock(track)
        }

        // Try to set transition on locked track
        projectState.setClipTransition(clipId: clip.id, transitionType: .dissolve)

        // Should not be set
        let updatedClip = projectState.getClip(by: clip.id)
        XCTAssertNil(updatedClip?.transition, "Transition should not be set on locked track")
    }

    // MARK: - Effects Application Tests

    @MainActor
    func testApplyVideoEffect() {
        guard let clip = addTestClip() else {
            XCTFail("Failed to add test clip")
            return
        }

        let effect = VideoEffect(type: .autoEnhance)
        projectState.applyEffect(to: clip, effect: effect)

        let updatedClip = projectState.getClip(by: clip.id)
        XCTAssertTrue(updatedClip?.effects.contains(where: { $0.type == .autoEnhance }) ?? false,
                      "Auto enhance effect should be applied")
    }

    @MainActor
    func testApplyNoirEffect() {
        guard let clip = addTestClip() else {
            XCTFail("Failed to add test clip")
            return
        }

        let effect = VideoEffect(type: .noir)
        projectState.applyEffect(to: clip, effect: effect)

        let updatedClip = projectState.getClip(by: clip.id)
        XCTAssertTrue(updatedClip?.effects.contains(where: { $0.type == .noir }) ?? false,
                      "Noir effect should be applied")
    }

    @MainActor
    func testRemoveVideoEffect() {
        guard let clip = addTestClip() else {
            XCTFail("Failed to add test clip")
            return
        }

        // Add effect first
        let effect = VideoEffect(type: .autoEnhance)
        projectState.applyEffect(to: clip, effect: effect)

        // Get the updated clip with the effect applied
        guard let clipWithEffect = projectState.getClip(by: clip.id) else {
            XCTFail("Failed to get clip after applying effect")
            return
        }

        // Verify it was applied
        XCTAssertTrue(clipWithEffect.effects.contains(where: { $0.type == .autoEnhance }))

        // Remove it by type using the updated clip reference
        projectState.removeEffect(from: clipWithEffect, type: .autoEnhance)

        let updatedClip = projectState.getClip(by: clip.id)
        XCTAssertFalse(updatedClip?.effects.contains(where: { $0.type == .autoEnhance }) ?? true,
                       "Effect should be removed")
    }

    @MainActor
    func testClearAllEffects() {
        guard let clip = addTestClip() else {
            XCTFail("Failed to add test clip")
            return
        }

        // Add multiple effects
        projectState.applyEffect(to: clip, effect: VideoEffect(type: .autoEnhance))
        projectState.applyEffect(to: clip, effect: VideoEffect(type: .noir))

        XCTAssertGreaterThan(projectState.getClip(by: clip.id)?.effects.count ?? 0, 0)

        // Clear all effects
        projectState.clearEffects(from: clip)

        let updatedClip = projectState.getClip(by: clip.id)
        XCTAssertEqual(updatedClip?.effects.count, 0, "All effects should be cleared")
    }

    @MainActor
    func testUpdateClipEffects() {
        guard let clip = addTestClip() else {
            XCTFail("Failed to add test clip")
            return
        }

        let effects = [
            VideoEffect(type: .autoEnhance),
            VideoEffect(type: .sepia)
        ]

        projectState.updateClipEffects(clipId: clip.id, effects: effects)

        let updatedClip = projectState.getClip(by: clip.id)
        XCTAssertEqual(updatedClip?.effects.count, 2, "Should have 2 effects")
    }

    // MARK: - Keyframe Animation Tests

    @MainActor
    func testClipKeyframeAnimation() {
        guard let clip = addTestClip() else {
            XCTFail("Failed to add test clip")
            return
        }

        // Initially no keyframe animation
        XCTAssertNil(clip.keyframeAnimation)

        // Build keyframes
        var keyframes = KeyframeAnimation()
        keyframes.setKeyframe(property: .scale, at: .zero, value: 1.0)
        keyframes.setKeyframe(property: .scale, at: CMTime(seconds: 5, preferredTimescale: 600), value: 1.5)

        // Update clip with keyframes
        guard var project = projectState.currentProject,
              let trackIndex = project.timeline.tracks.firstIndex(where: { $0.clips.contains(where: { $0.id == clip.id }) }),
              let clipIndex = project.timeline.tracks[trackIndex].clips.firstIndex(where: { $0.id == clip.id }) else {
            XCTFail("Could not find clip")
            return
        }

        project.timeline.tracks[trackIndex].clips[clipIndex].keyframeAnimation = keyframes
        projectState.currentProject = project

        let updatedClip = projectState.getClip(by: clip.id)
        XCTAssertNotNil(updatedClip?.keyframeAnimation, "Keyframe animation should be set")
    }

    // MARK: - Operations During Processing Tests

    @MainActor
    func testTransitionBlockedDuringProcessing() {
        guard let clip = addTestClip() else {
            XCTFail("Failed to add test clip")
            return
        }

        // Start processing
        _ = projectState.beginTransaction()

        // Try to set transition
        projectState.setClipTransition(clipId: clip.id, transitionType: .dissolve)

        // Should be blocked
        let updatedClip = projectState.getClip(by: clip.id)
        XCTAssertNil(updatedClip?.transition, "Transition should be blocked during processing")

        projectState.cancelAllTransactions()
    }

    @MainActor
    func testTransitionAllowedWithTransactionId() {
        guard let clip = addTestClip() else {
            XCTFail("Failed to add test clip")
            return
        }

        let transactionId = projectState.beginTransaction()

        // Set transition with transaction ID
        projectState.setClipTransition(clipId: clip.id, transitionType: .dissolve, transactionId: transactionId)

        // Should be allowed
        let updatedClip = projectState.getClip(by: clip.id)
        XCTAssertNotNil(updatedClip?.transition, "Transition should be allowed with valid transaction ID")

        projectState.endTransaction(transactionId)
    }

    // MARK: - Overlay Tests

    @MainActor
    func testUpdateClipOverlay() {
        guard let clip = addTestClip() else {
            XCTFail("Failed to add test clip")
            return
        }

        // Default is no overlays
        XCTAssertTrue(clip.overlays.isEmpty)

        // Test that overlay can be added
        let overlay = VideoClip.VideoOverlay(
            text: "Test Overlay",
            startTime: 0.0,
            duration: 5.0,
            position: CGPoint(x: 0.5, y: 0.9)
        )

        projectState.updateClipOverlay(clipId: clip.id, overlay: overlay)

        let updatedClip = projectState.getClip(by: clip.id)
        XCTAssertFalse(updatedClip?.overlays.isEmpty ?? true, "Overlay should be added")
        XCTAssertEqual(updatedClip?.overlays.first?.text, "Test Overlay")
    }
}
