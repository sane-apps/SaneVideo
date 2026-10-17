//
//  InspectorRegressionTests.swift
//  SaneVideoTests
//
//  Relinking a missing clip from Clip Info ("Locate File").
//

import CoreMedia
import Foundation
@testable import SaneVideo
import Testing

@Suite("Inspector Relink")
@MainActor
struct InspectorRegressionTests {
    private func makeTempFile(_ prefix: String) throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("\(prefix)_\(UUID().uuidString).mp4")
        try Data("test video content".utf8).write(to: url)
        return url
    }

    private func stateWithMissingClip(locked: Bool = false) -> (ProjectState, VideoClip) {
        var clip = VideoClip(
            url: FileManager.default.temporaryDirectory.appendingPathComponent("gone_\(UUID().uuidString).mp4"),
            duration: CMTime(seconds: 10, preferredTimescale: 600),
            startTime: .zero
        )
        clip.isMissing = true

        var track = Track(name: "Test Track", type: .video, clips: [clip], zIndex: 0)
        track.isLocked = locked
        var project = VideoProject(name: "Relink Project")
        project.timeline.tracks = [track]

        let state = ProjectState()
        state.currentProject = project
        return (state, clip)
    }

    @Test("Relinking a missing clip points it at the new file and clears missing")
    func relinkUpdatesURLAndClearsMissing() throws {
        let newFileURL = try makeTempFile("relinked")
        defer { try? FileManager.default.removeItem(at: newFileURL) }
        let (state, clip) = stateWithMissingClip()

        state.relinkClip(clip, to: newFileURL)

        let relinked = try #require(state.currentProject?.timeline.tracks[0].clips.first { $0.id == clip.id })
        #expect(relinked.url == newFileURL)
        #expect(!relinked.isMissing)
    }

    @Test("Relinking on a locked track changes nothing")
    func relinkIgnoredOnLockedTrack() throws {
        let newFileURL = try makeTempFile("relinked_locked")
        defer { try? FileManager.default.removeItem(at: newFileURL) }
        let (state, clip) = stateWithMissingClip(locked: true)

        state.relinkClip(clip, to: newFileURL)

        let unchanged = try #require(state.currentProject?.timeline.tracks[0].clips.first { $0.id == clip.id })
        #expect(unchanged.url == clip.url)
        #expect(unchanged.isMissing)
    }
}
