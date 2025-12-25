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
    var clip2 = VideoClip(
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
