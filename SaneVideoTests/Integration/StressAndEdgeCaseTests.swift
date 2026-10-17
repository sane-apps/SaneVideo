// Large timelines and unusual inputs: the timeline must keep exact counts and
// contiguous clip placement. No wall-clock assertions.

import AVFoundation
import CoreMedia
import Foundation
@testable import SaneVideo
import Testing

@Suite("Stress and Edge Cases")
@MainActor
struct StressAndEdgeCaseTests {
    private let clipURL = URL(fileURLWithPath: "/tmp/SaneVideoTests/stress_clip.mp4")

    private func freshState() -> ProjectState {
        let state = ProjectState()
        state.startNewProject()
        state.addTrack(type: .video, name: "Video Track 1")
        return state
    }

    private func clip(seconds: Double, start: Double = 0, url: URL? = nil) -> VideoClip {
        VideoClip(
            url: url ?? clipURL,
            duration: CMTime(seconds: seconds, preferredTimescale: 600),
            startTime: CMTime(seconds: start, preferredTimescale: 600)
        )
    }

    private func allClips(_ state: ProjectState) -> [VideoClip] {
        state.currentProject?.timeline.tracks.flatMap(\.clips) ?? []
    }

    @Test("100 one-second clips land back to back on the timeline")
    func timelineWith100Clips() {
        let state = freshState()

        for index in 0 ..< 100 {
            state.addClip(clip(seconds: 1, start: Double(index)))
        }

        let clips = allClips(state).sorted { $0.startTime < $1.startTime }
        #expect(clips.count == 100)
        #expect(abs((clips.last?.startTime.seconds ?? -1) - 99) < 0.01)
    }

    @Test("A clip keeps all ten effects applied one after another")
    func clipWith10Effects() throws {
        let state = freshState()
        let original = clip(seconds: 10)
        state.addClip(original)

        let effectTypes: [VideoEffectType] = [
            .autoEnhance, .noir, .vignette, .brightness, .contrast,
            .saturation, .sharpen, .warmth, .exposure, .vibrance
        ]
        for effectType in effectTypes {
            let current = try #require(state.getClip(by: original.id))
            state.applyEffect(to: current, effect: VideoEffect(type: effectType))
        }

        #expect(state.getClip(by: original.id)?.effects.map(\.type) == effectTypes)
    }

    @Test("Adding 20 clips and deleting every other one leaves exactly 10")
    func rapidClipAddAndDelete() {
        let state = freshState()

        for index in 0 ..< 20 {
            let newClip = clip(seconds: 1, start: Double(index))
            state.addClip(newClip)
            if index.isMultiple(of: 2) {
                state.deleteClip(newClip)
            }
        }

        #expect(allClips(state).count == 10)
    }

    @Test("100 rapid volume changes end on the last value")
    func rapidVolumeChanges() {
        let state = freshState()
        let original = clip(seconds: 10)
        state.addClip(original)

        for index in 0 ..< 100 {
            state.updateClipVolume(clipId: original.id, volume: Float(index) / 100.0)
        }

        #expect(abs((state.getClip(by: original.id)?.volume ?? 0) - 0.99) < 0.001)
    }

    @Test("addClip ignores a negative requested start and appends at the timeline end")
    func negativeStartTimeIsNormalized() {
        let state = freshState()
        state.addClip(clip(seconds: 10, start: -5))

        #expect(allClips(state).first?.startTime.seconds == 0)
    }

    @Test("A 10-hour clip keeps its duration")
    func veryLongDuration() {
        let state = freshState()
        state.addClip(clip(seconds: 36000))

        #expect(abs((allClips(state).first?.duration.seconds ?? 0) - 36000) < 1)
    }

    @Test("Twenty saved projects all load back")
    func manyProjectsSaved() async throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("StressProjects_\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: root) }
        let store = ProjectStore(rootDirectory: root)

        var ids = Set<UUID>()
        for index in 0 ..< 20 {
            let project = VideoProject(name: "Stress Test Project \(index)")
            try await store.saveProject(project)
            ids.insert(project.id)
        }

        let loaded = try await store.loadProjects()
        #expect(Set(loaded.map(\.id)) == ids)
    }

    @Test(
        "Clip file names with special characters survive addClip",
        arguments: ["test video (1) [final] 'copy'.mp4", "视频テスト🎬.mp4"]
    )
    func clipPathCharacters(fileName: String) {
        let state = freshState()
        let url = URL(fileURLWithPath: "/tmp").appendingPathComponent(fileName)
        state.addClip(clip(seconds: 10, url: url))

        #expect(allClips(state).first?.url.lastPathComponent == fileName)
    }

    @Test("Five tracks plus fifty clips are all kept")
    func multipleTracksWithManyClips() {
        let state = ProjectState()
        state.startNewProject()

        for trackNumber in 0 ..< 5 {
            state.addTrack(type: .video, name: "Video Track \(trackNumber + 1)")
            for clipNumber in 0 ..< 10 {
                state.addClip(clip(seconds: 1, start: Double(clipNumber)))
            }
        }

        #expect(state.currentProject?.timeline.tracks.count == 5)
        #expect(allClips(state).count == 50)
    }
}
