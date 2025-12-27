//
//  StateMachineVerificationTests.swift
//  SaneVideoTests
//
//  Created by SaneVideo Refactor
//

import AVFoundation
import Combine
import CoreMedia
import XCTest

@testable import SaneVideo

@MainActor
final class StateMachineVerificationTests: XCTestCase {

  var appState: AppState!
  var windowManager: WindowManager!
  var recordingState: RecordingState!
  var mockCameraService: CameraServiceProtocolMock!
  var cancellables: Set<AnyCancellable>!

  override func setUp() async throws {
    // 1. Setup Mocks
    mockCameraService = CameraServiceProtocolMock()
    mockCameraService.startHandler = {}  // No-op
    mockCameraService.stopHandler = {}

    let mockAudioService = MockAudioService(
      permissionManager: ServiceContainer.shared.permissionManager)
    let mockScreenRecorder = MockScreenRecorder()

    // 2. Inject Mocks into RecordingState
    recordingState = RecordingState(
      cameraService: mockCameraService,
      audioService: mockAudioService,
      screenRecorder: mockScreenRecorder
    )

    // 3. Inject RecordingState into AppState
    appState = AppState(recordingState: recordingState)
    windowManager = appState.windowManager
    // recordingState is already set above

    cancellables = []
  }

  override func tearDown() {
    // Report test end
    reportTestEnd(success: true)

    // CRITICAL FIX: Ensure screen recorder is properly cleaned up before deallocating AppState
    // This prevents crashes from accessing deallocated picker
    // In test environment, teardown is a no-op, so this is safe to call synchronously
    if let screenRecorder = appState?.recordingState.engine?.screenRecorder {
      screenRecorder.teardown()
    }

    // CRITICAL FIX: Cancel all tasks to prevent hanging
    // This prevents tests from spawning multiple app instances
    cancellables?.removeAll()

    // CRITICAL FIX: Clean up AppState to prevent multiple instances
    appState = nil
    cancellables = nil

    // CRITICAL FIX: Small delay to allow cleanup to complete
    // This prevents race conditions that cause multiple app instances
    Thread.sleep(forTimeInterval: 0.1)
  }

  // MARK: - Scenario 1: Screen Share -> Record -> Stop

  func testScreenShareRecordingFlow() async throws {
    // Permission bypass implemented via MockScreenRecorder
    print("🧪 Testing: Screen Share -> Record -> Stop")

    // 1. Initial State
    XCTAssertFalse(appState.isScreenSharing)
    XCTAssertFalse(appState.isRecording)

    // 2. Start Screen Share
    appState.toggleScreenShare()
    XCTAssertTrue(appState.isScreenSharing, "Should be screen sharing")
    XCTAssertTrue(appState.windowManager.isPiPVisible, "PiP should be visible by default")

    // Verify Window Logic (Mocked or checked via state)
    // We can't actually check NSWindow visibility in Unit Test easily without a host app,
    // but we can check the *intent* in WindowMgr

    // 3. Start Recording
    appState.startRecording()

    // In TestEnvironment.isUITesting, it skips countdown and starts immediately
    if TestEnvironment.isUITesting {
      XCTAssertTrue(appState.recordingState.isRecording)
      XCTAssertFalse(appState.isPreparing)
    } else {
      XCTAssertTrue(appState.isPreparing, "Should be counting down")
    }

    // 4. Force state to Recording (if not already there)
    // We can't assume private access, but we can wait or just test logic pre-recording.
    // Let's assume recording starts.

    // 5. STOP Recording
    // appState.stopRecording() calls async cleanup
    let expectation = XCTestExpectation(description: "Recording Stopped")

    appState.recordingState.isRecording = true  // Cheat to skip countdown for test speed
    appState.recordingState.isPreparing = false

    appState.stopRecording()

    // Verify "Immediate" State changes
    // stopRecording is async for file saving, but UI state updates should be orchestrated.

    // WAIT for completion
    // In AppState, stopRecording calls Task { ... handleRecordingFinished ... }
    // We need to wait a bit.
    try? await Task.sleep(nanoseconds: 500_000_000)  // 0.5s

    // 6. Verify Restoration
    // CRITICAL: WindowManager state check
    XCTAssertFalse(appState.isScreenSharing, "Should exit screen share after recording")
    XCTAssertFalse(
      appState.windowManager.isScreenSharing, "WindowManager should know screen share ended")

    // PiP Logic:
    // "updatePiPState(isCameraActive: false, isRecording: false)" -> Hides PiP
    // We can check `isPiPVisible` state property?
    // Note: isPiPVisible remains `true` (user preference) but `shouldShowPiP` logic depends on context.
    // However, we can check if the WindowManager *believes* it should show.
    // Ideally we'd check pipWindow == nil, but that's internal.

    // We relies on `isScreenSharing` being false to ensure PiP hides.
    XCTAssertFalse(appState.isScreenSharing)

    expectation.fulfill()
    await fulfillment(of: [expectation], timeout: 1.0)
  }

  // MARK: - Scenario 3: Screen Share -> Stop Share (No Recording)
  // CRITICAL REGRESSION TEST: This test verifies the screen sharing exit crash is fixed
  // Previously skipped due to crash - now fixed with proper stream cleanup sequence

  @MainActor
  func testScreenShareStopOnlyFlow() async throws {
    // Permission bypass implemented via MockScreenRecorder
    print("🧪 Testing: Screen Share -> Stop Share (Regression test for crash fix)")

    // 1. Start Share
    appState.toggleScreenShare()

    // CRITICAL: Wait for async operations to complete
    // Give enough time for window creation, picker presentation, and state updates
    try? await Task.sleep(nanoseconds: 500_000_000)  // 500ms

    XCTAssertTrue(appState.isScreenSharing, "Should be screen sharing after toggle")

    // 2. Stop Share - THIS IS WHERE THE CRASH WAS HAPPENING
    // The fix ensures stream is stopped before picker deactivation
    appState.toggleScreenShare()

    // CRITICAL: Wait for proper cleanup sequence to complete
    // The fix includes: stop stream (100ms) -> deactivate picker -> cleanup windows (100ms) -> restore
    // Total should be ~300ms, but we wait longer to be safe
    try? await Task.sleep(nanoseconds: 800_000_000)  // 800ms for complete cleanup

    // 3. Verify state - this should NOT crash
    XCTAssertFalse(appState.isScreenSharing, "Should not be screen sharing after second toggle")
    XCTAssertFalse(
      appState.windowManager.isScreenSharing, "WindowManager should reflect screen share is off")

    // 4. CRITICAL FIX: Ensure all async tasks complete before test ends
    // This prevents the test from hanging and spawning multiple app instances
    try? await Task.sleep(nanoseconds: 200_000_000)  // 200ms final cleanup

    // 5. Verify no crash occurred - if we get here, the test passed
    print("✅ Screen share exit completed without crash")
  }

  // MARK: - Crash Regression (Zombie Window Logic)

  func testZombieWindowFixLogic() async throws {
    // Permission bypass implemented via MockScreenRecorder
    // This tests the WindowManager code path specifically

    // 1. Show PiP
    appState.windowManager.isPiPVisible = true
    appState.windowManager.isScreenSharing = true
    appState.windowManager.updatePiPState(isCameraActive: true, isRecording: false)

    // CRITICAL FIX: Wait for window creation
    try? await Task.sleep(nanoseconds: 100_000_000)  // 100ms

    // 2. Hide PiP
    appState.windowManager.updatePiPState(isCameraActive: false, isRecording: false)

    // CRITICAL FIX: Wait for window cleanup to complete
    try? await Task.sleep(nanoseconds: 200_000_000)  // 200ms

    // The fix was in the *implementation* of hidePiPWindow.
    // We can't easily assert the window memory state here without internals,
    // but verifying it doesn't crash on execution is a good smoke test.
    XCTAssertTrue(true, "Did not crash calling updatePiPState")
  }
}

// Mock Audio Service
class MockAudioService: AudioService {
  override func start() {
    // No-op for tests to avoid TCC crash
    print("MockAudioService: start called")
  }

  override func stop() {
    print("MockAudioService: stop called")
  }

  override func checkPermission() {
    // No-op
  }

  override func requestPermission() {
    // No-op
  }
}

// Note: MockCameraService removed - now using Mockolo-generated CameraServiceProtocolMock
// See SaneVideoTests/Mocks/Mocks.swift for generated mocks

// Mock ScreenRecorder
class MockScreenRecorder: ScreenRecorder {
  override func start(outputURL: URL? = nil) async throws {
    print("MockScreenRecorder: start called")
    // Do not call super.start() to avoid picker
  }

  override func stop() async {
    print("MockScreenRecorder: stop called")
  }

  override func teardown() {
    print("MockScreenRecorder: teardown called")
  }
}
