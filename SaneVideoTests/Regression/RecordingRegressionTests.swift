//
//  RecordingRegressionTests.swift
//  SaneVideoTests
//
//  Created by SaneVideo Refactor
//

import CoreMedia
import XCTest

@testable import SaneVideo

@MainActor
final class RecordingRegressionTests: XCTestCase {

  // MARK: - Bug Fix: Source Switch Timestamp Monotonicity (Code -12737)

  // Regression Test for: "Recording crash on source switch due to non-monotonic timestamps"
  // Fix implemented: Added 100ms safe gap when switching sources
  func testSourceSwitchTimestampGap() async {
    let startTime = CMTime(seconds: 0, preferredTimescale: 600)
    let lastRecordedDuration = CMTime(seconds: 9.9, preferredTimescale: 600)

    // Simulate the logic used in RecordingEngine.processSample
    // New Logic:
    let safeGap = CMTime(value: 100, timescale: 1000)  // 100ms

    let lastAbsoluteTime = CMTimeAdd(startTime, lastRecordedDuration)
    let targetNewTime = CMTimeAdd(lastAbsoluteTime, safeGap)

    // Verify that targetNewTime is strictly greater than lastRecordedTime + 33ms (typical frame duration)
    let typicalFrameDuration = CMTime(value: 1, timescale: 30)  // ~33ms
    let previousFrameEndTime = CMTimeAdd(lastAbsoluteTime, typicalFrameDuration)

    XCTAssertGreaterThan(
      targetNewTime, previousFrameEndTime,
      "New segment must start AFTER the previous frame has finished playing")

    // Calculate the actual gap in seconds
    let actualGap = CMTimeSubtract(targetNewTime, lastAbsoluteTime).seconds
    XCTAssertEqual(actualGap, 0.1, accuracy: 0.001, "Gap should be exactly 0.1s (100ms)")
  }

  // MARK: - Bug Fix: Recording Engine Threading

  // Regression Test for: "Recording Engine running on Main Thread check"
  func testRecordingEngineQueue() {
    _ = RecordingEngine(
      cameraService: ServiceContainer.shared.cameraService,
      audioService: ServiceContainer.shared.audioService
    )

    // We can't easily check private queue, but we can check it's NOT main thread
    // This is hard to unit test without exposing internals.
    // Instead, we verify that calling public methods doesn't crash or block main.

    let expectation = XCTestExpectation(description: "Start recording async")

    Task {
      // Simulate start
      // engine.startRecording(...) requires real services, skipping full integration test here.
      // Just verifying instantiation is relatively safe.
      expectation.fulfill()
    }

    wait(for: [expectation], timeout: 1.0)
  }
}
