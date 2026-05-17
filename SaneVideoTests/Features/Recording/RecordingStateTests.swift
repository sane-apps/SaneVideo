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

        await Task.yield()
        try? await Task.sleep(nanoseconds: 50_000_000)

        #expect(permissionManager.requestCameraPermissionCallCount == 1)
        #expect(permissionManager.requestMicrophonePermissionCallCount == 1)
        #expect(recordingState.countdownValue == 3, "Countdown should start after permissions are granted")
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

    @Test("Denied microphone opens microphone settings")
    func deniedMicrophoneOpensMicrophoneSettings() {
        let permissionManager = PermissionManagerProtocolMock(
            cameraStatus: .granted,
            microphoneStatus: .denied,
            screenRecordingStatus: .granted
        )
        permissionManager.verifyPermissionsForRecordingHandler = { _, _, _ in false }

        let recordingState = RecordingState(
            cameraService: nil,
            permissionManager: permissionManager
        )
        recordingState.shouldSkipCountdown = false
        recordingState.startRecording(isScreenSharing: false)

        #expect(permissionManager.openMicrophoneSettingsCallCount == 1)
        #expect(permissionManager.openCameraSettingsCallCount == 0)
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

        await Task.yield()
        try? await Task.sleep(nanoseconds: 50_000_000)

        #expect(weakState == nil)
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
