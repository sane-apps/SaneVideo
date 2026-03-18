import CoreMedia
import XCTest

@testable import SaneVideo

final class RecordingTimeCoordinatorTests: XCTestCase {

  func testRecalibrationTrigger() {
    let coordinator = RecordingTimeCoordinator()

    // 1. Initial State
    let firstSampleTime = CMTime(seconds: 10, preferredTimescale: 600)
    let result1 = coordinator.processSampleTime(firstSampleTime)
    coordinator.recordWrittenPresentationTime(result1.presentationTime)

    XCTAssertEqual(coordinator.startTime, firstSampleTime)
    XCTAssertFalse(coordinator.startTimeNeedsRecalibration)
    XCTAssertEqual(result1.presentationTime, firstSampleTime)

    // Simulate some recording
    let secondResult = coordinator.processSampleTime(CMTime(seconds: 11, preferredTimescale: 600))
    coordinator.recordWrittenPresentationTime(secondResult.presentationTime)
    let lastRecordedTimeBeforeSwitch = coordinator.lastRecordedTime

    // 2. Trigger Recalibration (Source Switch)
    coordinator.startTimeNeedsRecalibration = true

    // First sample from new source has a widely different timestamp
    let newSourceTime = CMTime(seconds: 50, preferredTimescale: 600)
    let result2 = coordinator.processSampleTime(newSourceTime)
    coordinator.commitPendingRecalibrationIfNeeded()

    // 3. Verify Recalibration
    XCTAssertFalse(
      coordinator.startTimeNeedsRecalibration, "Flag should be cleared after the first frame lands")
    XCTAssertNotEqual(coordinator.timeOffset, .zero, "Time offset should have been calculated")

    // The new presentation time should be ~lastRecordedTime + 100ms
    let expectedTime = lastRecordedTimeBeforeSwitch.seconds + 0.1
    XCTAssertEqual(
      result2.presentationTime.seconds - coordinator.startTime.seconds, expectedTime,
      accuracy: 0.001)
  }

  func testBeginSourceSwitchRecalibrationResetsDriftTrackerState() {
    let coordinator = RecordingTimeCoordinator()
    let tracker = DriftTracker()
    tracker.recordVideoTimestamp(CMTime(seconds: 1.2, preferredTimescale: 600))
    tracker.recordAudioTimestamp(CMTime(seconds: 0.9, preferredTimescale: 600))
    _ = tracker.calculateCorrection()

    coordinator.driftTracker = tracker
    coordinator.beginSourceSwitchRecalibration()

    XCTAssertTrue(coordinator.startTimeNeedsRecalibration)
    XCTAssertEqual(tracker.getDriftHistory().count, 0)
    XCTAssertEqual(tracker.currentDrift(), 0, accuracy: 0.0001)
  }

  func testRecalibrationContinuesFromLatestWrittenAudioTime() {
    let coordinator = RecordingTimeCoordinator()

    let firstVideo = coordinator.processSampleTime(CMTime(seconds: 10, preferredTimescale: 600))
    coordinator.recordWrittenPresentationTime(firstVideo.presentationTime)

    let secondVideo = coordinator.processSampleTime(CMTime(seconds: 11, preferredTimescale: 600))
    coordinator.recordWrittenPresentationTime(secondVideo.presentationTime)

    // Audio continues during the handoff even though no new video frame has landed yet.
    coordinator.recordWrittenPresentationTime(CMTime(seconds: 11.8, preferredTimescale: 600))
    coordinator.beginSourceSwitchRecalibration()

    let result = coordinator.processSampleTime(CMTime(seconds: 50, preferredTimescale: 600))
    coordinator.commitPendingRecalibrationIfNeeded()

    XCTAssertFalse(coordinator.startTimeNeedsRecalibration)
    XCTAssertEqual(
      result.presentationTime.seconds - coordinator.startTime.seconds,
      1.9,
      accuracy: 0.001
    )
  }
}
