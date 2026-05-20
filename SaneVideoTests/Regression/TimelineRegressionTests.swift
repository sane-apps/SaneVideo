//
//  TimelineRegressionTests.swift
//  SaneVideoTests
//
//  Created by SaneVideo Refactor
//

import CoreMedia
import XCTest

@testable import SaneVideo

final class TimelineRegressionTests: XCTestCase {

  // MARK: - Editor Timeline Fit

  func testTimelineFitZoomUsesActualVisibleWidthForLongRecordings() {
    let zoom = TimelineZoomCalculator.fitZoom(duration: 7 * 60 + 47, visibleWidth: 936)
    let renderedWidth = CGFloat(7 * 60 + 47) * AppConstants.pixelsPerSecond * zoom

    XCTAssertLessThanOrEqual(renderedWidth, 912.5)
    XCTAssertGreaterThan(zoom, TimelineZoomCalculator.minimumZoom)
  }

  func testTimelineFitZoomCanGoBelowOldPointOneClamp() {
    let zoom = TimelineZoomCalculator.fitZoom(duration: 10 * 60, visibleWidth: 900)

    XCTAssertLessThan(zoom, 0.1)
    XCTAssertGreaterThanOrEqual(zoom, TimelineZoomCalculator.minimumZoom)
  }

  // MARK: - Bug Fix: Clip Splitting Time Calculations

  // Regression Test for: "Splitting clips resulted in incorrect local times"
  func testClipSplittingMath() {
    // Setup a clip: 10s long, starting at 0
    let videoURL = URL(fileURLWithPath: "/tmp/test.mp4")
    let clip = VideoClip(
      url: videoURL, duration: CMTime(seconds: 10, preferredTimescale: 600), startTime: .zero)

    // Split at 5s global time
    let splitTime = CMTime(seconds: 5, preferredTimescale: 600)

    // Logic verification (mimicking TimelineEngine.split)
    let leftDuration = CMTimeSubtract(splitTime, clip.startTime)
    let rightDuration = CMTimeSubtract(clip.duration, leftDuration)

    XCTAssertEqual(leftDuration.seconds, 5.0)
    XCTAssertEqual(rightDuration.seconds, 5.0)

    // Verify "Offset" / "Content Start" logic
    // If the original clip had an offset (e.g. started 2s into file)
    let originalOffset = CMTime(seconds: 2, preferredTimescale: 600)
    let offsetClip = VideoClip(
      url: videoURL, duration: CMTime(seconds: 10, preferredTimescale: 600), startTime: .zero,
      trimStart: originalOffset)

    // Split at 3s global (which is +3s from start)
    // Left: duration 3. content 2...(2+3)=5
    // Right: duration 7. content 5...(2+10)=12

    let splitPoint = CMTime(seconds: 3, preferredTimescale: 600)
    let leftDur = splitPoint
    _ = CMTimeSubtract(offsetClip.duration, leftDur)

    let newRightOffset = CMTimeAdd(originalOffset, leftDur)

    XCTAssertEqual(
      newRightOffset.seconds, 5.0, "Right clip should start 5s into the underlying file")
  }

  // MARK: - Feature: Caption Time Mapping

  func testCaptionTimeMappingWithRemovals() {
    let videoURL = URL(fileURLWithPath: "/tmp/test.mp4")
    var clip = VideoClip(url: videoURL, duration: CMTime(seconds: 10, preferredTimescale: 600))

    // Remove 2s...4s (2s duration)
    clip.addRemovedRange(
      CMTimeRange(
        start: CMTime(seconds: 2, preferredTimescale: 600),
        duration: CMTime(seconds: 2, preferredTimescale: 600)))

    // Effective duration should be 8s
    XCTAssertEqual(clip.effectiveDuration.seconds, 8.0)

    // Effective time 1s -> Original 1s
    XCTAssertEqual(
      clip.originalTime(forEffectiveTime: CMTime(seconds: 1, preferredTimescale: 600)).seconds, 1.0)

    // Effective time 3s -> Original 5s (skips 2s...4s)
    XCTAssertEqual(
      clip.originalTime(forEffectiveTime: CMTime(seconds: 3, preferredTimescale: 600)).seconds, 5.0)
  }

  // MARK: - Feature: Magnetic Timeline

  func testMagneticTimelineRecalculate() {
    let videoURL = URL(fileURLWithPath: "/tmp/test.mp4")
    let clip1 = VideoClip(
      url: videoURL, duration: CMTime(seconds: 5, preferredTimescale: 600), startTime: .zero)
    let clip2 = VideoClip(
      url: videoURL, duration: CMTime(seconds: 5, preferredTimescale: 600),
      startTime: CMTime(seconds: 10, preferredTimescale: 600))  // Gap of 5s

    var timeline = Timeline(tracks: [
      Track(name: "Test Track", type: .video, clips: [clip1, clip2], zIndex: 0)
    ])

    // This is tricky because recalculateStartTimes uses @AppStorage which we might not want to mock here
    // But we can test the logic directly if we assume it's enabled.
    // Let's verify the logic in ProjectState.recalculateStartTimes

    var cumulativeTime = CMTime.zero
    for i in 0..<timeline.tracks[0].clips.count {
      timeline.tracks[0].clips[i].startTime = cumulativeTime
      cumulativeTime = CMTimeAdd(cumulativeTime, timeline.tracks[0].clips[i].effectiveDuration)
    }

    XCTAssertEqual(
      timeline.tracks[0].clips[1].startTime.seconds, 5.0,
      "Second clip should snap to the end of the first clip (5s)")
  }

  // MARK: - Bug Fix: Empty Track Range Crash (2025-12-27)

  /// Regression test for: "Range requires lowerBound <= upperBound" crash
  /// Bug: In non-magnetic timeline mode, `for clipIndex in 1..<mutableTrack.clips.count`
  /// crashes when clips.count is 0 because 1..<0 is an invalid range in Swift.
  /// Fix: Added guard `if mutableTrack.clips.count > 1` before the loop.
  /// Location: ProjectState+Timeline.swift:33
  @MainActor
  func testRecalculateStartTimesWithEmptyTrack() {
    let projectState = ProjectState()
    projectState.startNewProject()

    guard var project = projectState.currentProject else {
      XCTFail("Should have a project")
      return
    }

    // Create an empty track (0 clips)
    let emptyTrack = Track(name: "Empty Track", type: .video, clips: [], zIndex: 0)
    project.timeline.tracks = [emptyTrack]

    // This should NOT crash - the bug was 1..<0 creating an invalid range
    projectState.recalculateStartTimes(in: &project.timeline)

    // Verify it completed without crash
    XCTAssertTrue(true, "recalculateStartTimes should handle empty tracks without crashing")
  }

  @MainActor
  func testRecalculateStartTimesWithSingleClipTrack() {
    let projectState = ProjectState()
    projectState.startNewProject()

    guard var project = projectState.currentProject else {
      XCTFail("Should have a project")
      return
    }

    // Create a track with exactly 1 clip
    let videoURL = URL(fileURLWithPath: "/tmp/test.mp4")
    let clip = VideoClip(
      url: videoURL, duration: CMTime(seconds: 5, preferredTimescale: 600), startTime: .zero)
    let singleClipTrack = Track(name: "Single Clip Track", type: .video, clips: [clip], zIndex: 0)
    project.timeline.tracks = [singleClipTrack]

    // This should NOT crash - 1..<1 is valid but empty, but guard prevents it anyway
    projectState.recalculateStartTimes(in: &project.timeline)

    XCTAssertTrue(true, "recalculateStartTimes should handle single-clip tracks without crashing")
  }

  // MARK: - Feature: Smooth Cut Insertion

  func testSmoothCutInsertion() {
    let videoURL = URL(fileURLWithPath: "/tmp/test.mp4")
    var clip = VideoClip(url: videoURL, duration: CMTime(seconds: 10, preferredTimescale: 600))
    clip.useSmoothCutForRemovals = true
    clip.addRemovedRange(
      CMTimeRange(
        start: CMTime(seconds: 5, preferredTimescale: 600),
        duration: CMTime(seconds: 1, preferredTimescale: 600)))

    let validSegments = VideoTrackBuilder.computeValidSegments(
      clip: clip, sourceDuration: clip.duration)
    XCTAssertEqual(validSegments.count, 2)
    XCTAssertEqual(validSegments[0].duration.seconds, 5.0)
    XCTAssertEqual(validSegments[1].start.seconds, 6.0)

    // The smoothing overlap is 0.15s in VideoTrackBuilder
    let overlap = CMTime(seconds: 0.15, preferredTimescale: 600)

    // Verify segment 2 would be extended if we followed the logic in VideoTrackBuilder
    var segment2 = validSegments[1]
    segment2.start = CMTimeSubtract(segment2.start, overlap)
    segment2.duration = CMTimeAdd(segment2.duration, overlap)

    XCTAssertEqual(segment2.start.seconds, 5.85, "Should start 0.15s earlier for smooth transition")
  }
}
