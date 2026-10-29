// Timeline fit zoom, split, removed-range time mapping, magnetic snapping and the
// segments the renderer builds around a removed range.

import CoreMedia
import Foundation
@testable import SaneVideo
import Testing

@Suite("Timeline Regression Tests")
struct TimelineRegressionTests {
    private let videoURL = URL(fileURLWithPath: "/tmp/test.mp4")

    private func time(_ seconds: Double) -> CMTime {
        CMTime(seconds: seconds, preferredTimescale: 600)
    }

    /// Magnetic snapping is the default; skip if this test host has the user setting turned off.
    static var magneticTimelineOn: Bool {
        UserDefaults.standard.object(forKey: "magneticTimeline") as? Bool ?? true
    }

    @Test("Fit zoom for a 7:47 recording fits the visible width")
    func fitZoomUsesVisibleWidthForLongRecordings() {
        let duration = Double(7 * 60 + 47)
        let zoom = TimelineZoomCalculator.fitZoom(duration: duration, visibleWidth: 936)
        let renderedWidth = CGFloat(duration) * AppConstants.pixelsPerSecond * zoom

        #expect(renderedWidth <= 912.5)
        #expect(zoom > TimelineZoomCalculator.minimumZoom)
    }

    @Test("A short recording fills most of the timeline instead of a fixed minute")
    func fitZoomFillsWidthForShortClips() {
        let width: CGFloat = 900
        let zoom = TimelineZoomCalculator.fitZoom(duration: 15, visibleWidth: width)
        let renderedWidth = 15 * AppConstants.pixelsPerSecond * zoom
        #expect(renderedWidth > width * 0.8)
        #expect(renderedWidth <= width)
    }

    @Test("Fit zoom for a 10-minute recording can go below the old 0.1 clamp")
    func fitZoomCanGoBelowOldClamp() {
        let zoom = TimelineZoomCalculator.fitZoom(duration: 10 * 60, visibleWidth: 900)

        #expect(zoom < 0.1)
        #expect(zoom >= TimelineZoomCalculator.minimumZoom)
    }

    @Test("Splitting a trimmed clip divides its source range at the playhead")
    @MainActor
    func splitClipDividesSourceRange() throws {
        // 10 s of media, trimmed to start 2 s in; split 3 s into the clip.
        let clip = VideoClip(url: videoURL, duration: time(10), startTime: .zero, trimStart: time(2))
        let state = ProjectState()
        state.startNewProject()
        var project = try #require(state.currentProject)
        project.timeline.tracks = [Track(name: "Video", type: .video, clips: [clip], zIndex: 0)]
        state.currentProject = project

        state.splitClip(clip, atTimelineTime: time(3))

        let clips = try #require(state.currentProject?.timeline.tracks.first?.clips)
        #expect(clips.count == 2)
        let left = try #require(clips.first)
        let right = try #require(clips.last)
        #expect(left.id == clip.id)
        #expect(right.id != clip.id)
        #expect(left.trimStart.seconds == 2.0)
        #expect(left.trimEnd.seconds == 5.0)
        #expect(right.trimStart.seconds == 5.0, "Right part should start 5 s into the file")
        #expect(right.trimEnd.seconds == 10.0)
    }

    @Test("After Clean Up cuts 1-3 s, splitting at 2 s on the timeline cuts the file at 4 s")
    @MainActor
    func splitAfterCleanUpMapsThroughCuts() throws {
        var clip = VideoClip(url: videoURL, duration: time(10), startTime: .zero)
        clip.addRemovedRange(CMTimeRange(start: time(1), duration: time(2)))
        let state = ProjectState()
        state.startNewProject()
        var project = try #require(state.currentProject)
        project.timeline.tracks = [Track(name: "Video", type: .video, clips: [clip], zIndex: 0)]
        state.currentProject = project

        state.splitClip(clip, atTimelineTime: time(2))

        let clips = try #require(state.currentProject?.timeline.tracks.first?.clips)
        #expect(clips.count == 2)
        #expect(clips.first?.trimEnd.seconds == 4.0)
        #expect(clips.last?.trimStart.seconds == 4.0)
        #expect(clips.last?.startTime.seconds == 2.0)
    }

    @Test("A caption crossing the trim end keeps its visible part in the timeline captions (.srt)")
    func captionCrossingTrimIsClamped() {
        var clip = VideoClip(url: videoURL, duration: time(10), startTime: .zero)
        clip.trimEnd = time(5)
        clip.captions = [Caption(text: "across the cut", startTime: time(4), endTime: time(6))]
        var project = VideoProject(name: "T")
        project.timeline.tracks = [Track(name: "Video", type: .video, clips: [clip], zIndex: 0)]

        let caption = project.timelineCaptions.first
        #expect(caption?.startTime.seconds == 4.0)
        #expect((caption?.endTime.seconds ?? 0) <= 5.0)
        #expect((caption?.endTime.seconds ?? 0) > 4.9)
    }

    @Test("A caption that starts inside a Clean Up cut starts where the cut ends")
    func captionStartingInCutIsKept() {
        var clip = VideoClip(url: videoURL, duration: time(10), startTime: .zero)
        clip.addRemovedRange(CMTimeRange(start: time(1), duration: time(2)))
        clip.captions = [Caption(text: "hello there", startTime: time(2), endTime: time(5))]
        var project = VideoProject(name: "T")
        project.timeline.tracks = [Track(name: "Video", type: .video, clips: [clip], zIndex: 0)]

        let caption = project.timelineCaptions.first
        #expect(caption?.startTime.seconds == 1.0)
        #expect(abs((caption?.endTime.seconds ?? 0) - 2.98) < 0.01)
    }

    @Test("Removing 2-4 s shortens the clip and shifts later effective times")
    func captionTimeMappingWithRemovals() {
        var clip = VideoClip(url: videoURL, duration: time(10))
        clip.addRemovedRange(CMTimeRange(start: time(2), duration: time(2)))

        #expect(clip.effectiveDuration.seconds == 8.0)
        #expect(clip.originalTime(forEffectiveTime: time(1)).seconds == 1.0)
        #expect(clip.originalTime(forEffectiveTime: time(3)).seconds == 5.0)
    }

    @Test("Magnetic timeline closes the gap between clips", .enabled(if: TimelineRegressionTests.magneticTimelineOn))
    @MainActor
    func magneticTimelineClosesGap() {
        let clip1 = VideoClip(url: videoURL, duration: time(5), startTime: .zero)
        let clip2 = VideoClip(url: videoURL, duration: time(5), startTime: time(10))
        var timeline = Timeline(tracks: [
            Track(name: "Test Track", type: .video, clips: [clip1, clip2], zIndex: 0)
        ])

        ProjectState().recalculateStartTimes(in: &timeline)

        #expect(timeline.tracks[0].clips[1].startTime.seconds == 5.0)
    }

    @Test("A Clean Up cut moves the next clip up so no gap is left", .enabled(if: TimelineRegressionTests.magneticTimelineOn))
    @MainActor
    func cleanUpCutClosesGap() {
        var clip1 = VideoClip(url: videoURL, duration: time(10), startTime: .zero)
        let clip2 = VideoClip(url: videoURL, duration: time(5), startTime: time(10))
        clip1.addRemovedRange(CMTimeRange(start: time(2), duration: time(3)))
        var timeline = Timeline(tracks: [
            Track(name: "Test Track", type: .video, clips: [clip1, clip2], zIndex: 0)
        ])

        ProjectState().recalculateStartTimes(in: &timeline)

        #expect(timeline.tracks[0].clips[1].startTime.seconds == 7.0)
    }

    @Test("Deleting one split piece keeps the recording the other piece still uses")
    @MainActor
    func deleteSplitPieceKeepsSharedFile() throws {
        let fileURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("shared-\(UUID().uuidString).mov")
        try Data("take".utf8).write(to: fileURL)
        defer { try? FileManager.default.removeItem(at: fileURL) }
        let first = VideoClip(url: fileURL, duration: time(5), startTime: .zero)
        let second = VideoClip(url: fileURL, duration: time(5), startTime: time(5))
        let state = ProjectState()
        state.startNewProject()
        var project = try #require(state.currentProject)
        project.timeline.tracks = [Track(name: "Video", type: .video, clips: [first, second], zIndex: 0)]
        state.currentProject = project

        state.deleteClipFile(first)

        let clips = try #require(state.currentProject?.timeline.tracks.first?.clips)
        #expect(clips.map(\.id) == [second.id])
        #expect(clips.first?.isMissing == false)
        #expect(FileManager.default.fileExists(atPath: fileURL.path))
    }

    @Test("Delete from Disk on a locked track keeps the clip and its file")
    @MainActor
    func deleteFileOnLockedTrackKeepsFile() async throws {
        let fileURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("locked-\(UUID().uuidString).mov")
        try Data("take".utf8).write(to: fileURL)
        defer { try? FileManager.default.removeItem(at: fileURL) }
        let clip = VideoClip(url: fileURL, duration: time(5), startTime: .zero)
        let state = ProjectState()
        state.startNewProject()
        var project = try #require(state.currentProject)
        var track = Track(name: "Video", type: .video, clips: [clip], zIndex: 0)
        track.isLocked = true
        project.timeline.tracks = [track]
        state.currentProject = project

        state.deleteClipFile(clip)
        // The trash used to run in a background Task; give it time to show up.
        try await Task.sleep(for: .milliseconds(300))

        let clips = try #require(state.currentProject?.timeline.tracks.first?.clips)
        #expect(clips.map(\.id) == [clip.id])
        #expect(clips.first?.isMissing == false)
        #expect(FileManager.default.fileExists(atPath: fileURL.path))
    }

    @Test("A removed 5-6 s range yields two render segments around it")
    func removedRangeSplitsRenderSegments() {
        var clip = VideoClip(url: videoURL, duration: time(10))
        clip.useSmoothCutForRemovals = true
        clip.addRemovedRange(CMTimeRange(start: time(5), duration: time(1)))

        let segments = VideoTrackBuilder.computeValidSegments(clip: clip, sourceDuration: clip.duration)

        #expect(segments.count == 2)
        #expect(segments.first?.duration.seconds == 5.0)
        #expect(segments.last?.start.seconds == 6.0)
        #expect(segments.last?.duration.seconds == 4.0)
    }

    @Test("At 2x the playhead maps twice as far into the file, and back")
    func speedMapsTimelineToSourceAndBack() throws {
        var clip = VideoClip(url: videoURL, duration: time(20), startTime: time(3))
        clip.speed = 2.0

        #expect(clip.sourceTime(atTimelineTime: time(8)).seconds == 10.0)
        let back = try #require(clip.timelineTime(forSourceTime: time(10)))
        #expect(back.seconds == 8.0)
    }

    @Test("A transcript line after a trim and a Clean Up cut seeks to where it plays")
    func captionSeekSkipsTrimAndCut() throws {
        // Trimmed to start at 1 s, 2-4 s cut: 1 s plays before the cut, so source 6 s plays at 3 s.
        var clip = VideoClip(url: videoURL, duration: time(10), startTime: .zero, trimStart: time(1))
        clip.addRemovedRange(CMTimeRange(start: time(2), duration: time(2)))
        let caption = Caption(text: "later", startTime: time(6), endTime: time(7))

        let start = try #require(clip.timelineStart(of: caption))
        #expect(start.seconds == 3.0)
    }

    @Test("Deleting a transcript line leaves later captions on their source times")
    @MainActor
    func removeRangeKeepsLaterCaptionTimes() throws {
        var clip = VideoClip(url: videoURL, duration: time(12), startTime: .zero)
        clip.captions = [
            Caption(text: "one", startTime: time(0), endTime: time(3)),
            Caption(text: "two", startTime: time(3), endTime: time(6)),
            Caption(text: "three", startTime: time(6), endTime: time(9)),
        ]
        let state = ProjectState()
        state.startNewProject()
        var project = try #require(state.currentProject)
        project.timeline.tracks = [Track(name: "Video", type: .video, clips: [clip], zIndex: 0)]
        state.currentProject = project

        state.removeRange(CMTimeRange(start: time(3), end: time(6)), from: clip)

        let edited = try #require(state.currentProject?.timeline.tracks.first?.clips.first)
        #expect(edited.captions.map(\.text) == ["one", "three"])
        #expect(edited.captions.last?.startTime.seconds == 6.0, "The cut is skipped at playback, not by moving captions")
    }
}
