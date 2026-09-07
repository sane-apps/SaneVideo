import CoreMedia
import Foundation
import Testing

@testable import SaneVideo

@Suite("Teleprompter Action Tests")
@MainActor
struct TeleprompterActionTests {
    @Test("Recording mode launch keeps audio service idle until user action")
    func recordingModeLaunchKeepsAudioIdle() async {
        let appState = AppState()

        #expect(appState.appMode == .recording)
        #expect(appState.audioService.isRunning == false)
        #expect(appState.cameraEnabled == false)
    }

    @Test("Switching back to recording mode does not auto-enable camera or microphone service")
    func switchToRecordingStaysIdle() async {
        let appState = AppState()

        appState.cameraEnabled = true
        appState.switchToEditing()
        appState.switchToRecording()

        #expect(appState.appMode == .recording)
        #expect(appState.cameraEnabled == false)
        #expect(appState.audioService.isRunning == false)
    }

    @Test("Teleprompter without notes shows toast and does not open Demo Studio")
    func teleprompterWithoutNotesShowsToastOnly() async {
        let appState = AppState()
        let toastManager = ServiceContainer.shared.toastManager
        toastManager.clear()
        try? await Task.sleep(nanoseconds: 50_000_000)
        toastManager.clear()

        #expect(appState.currentProject == nil)
        #expect(appState.showDemoStudioSheet == false)

        appState.toggleTeleprompter()

        let expectedToast = "Add teleprompter text in Demo Studio first."
        for _ in 0 ..< 10 where toastManager.toastMessage != expectedToast {
            try? await Task.sleep(nanoseconds: 50_000_000)
        }

        #expect(appState.currentProject != nil)
        #expect(appState.showDemoStudioSheet == false)
        #expect(appState.currentProject?.speakerNotes.isVisible == false)
        #expect(toastManager.toastMessage == expectedToast)

        toastManager.clear()
    }

    @Test("New Recording returns to recording mode and creates a fresh project")
    func newRecordingRestoresRecordingWorkflow() async {
        let appState = AppState()

        appState.switchToEditing()
        #expect(appState.appMode == .editing)

        appState.startNewRecording()

        #expect(appState.appMode == .recording)
        #expect(appState.currentProject != nil)
    }

    @Test("Import blocks document commands without deferring them until dismissal")
    func importDoesNotQueueProjectCommands() {
        let appState = AppState()
        appState.projectState = ProjectState(projectStore: MockProjectStore())
        appState.projectState.startNewProject()
        let originalID = appState.currentProject?.id
        var showGIF = false

        appState.importVideo()
        #expect(!appState.projectCommandsEnabled)
        appState.performProjectCommand { showGIF = true }
        appState.performProjectCommand { appState.startNewRecording() }
        #expect(!showGIF)
        #expect(appState.currentProject?.id == originalID)

        appState.showingImportPicker = false
        #expect(appState.projectCommandsEnabled)
        #expect(!showGIF)
        appState.performProjectCommand { showGIF = true }
        #expect(showGIF)
        appState.performProjectCommand { appState.startNewRecording() }
        #expect(appState.currentProject?.id != originalID)
    }

    @Test("Import appends to a restored project; New Recording isolates the next clip")
    func restoredProjectAndFreshRecordingStaySeparate() async throws {
        let appState = AppState()
        appState.projectState = ProjectState(projectStore: MockProjectStore())
        appState.projectState.startNewProject()
        let originalClip = VideoClip(url: TestEnvironment.mockAssetURL,
                                     duration: CMTime(seconds: 2, preferredTimescale: 600))
        appState.projectState.addClip(originalClip)
        let restored = try #require(appState.currentProject)
        appState.projectState.openProject(restored)
        appState.switchToRecording()

        await appState.projectState.addVideoToTimeline(url: TestEnvironment.mockAssetURL)
        let appended = try #require(appState.currentProject)
        #expect(appended.id == restored.id)
        #expect(appended.timeline.tracks.flatMap(\.clips).count == 2)
        #expect(appended.timeline.tracks.flatMap(\.clips).first?.id == originalClip.id)

        appState.startNewRecording()
        let freshID = try #require(appState.currentProject?.id)
        #expect(freshID != restored.id)
        #expect(appState.currentProject?.timeline.tracks.flatMap(\.clips).isEmpty == true)
        appState.projectState.addClip(originalClip)
        #expect(appState.currentProject?.id == freshID)
        #expect(appState.currentProject?.timeline.tracks.flatMap(\.clips).count == 1)
        appState.projectState.openProject(appended)
        #expect(appState.currentProject?.id == restored.id)
        #expect(appState.currentProject?.timeline.tracks.flatMap(\.clips).count == 2)
    }

    @Test("Importing a video from AppState switches into editing mode")
    func importingVideoTransitionsToEditor() async {
        let appState = AppState()
        let testURL = TestEnvironment.mockAssetURL

        #expect(FileManager.default.fileExists(atPath: testURL.path))

        appState.switchToRecording()
        appState.addVideoToTimeline(url: testURL)

        for _ in 0 ..< 40 where appState.appMode != .editing {
            try? await Task.sleep(nanoseconds: 100_000_000)
        }

        #expect(appState.appMode == .editing)
        #expect(appState.currentProject != nil)
        #expect(appState.currentProject?.timeline.tracks.flatMap(\.clips).isEmpty == false)
    }

    @Test("Camera start failure unwinds presenter mode and shows an error toast")
    func cameraStartFailureReturnsToIdle() async {
        let toastManager = ServiceContainer.shared.toastManager
        toastManager.clear()
        let originalHardwareFlag = ProcessInfo.processInfo.environment["SANEVIDEO_ENABLE_HARDWARE_TESTS"]

        setenv("SANEVIDEO_ENABLE_HARDWARE_TESTS", "1", 1)
        defer {
            if let originalHardwareFlag {
                setenv("SANEVIDEO_ENABLE_HARDWARE_TESTS", originalHardwareFlag, 1)
            } else {
                unsetenv("SANEVIDEO_ENABLE_HARDWARE_TESTS")
            }
        }

        let mockCamera = CameraServiceProtocolMock()
        mockCamera.lastError = .cameraPermissionDenied
        mockCamera.startHandler = {
            throw AppError.cameraPermissionDenied
        }

        let appState = AppState()
        appState.cameraState = CameraState(
            cameraService: mockCamera,
            audioService: MockAudioService(permissionManager: ServiceContainer.shared.permissionManager)
        )

        appState.cameraEnabled = true

        try? await Task.sleep(nanoseconds: 350_000_000)

        #expect(appState.cameraEnabled == false)
        #expect(appState.cameraState.isActive == false)
        #expect(toastManager.toastMessage == AppError.cameraPermissionDenied.localizedDescription)

        toastManager.clear()
    }

    @Test("Camera toggle uses the shared camera intent path")
    func cameraToggleUsesSharedIntent() async {
        let originalHardwareFlag = ProcessInfo.processInfo.environment["SANEVIDEO_ENABLE_HARDWARE_TESTS"]

        setenv("SANEVIDEO_ENABLE_HARDWARE_TESTS", "1", 1)
        defer {
            if let originalHardwareFlag {
                setenv("SANEVIDEO_ENABLE_HARDWARE_TESTS", originalHardwareFlag, 1)
            } else {
                unsetenv("SANEVIDEO_ENABLE_HARDWARE_TESTS")
            }
        }

        let mockCamera = CameraServiceProtocolMock()
        mockCamera.startHandler = {
            await MainActor.run {
                mockCamera.isActive = true
                mockCamera.isActivePublisherSubject.send(true)
            }
        }

        let appState = AppState()
        appState.cameraState = CameraState(
            cameraService: mockCamera,
            audioService: MockAudioService(permissionManager: ServiceContainer.shared.permissionManager)
        )

        appState.toggleCamera()
        try? await Task.sleep(nanoseconds: 200_000_000)

        #expect(appState.cameraEnabled == true)
        #expect(mockCamera.startCallCount == 1)
        #expect(mockCamera.toggleCallCount == 0)

        mockCamera.isActive = true
        appState.toggleCamera()
        try? await Task.sleep(nanoseconds: 200_000_000)

        #expect(appState.cameraEnabled == false)
        #expect(mockCamera.stopCallCount == 1)
        #expect(mockCamera.toggleCallCount == 0)
    }
}
