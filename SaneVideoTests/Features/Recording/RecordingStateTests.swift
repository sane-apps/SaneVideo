import AVFoundation
import Foundation
import Testing

@testable import SaneVideo

/// Countdown and permission work runs in tasks; wait for the state instead of a fixed delay.
@MainActor
private func waitUntil(timeout: Duration = .seconds(3), _ condition: () -> Bool) async -> Bool {
    let clock = ContinuousClock()
    let deadline = clock.now.advanced(by: timeout)
    while !condition() {
        if clock.now >= deadline { return false }
        try? await Task.sleep(for: .milliseconds(5))
    }
    return true
}

@Suite("Recording State Tests")
@MainActor
struct RecordingStateTests {
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

    @Test("Promptable permissions resolve before countdown starts")
    func startRecordingRequestsPromptablePermissionsBeforeCountdown() async {
        let permissionManager = PermissionManagerProtocolMock(
            cameraStatus: .notDetermined,
            microphoneStatus: .notDetermined,
            screenRecordingStatus: .granted
        )
        permissionManager.verifyPermissionsForRecordingHandler = { requiresCamera, requiresMicrophone, requiresScreenRecording in
            MainActor.assumeIsolated {
                !requiresScreenRecording
                    && (!requiresCamera || permissionManager.cameraStatus == .granted)
                    && (!requiresMicrophone || permissionManager.microphoneStatus == .granted)
            }
        }
        permissionManager.requestCameraPermissionHandler = {
            await MainActor.run {
                permissionManager.cameraStatus = .granted
            }
            return true
        }
        permissionManager.requestMicrophonePermissionHandler = {
            await MainActor.run {
                permissionManager.microphoneStatus = .granted
            }
            return true
        }

        let recordingState = RecordingState(
            cameraService: nil,
            permissionManager: permissionManager
        )
        recordingState.shouldSkipCountdown = false
        recordingState.startRecording(isScreenSharing: false)

        #expect(recordingState.isPreparing)
        #expect(recordingState.countdownValue == 0, "Countdown should wait for permission prompts")

        let countdownStarted = await waitUntil { recordingState.countdownValue == 3 }

        #expect(permissionManager.requestCameraPermissionCallCount == 1)
        #expect(permissionManager.requestMicrophonePermissionCallCount == 1)
        #expect(countdownStarted, "Countdown should start after permissions are granted")
    }

    @Test("Screen recording without camera overlay skips camera permission preflight")
    func screenRecordingWithoutCameraOverlaySkipsCameraPermissionPreflight() async {
        let permissionManager = PermissionManagerProtocolMock(
            cameraStatus: .notDetermined,
            microphoneStatus: .granted,
            screenRecordingStatus: .granted
        )
        permissionManager.verifyPermissionsForRecordingHandler = { requiresCamera, requiresMicrophone, requiresScreenRecording in
            !requiresCamera && requiresMicrophone && requiresScreenRecording
        }

        let recordingState = RecordingState(
            cameraService: nil,
            permissionManager: permissionManager
        )
        recordingState.shouldSkipCountdown = false
        recordingState.startRecording(isScreenSharing: true, includeCameraOverlay: false)

        #expect(permissionManager.requestCameraPermissionCallCount == 0)
        #expect(recordingState.isPreparing)
        #expect(recordingState.countdownValue == 3)
    }

    @Test("Muted recordings skip microphone permission preflight")
    func mutedRecordingSkipsMicrophonePermissionPreflight() async {
        let permissionManager = PermissionManagerProtocolMock(
            cameraStatus: .granted,
            microphoneStatus: .notDetermined,
            screenRecordingStatus: .granted
        )
        permissionManager.verifyPermissionsForRecordingHandler = { requiresCamera, requiresMicrophone, requiresScreenRecording in
            requiresCamera && !requiresMicrophone && !requiresScreenRecording
        }

        let recordingState = RecordingState(
            cameraService: nil,
            permissionManager: permissionManager
        )
        recordingState.toggleMic()
        recordingState.shouldSkipCountdown = false
        recordingState.startRecording(isScreenSharing: false)

        #expect(permissionManager.requestMicrophonePermissionCallCount == 0)
        #expect(recordingState.isPreparing)
        #expect(recordingState.countdownValue == 3)
    }

    @Test("Live microphone permission refresh skips stale inline prompt")
    func refreshedMicrophonePermissionSkipsPrompt() async {
        let permissionManager = PermissionManagerProtocolMock(
            cameraStatus: .granted,
            microphoneStatus: .notDetermined,
            screenRecordingStatus: .granted
        )
        permissionManager.checkMicrophonePermissionHandler = {
            MainActor.assumeIsolated {
                permissionManager.microphoneStatus = .granted
            }
        }
        permissionManager.verifyPermissionsForRecordingHandler = { requiresCamera, requiresMicrophone, requiresScreenRecording in
            MainActor.assumeIsolated {
                requiresCamera
                    && requiresMicrophone
                    && !requiresScreenRecording
                    && permissionManager.cameraStatus == .granted
                    && permissionManager.microphoneStatus == .granted
            }
        }

        let recordingState = RecordingState(
            cameraService: nil,
            permissionManager: permissionManager
        )
        recordingState.shouldSkipCountdown = false
        recordingState.startRecording(isScreenSharing: false)

        await Task.yield()

        #expect(permissionManager.checkMicrophonePermissionCallCount == 1)
        #expect(permissionManager.requestMicrophonePermissionCallCount == 0)
        #expect(recordingState.isPreparing)
        #expect(recordingState.countdownValue == 3)
    }

    @Test("Denied microphone does not block recording: it records without sound and opens no settings")
    func deniedMicrophoneRecordsWithoutSound() {
        let permissionManager = PermissionManagerProtocolMock(
            cameraStatus: .granted,
            microphoneStatus: .denied,
            screenRecordingStatus: .granted
        )
        permissionManager.verifyPermissionsForRecordingHandler = { _, requiresMicrophone, _ in !requiresMicrophone }

        let recordingState = RecordingState(
            cameraService: nil,
            permissionManager: permissionManager
        )
        recordingState.shouldSkipCountdown = false
        recordingState.startRecording(isScreenSharing: false)

        #expect(recordingState.isMicActive == false)
        #expect(permissionManager.verifyPermissionsForRecordingArgValues.last?.requiresMicrophone == false)
        #expect(permissionManager.openMicrophoneSettingsCallCount == 0)
        #expect(recordingState.isPreparing)
    }

    @Test("Denied camera opens camera settings")
    func deniedCameraOpensCameraSettings() {
        let permissionManager = PermissionManagerProtocolMock(
            cameraStatus: .denied,
            microphoneStatus: .granted,
            screenRecordingStatus: .granted
        )
        permissionManager.verifyPermissionsForRecordingHandler = { _, _, _ in false }

        let recordingState = RecordingState(
            cameraService: nil,
            permissionManager: permissionManager
        )
        recordingState.shouldSkipCountdown = false
        recordingState.startRecording(isScreenSharing: false)

        #expect(permissionManager.openCameraSettingsCallCount == 1)
        #expect(permissionManager.openMicrophoneSettingsCallCount == 0)
    }

    @Test("A failed check after the inline permission prompt does not leave Record stuck preparing")
    func failedCheckAfterPromptClearsPreparing() async {
        let permissionManager = PermissionManagerProtocolMock(
            cameraStatus: .granted,
            microphoneStatus: .notDetermined,
            screenRecordingStatus: .granted
        )
        permissionManager.requestMicrophonePermissionHandler = { true }
        permissionManager.verifyPermissionsForRecordingHandler = { _, _, _ in false }

        let recordingState = RecordingState(
            cameraService: nil,
            permissionManager: permissionManager
        )
        recordingState.shouldSkipCountdown = false
        recordingState.startRecording(isScreenSharing: false)

        let cleared = await waitUntil { !recordingState.isPreparing }
        #expect(cleared, "Left preparing, every later Record press is ignored until relaunch")
    }

    /// A state that starts a test-mode take at once: permissions granted, no countdown.
    private func makeReadyToRecordState() -> RecordingState {
        let permissionManager = PermissionManagerProtocolMock(
            cameraStatus: .granted,
            microphoneStatus: .granted,
            screenRecordingStatus: .granted
        )
        permissionManager.verifyPermissionsForRecordingHandler = { _, _, _ in true }
        let recordingState = RecordingState(cameraService: nil, permissionManager: permissionManager)
        recordingState.shouldSkipCountdown = true
        return recordingState
    }

    private func waitForEngine(_ engine: RecordingEngine, recording: Bool, paused: Bool) async -> Bool {
        for _ in 0 ..< 300 {
            if await engine.isRecording == recording, await engine.isPaused == paused { return true }
            try? await Task.sleep(for: .milliseconds(10))
        }
        return false
    }

    @Test("A take the engine ends itself (capture error) is handed over with its file and leaves recording")
    func engineEndedTakeIsHandedOver() async throws {
        let recordingState = makeReadyToRecordState()
        var handedOver: [URL?] = []
        recordingState.onRecordingEndedUnexpectedly = { url in handedOver.append(url) }
        recordingState.startRecording(isScreenSharing: false)
        let engine = try #require(recordingState.recordingEngine)
        #expect(await waitForEngine(engine, recording: true, paused: false))

        engine.handleSessionRuntimeError(notification: Notification(
            name: AVCaptureSession.runtimeErrorNotification,
            object: nil,
            userInfo: [AVCaptureSessionErrorKey: NSError(domain: AVFoundationErrorDomain, code: -11819)]
        ))

        #expect(await waitUntil { !handedOver.isEmpty })
        let url = try #require(handedOver.first ?? nil, "The finished file goes to the app to import")
        #expect(url.pathExtension == "mp4")
        #expect(!recordingState.isRecording)
    }

    @Test("When the engine pauses itself (sleep), the controls show paused and Resume resumes it")
    func systemPauseSyncsControls() async throws {
        let recordingState = makeReadyToRecordState()
        recordingState.startRecording(isScreenSharing: false)
        let engine = try #require(recordingState.recordingEngine)
        #expect(await waitForEngine(engine, recording: true, paused: false))

        engine.handleSleep()

        #expect(await waitUntil { recordingState.isPaused })
        recordingState.togglePause(isScreenSharing: false)
        #expect(!recordingState.isPaused)
        #expect(await waitForEngine(engine, recording: true, paused: false), "Resume must resume the engine, not pause it again")

        await withCheckedContinuation { continuation in
            recordingState.stopRecording { _ in continuation.resume() }
        }
    }

    @Test("Cancellation during countdown")
    func stopDuringCountdownCancels() async {
        let recordingState = RecordingState(cameraService: nil)
        recordingState.shouldSkipCountdown = false
        recordingState.startRecording(isScreenSharing: false)
        #expect(recordingState.isPreparing)

        await withCheckedContinuation { continuation in
            Task { @MainActor in
                recordingState.stopRecording { url in
                    #expect(url == nil)
                    continuation.resume()
                }
            }
        }

        #expect(!recordingState.isPreparing)
        #expect(!recordingState.isRecording)
        #expect(recordingState.countdownValue == 0)
    }

    @Test("Countdown tasks do not retain recording state after test teardown")
    func countdownTaskDoesNotRetainRecordingState() async {
        weak var weakState: RecordingState?

        do {
            var recordingState: RecordingState? = RecordingState(cameraService: nil)
            recordingState?.shouldSkipCountdown = false
            recordingState?.startRecording(isScreenSharing: false)
            weakState = recordingState
            recordingState = nil
        }

        let released = await waitUntil { weakState == nil }
        #expect(released)
    }

    // MARK: - Stop Recording Tests

    @Test("Stop behavior when idle")
    func stopWhenNotRecordingDoesNothing() async {
        let recordingState = RecordingState(cameraService: nil)
        #expect(!recordingState.isRecording)

        await withCheckedContinuation { continuation in
            Task { @MainActor in
                recordingState.stopRecording { _ in
                    continuation.resume()
                }
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
