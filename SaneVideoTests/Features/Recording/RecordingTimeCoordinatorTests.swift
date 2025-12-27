import CoreMedia
import XCTest

@testable import SaneVideo

final class RecordingTimeCoordinatorTests: XCTestCase {

  func testRecalibrationTrigger() {
    let coordinator = RecordingTimeCoordinator()

    // 1. Initial State
    let firstSampleTime = CMTime(seconds: 10, preferredTimescale: 600)
    let result1 = coordinator.processSampleTime(firstSampleTime)

    XCTAssertEqual(coordinator.startTime, firstSampleTime)
    XCTAssertFalse(coordinator.startTimeNeedsRecalibration)
    XCTAssertEqual(result1.presentationTime, firstSampleTime)

    // Simulate some recording
    _ = coordinator.processSampleTime(CMTime(seconds: 11, preferredTimescale: 600))
    let lastRecordedTimeBeforeSwitch = coordinator.lastRecordedTime

    // 2. Trigger Recalibration (Source Switch)
    coordinator.startTimeNeedsRecalibration = true

    // First sample from new source has a widely different timestamp
    let newSourceTime = CMTime(seconds: 50, preferredTimescale: 600)
    let result2 = coordinator.processSampleTime(newSourceTime)

    // 3. Verify Recalibration
    XCTAssertFalse(
      coordinator.startTimeNeedsRecalibration, "Flag should be cleared after processing")
    XCTAssertNotEqual(coordinator.timeOffset, .zero, "Time offset should have been calculated")

    // The new presentation time should be ~lastRecordedTime + 100ms
    let expectedTime = lastRecordedTimeBeforeSwitch.seconds + 0.1
    XCTAssertEqual(
      result2.presentationTime.seconds - coordinator.startTime.seconds, expectedTime,
      accuracy: 0.001)
  }
}
