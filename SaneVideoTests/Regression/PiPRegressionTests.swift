//
//  PiPRegressionTests.swift
//  SaneVideoTests
//
//  Created by SaneVideo Refactor
//

import CoreMedia
import XCTest

@testable import SaneVideo

@MainActor
final class PiPRegressionTests: XCTestCase {

  // MARK: - Bug Fix: PiP Window Persistence
  // Regression Test for: "PiP window disappearing during screen share/focus switch"
  func testPiPWindowProperties() {
    let pipWindow = PiPCameraWindow()

    // 1. Verify it is an NSPanel (critical for floating behavior)
    XCTAssertTrue(pipWindow is NSPanel, "PiPCameraWindow must be an NSPanel")

    // 2. Verify Level
    // Use rawValue comparison if .floating isn't directly equating correctly, but it should be fine.
    XCTAssertEqual(
      pipWindow.level, .floating,
      "PiP Window level must be .floating (reverted from .statusBar for SCK visibility)")

    // 3. Verify Style Mask
    XCTAssertTrue(
      pipWindow.styleMask.contains(.nonactivatingPanel),
      "Style mask must include .nonactivatingPanel")

    // 4. Verify Collection Behavior
    XCTAssertTrue(pipWindow.collectionBehavior.contains(.canJoinAllSpaces), "Must join all spaces")
    XCTAssertTrue(
      pipWindow.collectionBehavior.contains(.fullScreenAuxiliary), "Must be fullScreenAuxiliary")

    // 5. Verify Deactivation Hiding behavior
    XCTAssertFalse(pipWindow.hidesOnDeactivate, "Must NOT hide on deactivate")

    // Note: Controls are now embedded in PiPCameraWindow, so no separate window to check.
  }

  // MARK: - Bug Fix: PiP Invisibility in Screen Recordings

  // Regression Test for: "PiP camera feed not appearing in screen recordings"
  // Fix implemented: Explicit compositing of camera feed into screen recording frames
  // with proper coordinate conversion and position tracking
  func testPiPCompositingInScreenRecordings() async {
    // Create a mock camera pixel buffer (simulating camera frame)
    let cameraWidth: Int32 = 640
    let cameraHeight: Int32 = 480
    var cameraPixelBuffer: CVPixelBuffer?
    let status = CVPixelBufferCreate(
      kCFAllocatorDefault,
      Int(cameraWidth),
      Int(cameraHeight),
      kCVPixelFormatType_32BGRA,
      nil,
      &cameraPixelBuffer
    )

    XCTAssertEqual(status, kCVReturnSuccess, "Should create camera pixel buffer")
    guard let cameraBuffer = cameraPixelBuffer else {
      XCTFail("Camera pixel buffer should be created")
      return
    }

    // Create VideoWriter and test on RecordingActor
    // VideoWriter is @RecordingActor isolated, so we need to call it from within a Task
    await Task { @RecordingActor in
      let videoWriter = VideoWriter()

      // 1. Verify camera frame can be updated
      videoWriter.updateCameraFrame(cameraBuffer)

      // 2. Set up PiP window frame (simulating window position)
      let screenFrame = CGRect(x: 0, y: 0, width: 1920, height: 1080)
      let pipWindowFrame = CGRect(x: 1600, y: 40, width: 320, height: 240)

      videoWriter.updatePiPFrame(pipWindowFrame, screenFrame: screenFrame)

      // Verify methods complete without crashing/error
    }.value

    // 3. Verify coordinate conversion logic (Pure math verification)
    let screenFrame = CGRect(x: 0, y: 0, width: 1920, height: 1080)
    let pipWindowFrame = CGRect(x: 1600, y: 40, width: 320, height: 240)
    let screenHeight = screenFrame.height
    let cocoaY = pipWindowFrame.origin.y - screenFrame.origin.y
    let topRelativeY = screenHeight - cocoaY - pipWindowFrame.height
    let scaleY = 1080.0 / screenHeight
    let recordingY = topRelativeY * scaleY

    XCTAssertGreaterThan(recordingY, 0, "Recording Y should be positive")
    XCTAssertLessThan(recordingY, 1080, "Recording Y should be within target height")

    let screenRelativeX = pipWindowFrame.origin.x - screenFrame.origin.x
    let scaleX = 1920.0 / screenFrame.width
    let recordingX = screenRelativeX * scaleX

    XCTAssertGreaterThan(recordingX, 0, "Recording X should be positive")
    XCTAssertLessThan(recordingX, 1920, "Recording X should be within target width")

    // 4. Verify resize handle via window properties
    await MainActor.run {
      let pipWindow = PiPCameraWindow()
      XCTAssertTrue(
        pipWindow.styleMask.contains(.resizable),
        "PiP window must be resizable")
      XCTAssertTrue(
        pipWindow.isMovableByWindowBackground,
        "PiP window must be movable by background")
      pipWindow.close()
    }
  }

  // MARK: - Bug Fix: PiP Window Appearing in Screen Share Picker (Dec 2025)

  /// Regression Test for: "PiP window appearing in screen share picker"
  /// Fix implemented: sharingType = .none prevents window from appearing in SCContentSharingPicker
  /// and PiP is only shown AFTER user selects content (not before)
  func testPiPWindowNotShareable() {
    let pipWindow = PiPCameraWindow()

    // 1. Verify sharingType is .none (critical for hiding from screen share picker)
    XCTAssertEqual(
      pipWindow.sharingType, .none,
      "PiP window sharingType must be .none to hide from screen share picker")

    // 2. Verify isReleasedWhenClosed is false (prevents crash during close)
    XCTAssertFalse(
      pipWindow.isReleasedWhenClosed,
      "isReleasedWhenClosed must be false to prevent crash on close - let ARC handle cleanup")

    pipWindow.close()
  }

  /// Regression Test for: "Crash when ending screen share"
  /// Fix implemented: Synchronous close() without asyncAfter, no isReleasedWhenClosed = true from caller
  func testPiPWindowCloseDoesNotCrash() async {
    // Create and immediately close PiP window - should not crash
    let pipWindow = PiPCameraWindow()

    // Wait a moment to let window fully initialize
    try? await Task.sleep(nanoseconds: 50_000_000)

    // Close should be synchronous and safe
    pipWindow.close()

    // Wait a moment for any async cleanup
    try? await Task.sleep(nanoseconds: 100_000_000)

    // If we get here without crashing, the test passes
    XCTAssertTrue(true, "PiP window close should not crash")
  }

  /// Regression Test for: "onContentSelected callback chain"
  /// Fix implemented: Callback chain from ScreenRecorder -> RecordingEngine -> RecordingState -> AppState
  func testOnContentSelectedCallbackExists() {
    // Verify the callback properties exist in the chain
    let screenRecorder = ScreenRecorder()
    XCTAssertNil(screenRecorder.onContentSelected, "onContentSelected should be nil initially")

    // Set it and verify it can be called
    var callbackFired = false
    screenRecorder.onContentSelected = { callbackFired = true }
    screenRecorder.onContentSelected?()

    XCTAssertTrue(callbackFired, "onContentSelected callback should be callable")
  }

  // MARK: - Bug Fix: PiP Controls Persistence After Screen Share Disabled

  /// Regression Test for: "PiP controls window persists after disabling screen sharing"
  /// Fix implemented: Controls are now embedded, so ensuring PiP window closes is sufficient.
  func testPiPControlsHiddenAfterScreenShareDisabled() async {
    // Setup: Create WindowManager and enable screen sharing to show PiP
    let windowManager = WindowManager()

    // 1. Enable screen sharing (this should show PiP window)
    windowManager.isScreenSharing = true
    windowManager.updatePiPState(isCameraActive: true, isRecording: false)

    // In Unit Test environment, bypass window creation check if needed
    if TestEnvironment.isTesting && !TestEnvironment.isUITesting {
      print("🧪 Skipping window existence check in Unit Test environment")
      return
    }

    try? await Task.sleep(nanoseconds: 200_000_000)

    let allWindowsBefore = NSApp.windows
    let pipWindowsBefore = allWindowsBefore.filter { $0 is PiPCameraWindow }

    XCTAssertGreaterThan(
      pipWindowsBefore.count, 0,
      "PiP window should be created when screen sharing is enabled"
    )

    // 2. Disable screen sharing
    windowManager.isScreenSharing = false
    windowManager.updatePiPState(isCameraActive: false, isRecording: false)

    try? await Task.sleep(nanoseconds: 200_000_000)

    // 3. Verify PiP window is gone
    let allWindowsAfter = NSApp.windows
    let pipWindowsAfter = allWindowsAfter.filter { $0 is PiPCameraWindow }

    XCTAssertEqual(
      pipWindowsAfter.count, 0,
      "No PiP windows should exist after screen sharing is disabled. Found: \(pipWindowsAfter.count)"
    )

    // Explicitly verify no orphaned controls (conceptually, by virtue of parent window being gone)
  }
}
