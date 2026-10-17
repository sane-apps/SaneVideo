// Screen share / record / stop transitions in AppState and WindowManager.

import AVFoundation
import CoreMedia
@testable import SaneVideo
import XCTest

/// Waits for a main-actor condition instead of sleeping a fixed time.
@MainActor
private func waitUntil(
    timeout: Duration = .seconds(3),
    _ condition: () -> Bool
) async -> Bool {
    let clock = ContinuousClock()
    let deadline = clock.now.advanced(by: timeout)
    while !condition() {
        if clock.now >= deadline {
            return false
        }
        await Task.yield()
        try? await Task.sleep(for: .milliseconds(10))
    }
    return true
}

@MainActor
final class StateMachineVerificationTests: XCTestCase {
    var appState: AppState!
    var mockCameraService: CameraServiceProtocolMock!
    var mockScreenRecorder: MockScreenRecorder!

    override func setUp() async throws {
        mockCameraService = CameraServiceProtocolMock()
        mockCameraService.startHandler = {}
        mockCameraService.stopHandler = {}

        let mockAudioService = MockAudioService(
            permissionManager: ServiceContainer.shared.permissionManager
        )
        mockScreenRecorder = MockScreenRecorder()

        let recordingState = RecordingState(
            cameraService: mockCameraService,
            audioService: mockAudioService,
            screenRecorder: mockScreenRecorder
        )
        appState = AppState(recordingState: recordingState)
    }

    override func tearDown() {
        reportTestEnd(success: true)
        // In the test environment teardown is a no-op, so calling it synchronously is safe.
        appState?.recordingState.engine?.screenRecorder.teardown()
        appState = nil
        mockScreenRecorder = nil
    }

    func testStartRecordingDoesNotAutoEnableCameraDuringPermissionPreflight() {
        appState.cameraEnabled = false
        appState.startRecording()

        XCTAssertFalse(
            appState.cameraEnabled,
            "Recording start should let RecordingState handle camera permission preflight instead of force-starting camera"
        )
    }

    func testScreenShareToggleDoesNotAutoEnableCamera() {
        appState.cameraEnabled = false

        appState.toggleScreenShare()

        XCTAssertTrue(appState.isScreenSharing, "Screen sharing should enter picker mode")
        XCTAssertFalse(
            appState.cameraEnabled,
            "Screen sharing should stay screen-only until the user explicitly enables camera"
        )
    }

    func testScreenShareToggleStartsScreenRecorderFlow() async {
        XCTAssertEqual(mockScreenRecorder.startCallCount, 0)

        appState.toggleScreenShare()

        let started = await waitUntil { self.mockScreenRecorder.startCallCount == 1 }
        XCTAssertTrue(started, "Starting screen share should delegate to ScreenRecorder.start()")
    }

    func testScreenShareRecordingFlow() async {
        XCTAssertFalse(appState.isScreenSharing)
        XCTAssertFalse(appState.isRecording)

        appState.toggleScreenShare()
        XCTAssertTrue(appState.isScreenSharing, "Should be screen sharing")
        XCTAssertFalse(appState.cameraEnabled, "Screen sharing should not silently enable camera")
        XCTAssertTrue(appState.windowManager.isPiPVisible, "PiP should be visible by default")

        appState.startRecording()
        if TestEnvironment.isUITesting {
            XCTAssertTrue(appState.recordingState.isRecording)
            XCTAssertFalse(appState.isPreparing)
        } else {
            XCTAssertTrue(appState.isPreparing, "Should be counting down")
        }

        // Skip the countdown so stop runs against a live recording state.
        appState.recordingState.isRecording = true
        appState.recordingState.isPreparing = false

        appState.stopRecording()

        let exited = await waitUntil {
            !self.appState.isScreenSharing && !self.appState.windowManager.isScreenSharing
        }
        XCTAssertTrue(exited, "Stopping a screen recording should exit screen share in AppState and WindowManager")
    }

    // Regression: stopping screen share used to crash while the picker was torn down.
    func testScreenShareStopOnlyFlow() async {
        appState.toggleScreenShare()
        // A toggle is ignored while the previous one is still finishing, so wait for that too.
        let sharing = await waitUntil {
            self.appState.isScreenSharing && !self.appState.windowManager.isTogglingScreenShare
        }
        XCTAssertTrue(sharing, "Should be screen sharing after toggle")

        appState.toggleScreenShare()

        let stopped = await waitUntil {
            !self.appState.isScreenSharing && !self.appState.windowManager.isScreenSharing
        }
        XCTAssertTrue(stopped, "Second toggle should end screen share in AppState and WindowManager")
    }

    func testScreenPickerCancelResetsScreenShareState() async {
        XCTAssertFalse(appState.isScreenSharing)

        appState.toggleScreenShare()
        let started = await waitUntil { self.mockScreenRecorder.startCallCount == 1 }
        XCTAssertTrue(started)
        XCTAssertTrue(appState.isScreenSharing, "Starting screen share should enter picker mode")

        mockScreenRecorder.simulatePickerCancellation()

        let reset = await waitUntil {
            !self.appState.isScreenSharing && !self.appState.windowManager.isScreenSharing
        }
        XCTAssertTrue(reset, "Cancelling the picker should unwind screen-share mode in AppState and WindowManager")
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
  private(set) var startCallCount = 0

  override func start(outputURL: URL? = nil) async throws {
    print("MockScreenRecorder: start called")
    startCallCount += 1
    // Do not call super.start() to avoid picker
  }

  override func stop() async {
    print("MockScreenRecorder: stop called")
  }

  override func teardown() {
    print("MockScreenRecorder: teardown called")
  }

  func simulatePickerCancellation() {
    let error = NSError(
      domain: "SaneVideo",
      code: -102,
      userInfo: [NSLocalizedDescriptionKey: "User cancelled screen picker"]
    )
    onStop?(error)
  }
}
