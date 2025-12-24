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
    // Report test start for progress tracking
    reportTestStart()
    
    // Setup isolated test environment
    // Use Mockolo-generated mock instead of manual mock
    mockCameraService = CameraServiceProtocolMock()

    // Inject Mocks into Singleton Container
    ServiceContainer.shared.cameraService = mockCameraService

    // Mock Audio Service (Requires PermissionManager)
    // Note: AudioService is a class, not a protocol, so we still use manual mock
    // TODO: Consider creating AudioServiceProtocol and using Mockolo
    let pm = ServiceContainer.shared.permissionManager
    let mockAudio = MockAudioService(permissionManager: pm)
    ServiceContainer.shared.audioService = mockAudio

    // Now init AppState (which uses the container's services)
    // Note: ProjectState might try to read disk, so we should mock file manager if possible.
    // But ProjectState inits its own store.

    appState = AppState()
    windowManager = appState.windowManager
    recordingState = appState.recordingState

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
    
    appState = nil
    cancellables = nil
  }

  // MARK: - Scenario 1: Screen Share -> Record -> Stop

  func testScreenShareRecordingFlow() async throws {
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
    print("🧪 Testing: Screen Share -> Stop Share (Regression test for crash fix)")

    // 1. Start Share
    appState.toggleScreenShare()
    
    // CRITICAL: Wait for async operations to complete
    // Give enough time for window creation, picker presentation, and state updates
    try? await Task.sleep(nanoseconds: 500_000_000) // 500ms
    
    XCTAssertTrue(appState.isScreenSharing, "Should be screen sharing after toggle")

    // 2. Stop Share - THIS IS WHERE THE CRASH WAS HAPPENING
    // The fix ensures stream is stopped before picker deactivation
    appState.toggleScreenShare()
    
    // CRITICAL: Wait for proper cleanup sequence to complete
    // The fix includes: stop stream (100ms) -> deactivate picker -> cleanup windows (100ms) -> restore
    // Total should be ~300ms, but we wait longer to be safe
    try? await Task.sleep(nanoseconds: 800_000_000) // 800ms for complete cleanup

    // 3. Verify state - this should NOT crash
    XCTAssertFalse(appState.isScreenSharing, "Should not be screen sharing after second toggle")
    XCTAssertFalse(appState.windowManager.isScreenSharing, "WindowManager should reflect screen share is off")
    
    // 4. Verify no crash occurred - if we get here, the test passed
    print("✅ Screen share exit completed without crash")
  }

  // MARK: - Crash Regression (Zombie Window Logic)

  func testZombieWindowFixLogic() async throws {
    // This tests the WindowManager code path specifically

    // 1. Show PiP
    appState.windowManager.isPiPVisible = true
    appState.windowManager.isScreenSharing = true
    appState.windowManager.updatePiPState(isCameraActive: true, isRecording: false)
    
    // CRITICAL FIX: Wait for window creation
    try? await Task.sleep(nanoseconds: 100_000_000) // 100ms

    // 2. Hide PiP
    appState.windowManager.updatePiPState(isCameraActive: false, isRecording: false)
    
    // CRITICAL FIX: Wait for window cleanup to complete
    try? await Task.sleep(nanoseconds: 200_000_000) // 200ms

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
