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
}
