import AVFoundation
import Foundation
import Testing

@testable import SaneVideo

@Suite("Recording State Tests")
@MainActor
struct RecordingStateTests {

  // MARK: - Initial State Tests

  @Test("Initial state values")
  func initialState() {
    let recordingState = RecordingState(cameraService: nil)
    #expect(!recordingState.isRecording)
    #expect(!recordingState.isPaused)
    #expect(!recordingState.isPreparing)
    #expect(recordingState.countdownValue == 0)
    #expect(recordingState.recordingDuration == 0)
  }

  // MARK: - Countdown Tests

  @Test("Start recording behavior (preparing mode)")
  func startRecordingEntersPreparing() {
    let recordingState = RecordingState(cameraService: nil)
    recordingState.shouldSkipCountdown = false
    recordingState.startRecording(isScreenSharing: false)

    #expect(recordingState.isPreparing)
    #expect(recordingState.countdownValue == 3)
  }

  @Test("Prevention of redundant recording starts")
  func startRecordingPreventsDoubleStart() {
    let recordingState = RecordingState(cameraService: nil)
    recordingState.shouldSkipCountdown = false
    recordingState.startRecording(isScreenSharing: false)
    let initialCountdown = recordingState.countdownValue

    recordingState.startRecording(isScreenSharing: false)
    #expect(recordingState.isPreparing)
    #expect(recordingState.countdownValue == initialCountdown)
  }

  @Test("Cancellation during countdown")
  func stopDuringCountdownCancels() async {
    let recordingState = RecordingState(cameraService: nil)
    recordingState.shouldSkipCountdown = false
    recordingState.startRecording(isScreenSharing: false)
    #expect(recordingState.isPreparing)

    await withCheckedContinuation { continuation in
      recordingState.stopRecording { url in
        #expect(url == nil)
        continuation.resume()
      }
    }

    #expect(!recordingState.isPreparing)
    #expect(!recordingState.isRecording)
    #expect(recordingState.countdownValue == 0)
  }

  // MARK: - Stop Recording Tests

  @Test("Stop behavior when idle")
  func stopWhenNotRecordingDoesNothing() async {
    let recordingState = RecordingState(cameraService: nil)
    #expect(!recordingState.isRecording)

    await withCheckedContinuation { continuation in
      recordingState.stopRecording { _ in
        continuation.resume()
      }
    }

    #expect(!recordingState.isRecording)
  }

  // MARK: - Mic Toggle Tests

  @Test("Microphone toggle behavior")
  func toggleMic() {
    let recordingState = RecordingState(cameraService: nil)
    let initialState = recordingState.isMicActive

    recordingState.toggleMic()
    #expect(recordingState.isMicActive != initialState)

    recordingState.toggleMic()
    #expect(recordingState.isMicActive == initialState)
  }
}
