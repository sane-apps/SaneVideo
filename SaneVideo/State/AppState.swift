//
//  AppState.swift
//  SaneVideo
//
//  Created by SaneVideo Refactor
//

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

    var appMode: AppMode = .recording
    var isTesting: Bool = false
    @ObservationIgnored private var isBootstrapped = false

    // MARK: - Sub-States

    var recordingState = RecordingState()
    var projectState = ProjectState()
    var cameraState = CameraState()
    var windowManager = WindowManager()
    var playbackState = PlaybackState()

    // MARK: - Recording Settings

    /// User's intent for camera state - setting this automatically starts/stops camera
    /// Use cameraState.isActive to check if camera is actually running
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

    // microphoneEnabled removed - use isMicActive proxy (delegates to RecordingState.isMicActive)

    // MARK: - Error Handling

    // Delegated to ServiceContainer.shared.errorPresenter

    // MARK: - Export Sheet (for ⌘E shortcut)

    var showExportSheet = false
    var showDemoStudioSheet = false

    // MARK: - Quick Access Overlay (post-recording)

    var showQuickAccessOverlay = false
    var quickAccessRecordingURL: URL?
    var quickAccessThumbnail: NSImage?

    // MARK: - Timeline Selection (for multi-select and batch operations)

    var selectedClipIds: Set<UUID> = [] // Multi-select support for batch operations

    // MARK: - Project Selection (for multi-select in project browser)

    var selectedProjectIds: Set<UUID> = [] // Multi-select support for bulk project operations

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

        // Bootstrap if needed
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
        }
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

            // Create Project IMMEDATELY so UI exists
            projectState.startNewProject()

            // Wait for file locally (idempotent setup)
            if !FileManager.default.fileExists(atPath: testAssetURL.path) {
                AppLogger.general.error("❌ AppState: Test asset NOT FOUND at \(testAssetURL.path)")
                NSLog("❌ AppState: Test asset NOT FOUND at \(testAssetURL.path)")
            } else {
                // Use STANDARD import logic to ensure everything (tracks, duration) is valid
                AppLogger.general.info("🧪 Importing test asset: \(testAssetURL.path)")
                NSLog("🧪 Importing test asset: \(testAssetURL.path)")
                await projectState.addVideoToTimeline(url: testAssetURL)
            }
        }

        await applyAutomationTranscriptCorrectionsIfNeeded()

        if TestEnvironment.shouldBuildCommentaryReelAutomatically {
            do {
                let reel = try projectState.buildCommentaryReel()
                AppLogger.general.info("🧪 Built commentary reel automatically: \(reel.name)")
                NSLog("🧪 Built commentary reel automatically: \(reel.name)")
                await refineAutomationCaptionsIfNeeded()
            } catch {
                AppLogger.general.error("❌ AppState: Commentary reel automation failed: \(error.localizedDescription)")
                NSLog("❌ AppState: Commentary reel automation failed: \(error.localizedDescription)")
            }
        }

        // Switch Mode
        await MainActor.run {
            self.switchToEditing()
            self.windowManager.restoreMainWindow()

            // Explicitly select the newly added clip to reveal inspector tools
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

        // Final settle delay for UI layout
        try? await Task.sleep(nanoseconds: 1_000_000_000) // 1 second
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

    // REMOVED: generateTestVideo and createTestPixelBuffer to avoid AVAssetWriter hangs

    private func setupStateCoordination() {
        // 1. Listen for External Screen Stop Requests
        recordingState.onRequestScreenShareStop = { [weak self] in
            // Only toggle if currently sharing
            if self?.windowManager.isScreenSharing == true {
                self?.toggleScreenShare()
            }
        }

        // 2. Coordinate dependencies using Async tasks or direct triggers
        // Note: View rendering is now automatic due to @Observable.
        // Action-based coordination (PiP updates) is mostly handled in the action methods themselves.

        // We still need to react to isPresenterOverlayActive which changes via engine callback
        // This is set in RecordingState but we need side effects in AppState (WindowManager)
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

        // 3. Listen for Recording State changes (Automatic PiP Update)
        recordingState.onRecordingStateChanged = { [weak self] _ in
            guard let self else { return }
            Task { @MainActor in
                self.windowManager.updatePiPState(
                    isCameraActive: self.cameraState.isActive,
                    isRecording: self.recordingState.isRecording
                )
            }
        }

        // 4. Listen for Content Selection (Show PiP after picker selection)
        // This prevents PiP from appearing in the picker's window list
        recordingState.onContentSelected = { [weak self] in
            guard let self else { return }
            NSLog("🖥️ Content selected - NOW showing PiP window")
            windowManager.updatePiPState(
                isCameraActive: cameraState.isActive,
                isRecording: recordingState.isRecording
            )

            // CRITICAL FIX: If already recording, switch source to screen
            // Without this, currentSource stays .camera and screen frames are filtered out
            if recordingState.isRecording {
                NSLog("🖥️ Already recording - switching source to screen")
                recordingState.switchSource(.screen)
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
        // NOTE: Error handling is configured in RecordingState.setupRecordingEngine()
        // That handler intelligently filters permission prompts (shows toast instead of alert)
        // and only forwards actual errors to ErrorPresenter.
        //
        // Previously this method overwrote that handler, causing duplicate/incorrect alerts.
        // Now we rely on RecordingState's nuanced error handling.
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

    /// Access to AudioService for microphone selection
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
        // DEBUG: Log the switch for diagnostic visibility
        let trace = Thread.callStackSymbols.suffix(10).joined(separator: "\n")
        AppLogger.general.info("🔄 AppState: Switching to RECORDING mode. Stack: \(trace)")

        // CRITICAL: Switch mode IMMEDIATELY for responsive UI
        appMode = .recording
    }

    func switchToEditing() {
        // CRITICAL: Switch mode IMMEDIATELY for responsive UI
        appMode = .editing

        // Camera cleanup happens AFTER mode switch
        // cameraEnabled setter automatically stops camera
        if !recordingState.isRecording {
            cameraEnabled = false
            audioService.stop()
        }
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
