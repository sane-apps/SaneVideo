// Regressions from the 2025-12-28 Magic Fix audit: cancellation, bad input, clip deletion mid-run,
// smooth-cut timing and enhanced-audio drift.

import AVFoundation
import CoreMedia
import Foundation
@testable import SaneVideo
import Testing

@Suite("Magic Fix Regression")
@MainActor
struct MagicFixRegressionTests {
    /// A project with one 10 s clip whose file is not a real video, so every analysis step fails fast.
    private func makeStateWithUnreadableClip() throws -> (ProjectState, VideoClip, URL) {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("test_clip_\(UUID().uuidString).mp4")
        try "test video content".write(to: url, atomically: true, encoding: .utf8)
        let clip = VideoClip(url: url, duration: CMTime(seconds: 10, preferredTimescale: 600), startTime: .zero)
        var project = VideoProject(name: "Test Project")
        project.timeline.tracks = [Track(name: "Test Track", type: .video, clips: [clip], zIndex: 0)]
        let state = ProjectState(projectStore: MockProjectStore())
        state.currentProject = project
        return (state, clip, url)
    }

    private func options(_ configure: (inout MagicFixOptions) -> Void) -> MagicFixOptions {
        var options = MagicFixOptions(
            removeSilence: false, removeFillers: false, generateCaptions: false,
            enhanceAudio: false, applyHighlightCursor: false, smoothJumpCuts: false
        )
        configure(&options)
        return options
    }

    @Test("Cancelled audio enhancement finishes instead of hanging", .timeLimit(.minutes(1)))
    func audioEnhancementCancellationFinishes() async throws {
        let (_, _, url) = try makeStateWithUnreadableClip()
        defer { try? FileManager.default.removeItem(at: url) }
        let service = SaneAudioEnhancementService()

        let task = Task { try await service.enhanceAudio(from: url) }
        task.cancel()

        await #expect(throws: (any Error).self) { _ = try await task.value }
    }

    @Test("Audio enhancement of a missing file throws")
    func audioEnhancementOfMissingFileThrows() async {
        let missing = FileManager.default.temporaryDirectory.appendingPathComponent("nonexistent_\(UUID().uuidString).m4a")

        await #expect(throws: (any Error).self) {
            _ = try await SaneAudioEnhancementService().enhanceAudio(from: missing)
        }
    }

    @Test("Magic Fix with enhancement on an unreadable clip finishes and adds no cuts", .timeLimit(.minutes(1)))
    func magicFixOnUnreadableClipFinishes() async throws {
        let (state, clip, url) = try makeStateWithUnreadableClip()
        defer { try? FileManager.default.removeItem(at: url) }

        await state.performMagicFix(for: clip, options: options { $0.enhanceAudio = true })

        #expect(state.getClip(by: clip.id)?.removedRanges.isEmpty == true)
    }

    @Test("Deleting a clip is refused while a Magic Fix transaction runs, and allowed after")
    func clipDeletionBlockedDuringTransaction() throws {
        let (state, clip, url) = try makeStateWithUnreadableClip()
        defer { try? FileManager.default.removeItem(at: url) }

        let transaction = state.beginTransaction()
        state.deleteClip(clip)
        #expect(state.getClip(by: clip.id) != nil)

        state.endTransaction(transaction)
        state.deleteClip(clip)
        #expect(state.getClip(by: clip.id) == nil)
    }

    @Test("Magic Fix on a clip already removed from the project finishes without changes", .timeLimit(.minutes(1)))
    func magicFixOnRemovedClipFinishes() async throws {
        let (state, clip, url) = try makeStateWithUnreadableClip()
        defer { try? FileManager.default.removeItem(at: url) }
        state.deleteClip(clip)

        await state.performMagicFix(for: clip, options: options { $0.removeSilence = true })

        #expect(state.currentProject?.clipCount == 0)
    }

    @Test(
        "Smooth-cut overlap is fixed in played time and scaled by speed in source time",
        arguments: [(1.0, 0.15), (2.0, 0.30), (0.5, 0.075)]
    )
    func smoothCutOverlapScalesWithSpeed(speed: Double, expectedSource: Double) {
        let overlap = TimeUtils.smoothCutOverlap(clipSpeed: speed, overlapPlayedSeconds: 0.15)

        #expect(abs(overlap.played.seconds - 0.15) < 0.000_1)
        #expect(abs(overlap.source.seconds - expectedSource) < 0.000_1)
    }

    @Test(
        "Enhanced audio is used only when its duration matches the clip",
        arguments: [(10.0, true), (10.04, true), (9.8, false)]
    )
    func enhancedAudioDurationAlignmentGuard(enhancedSeconds: Double, expected: Bool) {
        let result = AudioTrackBuilder.shouldUseEnhancedAudio(
            clipDuration: CMTime(seconds: 10, preferredTimescale: 600),
            enhancedDuration: CMTime(seconds: enhancedSeconds, preferredTimescale: 600)
        )

        #expect(result == expected)
    }
}
