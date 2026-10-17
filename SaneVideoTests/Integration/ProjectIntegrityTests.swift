//
//  ProjectIntegrityTests.swift
//  SaneVideoTests
//
//  Verifies that every persisted project field survives a ProjectStore save/load cycle,
//  and that basic timeline clip operations change the clip count.
//

import AVFoundation
import CoreMedia
import Foundation
@testable import SaneVideo
import Testing

@Suite("Project Integrity")
struct ProjectIntegrityTests {
    private let clipURL = URL(fileURLWithPath: "/tmp/SaneVideoTests/integrity_clip.mp4")

    @Test("Save then load preserves every project, track and clip field")
    func complexProjectPreservesAllData() async throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("ProjectIntegrity_\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: root) }
        let store = ProjectStore(rootDirectory: root)

        var project = VideoProject(name: "Complex Project \(UUID().uuidString)")

        var videoTrack = Track(name: "Video 1", type: .video, zIndex: 0)
        videoTrack.isMuted = true
        var secondVideoTrack = Track(name: "Video 2", type: .video, zIndex: 1)
        secondVideoTrack.isLocked = true
        let audioTrack = Track(name: "Audio 1", type: .audio, zIndex: 2)

        var clip = VideoClip(
            url: clipURL,
            duration: CMTime(seconds: 10, preferredTimescale: 600),
            startTime: CMTime(seconds: 5, preferredTimescale: 600)
        )
        clip.volume = 0.8
        clip.speed = 1.5
        clip.trimStart = CMTime(seconds: 1, preferredTimescale: 600)
        clip.trimEnd = CMTime(seconds: 9, preferredTimescale: 600)
        clip.isVoiceIsolationEnabled = true
        clip.isGatingEnabled = true
        clip.effects = [VideoEffect(type: .noir), VideoEffect(type: .vignette, intensity: 0.7)]
        clip.transition = VideoTransition(type: .dissolve, duration: CMTime(seconds: 0.5, preferredTimescale: 600))
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

        videoTrack.clips.append(clip)
        project.timeline.tracks = [videoTrack, secondVideoTrack, audioTrack]

        try await store.saveProject(project)
        let loadedProjects = try await store.loadProjects()

        let loaded = try #require(loadedProjects.first { $0.id == project.id })
        #expect(loaded.name == project.name)

        let tracks = loaded.timeline.tracks
        #expect(tracks.map(\.name) == ["Video 1", "Video 2", "Audio 1"])
        #expect(tracks.map(\.type) == [.video, .video, .audio])
        #expect(tracks[0].isMuted)
        #expect(!tracks[0].isLocked)
        #expect(tracks[1].isLocked)
        #expect(!tracks[1].isMuted)

        let loadedClip = try #require(tracks.first?.clips.first)
        #expect(loadedClip.id == clip.id)
        #expect(abs(loadedClip.duration.seconds - 10) < 0.01)
        #expect(abs(loadedClip.startTime.seconds - 5) < 0.01)
        #expect(abs(loadedClip.volume - 0.8) < 0.01)
        #expect(abs(loadedClip.speed - 1.5) < 0.01)
        #expect(abs(loadedClip.trimStart.seconds - 1) < 0.01)
        #expect(abs(loadedClip.trimEnd.seconds - 9) < 0.01)
        #expect(loadedClip.isVoiceIsolationEnabled)
        #expect(loadedClip.isGatingEnabled)

        #expect(loadedClip.effects.map(\.type) == [.noir, .vignette])
        let vignette = try #require(loadedClip.effects.first { $0.type == .vignette })
        #expect(abs(vignette.intensity - 0.7) < 0.01)

        let transition = try #require(loadedClip.transition)
        #expect(transition.type == .dissolve)
        #expect(abs(transition.duration.seconds - 0.5) < 0.01)

        #expect(loadedClip.captions.map(\.text) == ["Hello world", "This is a test"])
        #expect(abs((loadedClip.captions.last?.startTime.seconds ?? -1) - 2) < 0.01)
        #expect(abs((loadedClip.captions.last?.endTime.seconds ?? -1) - 5) < 0.01)
    }

    @Test("Deleting a clip removes it from the timeline")
    @MainActor
    func deleteClipRemovesFromTimeline() {
        let state = ProjectState()
        state.startNewProject()
        state.addTrack(type: .video, name: "Video Track 1")

        let clip = VideoClip(
            url: clipURL,
            duration: CMTime(seconds: 10, preferredTimescale: 600),
            startTime: .zero
        )
        state.addClip(clip)
        #expect(state.currentProject?.timeline.tracks.flatMap(\.clips).count == 1)

        state.deleteClip(clip)

        #expect(state.currentProject?.timeline.tracks.flatMap(\.clips).isEmpty == true)
    }

    @Test("Adding five clips puts five clips on the timeline")
    @MainActor
    func addMultipleClipsToTimeline() {
        let state = ProjectState()
        state.startNewProject()
        state.addTrack(type: .video, name: "Video Track 1")

        for index in 0 ..< 5 {
            state.addClip(VideoClip(
                url: clipURL,
                duration: CMTime(seconds: 10, preferredTimescale: 600),
                startTime: CMTime(seconds: Double(index * 10), preferredTimescale: 600)
            ))
        }

        #expect(state.currentProject?.timeline.tracks.flatMap(\.clips).count == 5)
    }
}
