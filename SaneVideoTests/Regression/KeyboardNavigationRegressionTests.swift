// Behavior behind keyboard shortcuts: I/O in/out points, Shift+Arrow 10-second seek,
// and Cmd+D duplicate.

import CoreMedia
import Foundation
@testable import SaneVideo
import Testing

@Suite("Keyboard Navigation")
@MainActor
struct KeyboardNavigationRegressionTests {
    private func time(_ seconds: Double) -> CMTime {
        CMTime(seconds: seconds, preferredTimescale: 600)
    }

    @Test("In and out points form a selected range, and clearing removes it")
    func inOutPointManagement() throws {
        let playbackState = PlaybackState()
        #expect(playbackState.selectedRange == nil)

        playbackState.inPoint = time(2)
        #expect(playbackState.selectedRange == nil, "One point alone is not a range")
        playbackState.outPoint = time(5)

        let range = try #require(playbackState.selectedRange)
        #expect(range.start.seconds == 2.0)
        #expect(range.end.seconds == 5.0)

        playbackState.clearInOutPoints()
        #expect(playbackState.inPoint == nil)
        #expect(playbackState.outPoint == nil)
        #expect(playbackState.selectedRange == nil)
    }

    @Test("An out point before the in point still yields a forward range")
    func inOutPointsReversedOrder() throws {
        let playbackState = PlaybackState()
        playbackState.outPoint = time(2)
        playbackState.inPoint = time(5)

        let range = try #require(playbackState.selectedRange)
        #expect(range.start.seconds == 2.0)
        #expect(range.end.seconds == 5.0)
    }

    @Test(
        "10-second seek moves by 10 s and clamps to 0 and the duration",
        arguments: [
            (60.0, 30.0, true, 40.0),
            (60.0, 40.0, false, 30.0),
            (15.0, 10.0, true, 15.0),
            (15.0, 5.0, false, 0.0)
        ]
    )
    func seek10Seconds(duration: Double, start: Double, forward: Bool, expected: Double) {
        let playbackState = PlaybackState()
        playbackState.duration = time(duration)
        playbackState.currentTime = time(start)

        if forward {
            playbackState.seekForward10Seconds()
        } else {
            playbackState.seekBackward10Seconds()
        }

        #expect(abs(playbackState.currentTime.seconds - expected) < 0.001)
    }

    @Test("Duplicating a clip adds one copy with a new id and the same media")
    func clipDuplicateOperation() throws {
        let projectState = ProjectState()
        projectState.startNewProject()
        var project = try #require(projectState.currentProject)

        let originalClip = VideoClip(
            url: URL(fileURLWithPath: "/tmp/test.mp4"),
            duration: time(5),
            startTime: .zero
        )
        project.timeline.tracks = [Track(name: "Video", type: .video, clips: [originalClip], zIndex: 0)]
        projectState.currentProject = project

        projectState.duplicateClip(originalClip, atTime: time(5))

        let clips = projectState.currentProject?.timeline.tracks.first?.clips ?? []
        #expect(clips.count == 2)
        let copy = try #require(clips.first { $0.id != originalClip.id })
        #expect(copy.url == originalClip.url)
        #expect(copy.duration == originalClip.duration)
    }
}
