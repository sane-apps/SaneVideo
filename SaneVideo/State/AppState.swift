import AVFoundation
import Combine
import SwiftUI

enum AutomationExportPathPolicy {
    static func resolveOutputURL(
        requestedURL: URL,
        fileManager: FileManager = .default,
        fallbackRoot: URL = FileManager.default.temporaryDirectory
            .appendingPathComponent("AutomationExports", isDirectory: true)
    ) -> URL {
        let requestedDirectory = requestedURL.deletingLastPathComponent()
        var isDirectory: ObjCBool = false
        let directoryExists = fileManager.fileExists(
            atPath: requestedDirectory.path,
            isDirectory: &isDirectory
        )

        if !directoryExists || !isDirectory.boolValue {
            try? fileManager.createDirectory(
                at: requestedDirectory,
                withIntermediateDirectories: true
            )
        }

        if fileManager.isWritableFile(atPath: requestedDirectory.path) {
            return requestedURL
        }

        try? fileManager.createDirectory(at: fallbackRoot, withIntermediateDirectories: true)
        return fallbackRoot.appendingPathComponent(requestedURL.lastPathComponent)
    }
}

@MainActor
@Observable
class AppState {
    enum AppMode {
        case recording
        case editing
    }

    // MARK: - App Mode

    var appMode: AppMode = .recording {
        didSet {
            // Every way into the editor releases the camera and mic, unless a recording is running.
            if appMode == .recording, oldValue == .editing {
                restoreCameraIfWanted()
                return
            }
            guard appMode == .editing, oldValue != .editing, !recordingState.isRecording else { return }
            cameraEnabled = false
            cameraState.stopCamera()
            audioService.stop()
        }
    }
    var isTesting: Bool = false
    @ObservationIgnored private var isBootstrapped = false

    // MARK: - Sub-States

    var recordingState = RecordingState()
    var projectState = ProjectState()
    var cameraState = CameraState()
    var windowManager = WindowManager()
    var playbackState = PlaybackState()

    // MARK: - Recording Settings

    /// User intent: setting it starts or stops the camera. Read cameraState.isActive to see whether it is running.
    var cameraEnabled = false {
        didSet {
            guard cameraEnabled != oldValue else { return }
            if cameraEnabled {
                cameraState.startCamera { [weak self] didStart in
                    guard let self else { return }
                    guard !didStart else { return }

                    Task { @MainActor in
                        if self.cameraEnabled {
                            self.cameraEnabled = false
                        }

                        if let error = self.cameraState.lastError {
                            ServiceContainer.shared.toastManager.show(error.localizedDescription, type: .error)
                        }
                    }
                }
            } else {
                cameraState.stopCamera()
            }
        }
    }

    // MARK: - Error Handling

    // Delegated to ServiceContainer.shared.errorPresenter

    // MARK: - Export Sheet (for ⌘E shortcut)

    var showExportSheet = false
    var showTeleprompterScriptSheet = false

    // MARK: - Quick Access Overlay (post-recording)

    var showQuickAccessOverlay = false
    var quickAccessRecordingURL: URL?
    var quickAccessThumbnail: NSImage?
    /// Turns the finished recording into a project; Edit and Share wait for it.
    var recordingImportTask: Task<Void, Never>?

    // MARK: - Timeline Selection (for multi-select and batch operations)

    var selectedClipIds: Set<UUID> = []

    // MARK: - Project Selection (for multi-select in project browser)

    var selectedProjectIds: Set<UUID> = []

    private var cancellables = Set<AnyCancellable>()

    func prepareCameraPreviewIfNeeded() {
        let permissionManager = ServiceContainer.shared.permissionManager
        permissionManager.checkCameraPermission()
    }

    init(recordingState: RecordingState? = nil) {
        if let injectedState = recordingState {
            self.recordingState = injectedState
        }

        setupMode()
        setupEnvironment()
        setupStateCoordination()
        setupErrorHandling()
        scheduleInitialRecordingPreviewRestore()

        NSLog("🚀 AppState: init completed (appMode: \(appMode))")
        AppLogger.general.info("🚀 AppState: init completed")
    }

    private func setupMode() {
        if TestEnvironment.shouldOpenEditor {
            AppLogger.general.info("🧪 AppState: Detected Editor Mode. Initializing .editing")
            NSLog("🧪 AppState: Detected Editor Mode. Initializing .editing")
            appMode = .editing
        } else {
            NSLog("🧪 AppState: Recording Mode (default)")
            appMode = .recording
        }
    }

    private func setupEnvironment() {
        isTesting = TestEnvironment.isTesting
        TestEnvironment.logState()

        if isTesting {
            AppLogger.general.info("🧪 AppState: Test Environment Detected")
            NSLog("🧪 AppState: Test Environment Detected")
        }

        if TestEnvironment.shouldOpenEditor {
            NSLog("🧪 AppState: Calling bootstrapEditorForTesting()...")
            Task {
                await self.bootstrapEditorForTesting()
            }
        }
    }

    private func scheduleInitialRecordingPreviewRestore() {
        guard LaunchRecordingPreviewPolicy.shouldScheduleRestore(
            appMode: appMode,
            isTesting: isTesting
        ) else { return }

        Task { @MainActor [weak self] in
            self?.prepareCameraPreviewIfNeeded()
            self?.restoreCameraIfWanted()
        }
    }

    /// Whether the person last left the camera on in the recorder. Defaults to on.
    static let cameraWantedKey = "RecorderCameraOn"

    /// Opening the recorder turns the camera back on, unless the person turned it off last time.
    /// Only runs when access is already granted, so it never raises a permission prompt.
    func restoreCameraIfWanted() {
        let wanted = UserDefaults.standard.object(forKey: Self.cameraWantedKey) as? Bool ?? true
        guard !isTesting, wanted, !isScreenSharing, !cameraEnabled,
              AVCaptureDevice.authorizationStatus(for: .video) == .authorized else { return }
        AppLogger.camera.info("Recorder opened: turning the camera on")
        cameraEnabled = true
    }

    // MARK: - Test Helpers

    func bootstrapEditorForTesting() async {
        guard !isBootstrapped else {
            NSLog("🧪 AppState: Already bootstrapped, skipping")
            return
        }
        isBootstrapped = true

        AppLogger.general.info("🧪 Bootstrapping Editor for UI Tests (REAL ASSET MODE)...")
        NSLog("🧪 Bootstrapping Editor for UI Tests (REAL ASSET MODE)...")

        AppLogger.general.info("🧪 AppState: Bootstrapping editor...")

        if let projectURL = TestEnvironment.bootstrapProjectURL {
            do {
                try projectState.openProjectFile(at: projectURL)
                AppLogger.general.info("🧪 Opened prepared project: \(projectURL.path)")
                NSLog("🧪 Opened prepared project: \(projectURL.path)")
            } catch {
                AppLogger.general.error("❌ AppState: Failed to open prepared project: \(error.localizedDescription)")
                NSLog("❌ AppState: Failed to open prepared project: \(error.localizedDescription)")
            }
        } else {
            let testAssetURL = TestEnvironment.mockAssetURL

            // Create the project first so the editor UI exists.
            projectState.startNewProject()

            if !FileManager.default.fileExists(atPath: testAssetURL.path) {
                AppLogger.general.error("❌ AppState: Test asset NOT FOUND at \(testAssetURL.path)")
                NSLog("❌ AppState: Test asset NOT FOUND at \(testAssetURL.path)")
            } else {
                // Use the normal import path so tracks and duration are valid.
                AppLogger.general.info("🧪 Importing test asset: \(testAssetURL.path)")
                NSLog("🧪 Importing test asset: \(testAssetURL.path)")
                await projectState.addVideoToTimeline(url: testAssetURL)
            }
        }

        await applyAutomationTranscriptCorrectionsIfNeeded()

        await MainActor.run {
            self.switchToEditing()
            self.windowManager.restoreMainWindow()

            // Select the new clip so the inspector tools show.
            if let firstClip = self.projectState.currentProject?.timeline.tracks.first?.clips.first {
                self.selectedClipIds = [firstClip.id]
                AppLogger.general.info("🧪 Explicitly selected clip: \(firstClip.id)")
            }

            let projectName = self.projectState.currentProject?.name ?? "nil"
            AppLogger.general.info(
                "🧪 Switched to Editing Mode and restored window. Project: \(projectName)"
            )
            NSLog("🧪 Switched to Editing Mode and restored window. Project: \(projectName)")
        }

        // Let the UI layout settle.
        try? await Task.sleep(nanoseconds: 1_000_000_000)
        applyAutomationRailStateIfNeeded()
        await runAutomationExportIfNeeded()
        NSLog("🧪 AppState: Bootstrap complete and settled.")
    }

    private func applyAutomationRailStateIfNeeded() {
        guard let railState = TestEnvironment.automationRailState else { return }
        activateAutomationRailState(railState)
    }

    /// Posts the same notification the matching left-rail control posts when clicked,
    /// so automation reaches pixel-identical UI state without synthetic clicks.
    func activateAutomationRailState(_ railState: AutomationRailState) {
        NotificationCenter.default.post(name: railState.notificationName, object: nil)
        AppLogger.general.info("🧪 Automation rail state activated: \(railState.rawValue)")
        NSLog(
            "🧪 Automation rail state activated: \(railState.rawValue) → \(railState.notificationName.rawValue)"
        )
    }

    private func applyAutomationTranscriptCorrectionsIfNeeded() async {
        guard let transcriptURL = TestEnvironment.automationTranscriptURL,
              let clip = projectState.currentProject?.timeline.tracks
              .flatMap(\.clips)
              .first
        else {
            return
        }

        do {
            try projectState.applyTranscriptCorrections(from: transcriptURL, to: clip)
            AppLogger.general.info("🧪 Applied transcript corrections from: \(transcriptURL.path)")
            NSLog("🧪 Applied transcript corrections from: \(transcriptURL.path)")
        } catch {
            AppLogger.general.error("❌ AppState: Transcript correction import failed: \(error.localizedDescription)")
            NSLog("❌ AppState: Transcript correction import failed: \(error.localizedDescription)")
        }
    }

    private func refineAutomationCaptionsIfNeeded() async {
        guard TestEnvironment.shouldRefineAutomationCaptions,
              let project = projectState.currentProject
        else {
            return
        }

        for clip in project.timeline.tracks.flatMap(\.clips) where !clip.captions.isEmpty {
            do {
                let refined = try await ServiceContainer.shared.aiService.refineCaptions(clip.captions)
                projectState.updateCaptions(for: clip, newCaptions: refined)
                AppLogger.general.info("🧪 Refined captions for clip: \(clip.id)")
                NSLog("🧪 Refined captions for clip: \(clip.id)")
            } catch {
                AppLogger.general.warning("⚠️ AppState: Caption refinement skipped: \(error.localizedDescription)")
                NSLog("⚠️ AppState: Caption refinement skipped: \(error.localizedDescription)")
            }
        }
    }

    private func setupStateCoordination() {
        recordingState.onRequestScreenShareStop = { [weak self] in
            if self?.windowManager.isScreenSharing == true {
                self?.toggleScreenShare()
            }
        }

        // isPresenterOverlayActive changes via an engine callback, and WindowManager has to react to it.
        recordingState.onPresenterOverlayChanged = { [weak self] isActive in
            guard let self else { return }

            if isActive {
                AppLogger.recording.info("⚠️ System Presenter Overlay Active. Hiding App PiP.")
                windowManager.forceHidePiPForSystemOverlay()
            } else {
                AppLogger.recording.info("✅ System Presenter Overlay Inactive. Restoring App PiP.")
                windowManager.updatePiPState(
                    isCameraActive: cameraState.isActive,
                    isRecording: recordingState.isRecording
                )
            }
        }

        recordingState.onRecordingStateChanged = { [weak self] _ in
            guard let self else { return }
            Task { @MainActor in
                self.windowManager.updatePiPState(
                    isCameraActive: self.cameraState.isActive,
                    isRecording: self.recordingState.isRecording
                )
            }
        }

        // Show PiP only after picker selection so it stays out of the picker's window list.
        recordingState.onContentSelected = { [weak self] in
            guard let self else { return }
            NSLog("🖥️ Content selected - NOW showing PiP window")
            windowManager.updatePiPState(
                isCameraActive: cameraState.isActive,
                isRecording: recordingState.isRecording
            )

            // Switch the source to screen if already recording; otherwise currentSource stays .camera and screen frames are dropped.
            if recordingState.isRecording {
                NSLog("🖥️ Already recording - switching source to screen")
                recordingState.switchSource(.screen)
                // Same as starting a screen recording: hide the app so its own window is not recorded.
                windowManager.minimizeMainWindow()
            }
        }
    }

    private func runAutomationExportIfNeeded() async {
        guard let requestedOutputURL = TestEnvironment.automationExportURL else { return }
        guard let project = projectState.currentProject else { return }

        do {
            let outputURL = AutomationExportPathPolicy.resolveOutputURL(requestedURL: requestedOutputURL)
            let outputDirectory = outputURL.deletingLastPathComponent()
            try FileManager.default.createDirectory(
                at: outputDirectory,
                withIntermediateDirectories: true
            )
            try? FileManager.default.removeItem(at: outputURL)

            let settings = SaneExportSettings(
                codec: .hevc,
                resolution: .hd1080,
                bitrate: 8_000_000,
                frameRate: 30.0
            )

            AppLogger.export.info("🧪 Automation export starting: \(outputURL.path)")
            NSLog("🧪 Automation export starting: \(outputURL.path)")
            if outputURL != requestedOutputURL {
                AppLogger.export.warning("🧪 Requested automation export path was not writable. Falling back to \(outputURL.path)")
                NSLog("🧪 Requested automation export path was not writable. Falling back to \(outputURL.path)")
            }

            _ = try await ServiceContainer.shared.exportService.export(
                project: project,
                settings: settings,
                outputURL: outputURL
            ) { progress in
                let percent = Int(progress * 100)
                AppLogger.export.info("🧪 Automation export progress: \(percent)%")
            }

            AppLogger.export.info("🧪 Automation export complete: \(outputURL.path)")
            NSLog("🧪 Automation export complete: \(outputURL.path)")
        } catch {
            AppLogger.export.error("🧪 Automation export failed: \(error.localizedDescription)")
            NSLog("🧪 Automation export failed: \(error.localizedDescription)")
        }

        if TestEnvironment.shouldQuitAfterAutomation {
            NSApplication.shared.terminate(nil)
        }
    }

    private func setupErrorHandling() {
        // RecordingState.setupRecordingEngine() owns the error handler, which turns permission prompts into toasts. Do not replace it here.
    }

    // MARK: - Proxy Properties (Backward Compatibility / Convenience)

    var isRecording: Bool {
        recordingState.isRecording
    }

    var isPreparing: Bool {
        recordingState.isPreparing
    }

    var isPaused: Bool {
        recordingState.isPaused
    }

    var isScreenSharing: Bool {
        windowManager.isScreenSharing
    }

    var isMicActive: Bool {
        recordingState.isMicActive
    }

    var recordingDuration: TimeInterval {
        recordingState.recordingDuration
    }

    var audioService: AudioService {
        ServiceContainer.shared.audioService
    }

    var currentProject: VideoProject? {
        projectState.currentProject
    }

    var projects: [VideoProject] {
        projectState.projects
    }

    var recentlyAddedClip: VideoClip? {
        projectState.recentlyAddedClip
    }

    var showingImportPicker: Bool {
        get { projectState.showingImportPicker }
        set { projectState.showingImportPicker = newValue }
    }

    var screenPreviewLayer: AVSampleBufferDisplayLayer? {
        recordingState.screenPreviewLayer
    }

    // MARK: - Actions (Coordinated)

    // Logic extracted to AppState+Actions.swift

    // MARK: - Mode Switching

    func switchToRecording() {
        appMode = .recording
    }

    func switchToEditing() {
        appMode = .editing
    }

    // MARK: - Persistence

    func saveCurrentState() {
        guard appMode == .editing, projectState.currentProject != nil else { return }

        let currentScroll = projectState.currentProject?.scrollOffset ?? 0.0
        let currentZoom = projectState.currentProject?.zoomLevel ?? 1.0

        projectState.updatePlaybackState(
            currentTime: playbackState.currentTime.seconds,
            scrollOffset: currentScroll,
            zoomLevel: currentZoom
        )

        AppLogger.general.info(
            "💾 AppState: Saved current state with time: \(playbackState.currentTime.seconds)"
        )
    }
}

enum RecordingCameraPreviewPolicy {
    static func wantsCameraPreview(
        isScreenSharing: Bool,
        cameraEnabled: Bool
    ) -> Bool {
        !isScreenSharing && cameraEnabled
    }
}

enum CameraPreviewStartupPolicy {
    static func shouldAutoStartOnAppear(
        isScreenSharing _: Bool,
        cameraStatus _: PermissionStatus,
        cameraEnabled _: Bool,
        cameraSurfaceVisible _: Bool
    ) -> Bool {
        false
    }
}

enum LaunchRecordingPreviewPolicy {
    static func shouldScheduleRestore(
        appMode: AppState.AppMode,
        isTesting: Bool
    ) -> Bool {
        appMode == .recording && !isTesting
    }
}
