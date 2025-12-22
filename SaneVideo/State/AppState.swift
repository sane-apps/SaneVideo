//
//  AppState.swift
//  SaneVideo
//
//  Created by SaneVideo Refactor
//

import AVFoundation
import Combine
import SwiftUI

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

    var cameraEnabled = false // Toggle for camera overlay
    var microphoneEnabled = true // Toggle for microphone input

    // MARK: - Error Handling

    // Delegated to ServiceContainer.shared.errorPresenter

    // MARK: - Export Sheet (for ⌘E shortcut)

    var showExportSheet = false
    // MARK: - Timeline Selection (for multi-select and batch operations)

    var selectedClipIds: Set<UUID> = [] // Multi-select support for batch operations
    private var cancellables = Set<AnyCancellable>()

    init() {
        setupMode()
        setupEnvironment()
        setupStateCoordination()
        setupErrorHandling()
        
        NSLog("🚀 AppState: init completed (appMode: \(appMode))")
        AppLogger.general.info("🚀 AppState: init completed")
    }

    private func setupMode() {
        if TestEnvironment.shouldOpenEditor {
            AppLogger.general.info("🧪 AppState: Detected Editor Mode. Initializing .editing")
            NSLog("🧪 AppState: Detected Editor Mode. Initializing .editing")
            self.appMode = .editing
        } else {
            NSLog("🧪 AppState: Recording Mode (default)")
            self.appMode = .recording
        }
    }
    
    private func setupEnvironment() {
        self.isTesting = TestEnvironment.isUITesting
        TestEnvironment.logState()
        
        if isTesting {
             AppLogger.general.info("🧪 AppState: Test Environment Detected")
             NSLog("🧪 AppState: Test Environment Detected")
        } else {
             ServiceContainer.shared.audioService.start()
        }

        // Bootstrap if needed
        if TestEnvironment.shouldOpenEditor {
             NSLog("🧪 AppState: Calling bootstrapEditorForTesting()...")
             Task { 
                 await self.bootstrapEditorForTesting() 
             }
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
        
        let testAssetURL = TestEnvironment.mockAssetURL
        
        AppLogger.general.info("🧪 AppState: Bootstrapping editor...")
        
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
            AppLogger.general.info("🧪 Switched to Editing Mode and restored window. Project: \(projectName)")
            NSLog("🧪 Switched to Editing Mode and restored window. Project: \(projectName)")
        }
        
        // Final settle delay for UI layout
        try? await Task.sleep(nanoseconds: 1_000_000_000) // 1 second
        NSLog("🧪 AppState: Bootstrap complete and settled.")
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
                self.windowManager.forceHidePiPForSystemOverlay()
            } else {
                AppLogger.recording.info("✅ System Presenter Overlay Inactive. Restoring App PiP.")
                self.windowManager.updatePiPState(
                    isCameraActive: self.cameraState.isActive,
                    isRecording: self.recordingState.isRecording
                )
            }
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

    var isRecording: Bool { recordingState.isRecording }
    var isPreparing: Bool { recordingState.isPreparing }
    var isPaused: Bool { recordingState.isPaused }
    var isScreenSharing: Bool { windowManager.isScreenSharing }
    var isMicActive: Bool { recordingState.isMicActive }
    var recordingDuration: TimeInterval { recordingState.recordingDuration }

    /// Access to AudioService for microphone selection
    var audioService: AudioService { ServiceContainer.shared.audioService }

    var currentProject: VideoProject? { projectState.currentProject }
    var projects: [VideoProject] { projectState.projects }
    var recentlyAddedClip: VideoClip? { projectState.recentlyAddedClip }
    var showingImportPicker: Bool {
        get { projectState.showingImportPicker }
        set { projectState.showingImportPicker = newValue }
    }

    var screenPreviewLayer: AVSampleBufferDisplayLayer? { recordingState.screenPreviewLayer }

    // MARK: - Actions (Coordinated)

    func toggleRecording() {
        if recordingState.isRecording {
            stopRecording()
        } else {
            startRecording()
        }
    }

    func startRecording() {
        AppLogger.recording.info(" AppState: Initiating recording sequence...")

        // 1. Ensure camera is active if we are in camera mode (not screen sharing)
        // or if camera is enabled. (Skip during tests to avoid popups)
        let isTesting = ProcessInfo.processInfo.arguments.contains("-uitesting")
        if !isTesting && !windowManager.isScreenSharing && !cameraState.isActive {
            AppLogger.camera.info(" AppState: Auto-starting camera for recording")
            cameraEnabled = true
            cameraState.startCamera()
        }

        // 2. Start Recording via RecordingState (which handles countdown)
        recordingState.startRecording(isScreenSharing: windowManager.isScreenSharing)

        // 3. Hide App if Screen Sharing (so we don't record the window)
        if windowManager.isScreenSharing {
            // Use granular minimization so we don't hide the PiP window
            // No delay needed if we are just minimizing main window
            windowManager.minimizeMainWindow()
        }
    }

    func stopRecording() {
        // CRITICAL FIX: Ignore stop requests if we are already in editing mode (e.g. from phantom triggers)
        guard appMode == .recording else {
            AppLogger.recording.warning("🛑 AppState: stopRecording ignored (Mode is .editing)")
            return
        }
        
        // TRAP: If we are testing export workflow, we should NEVER stop recording in recording mode
        // (because we should be in editing mode, or not recording at all)
        let args = ProcessInfo.processInfo.arguments
        if args.contains("-ui_testing") && args.contains("-open_editor") {
             let trace = Thread.callStackSymbols.joined(separator: "\n")
             // Log first to ensure we catch it
             NSLog("❌ [FATAL] StopRecording called during Export Test! Stack:\n\(trace)")
             fatalError("TEST FAILURE: Unexpected stopRecording call during Export Workflow! Check console/crash logs.")
        }
        
        AppLogger.recording.info("📹 AppState: Stopping recording...")

        recordingState.stopRecording { [weak self] url in
            guard let self else { return }

            // ALWAYS close PiP and return to app, whether recording succeeded or not
            Task { @MainActor in
                // CRITICAL FIX: Restore Main Window FIRST to ensure app has a valid focus target
                // This prevents NSApp form trying to resurrect the closing PiP window as "Key Window"
                self.windowManager.restoreMainWindow()

                self.cameraState.stopCamera()
                self.cameraEnabled = false

                // Exit screen sharing mode automatically when recording stops
                if self.windowManager.isScreenSharing {
                    self.windowManager.isScreenSharing = false
                }

                self.windowManager.updatePiPState(isCameraActive: false, isRecording: false)
                self.windowManager.hideFloatingControls() // CRITICAL FIX: Ensure floating controls are hidden
            }

            if let url = url {
                Task { @MainActor in
                    AppLogger.general.info("📹 Recording saved to: \(url.path)")
                    self.handleRecordingFinished(url: url)
                }
            } else {
                AppLogger.general.warning("⚠️ No recording URL returned (recording may not have started)")
                // Suppress toast in test mode to avoid overlapping buttons
                let isTesting = TestEnvironment.isUITesting ||
                                UserDefaults.standard.bool(forKey: "ui_testing") || 
                                UserDefaults.standard.bool(forKey: "open_editor") ||
                                ProcessInfo.processInfo.arguments.contains("-ui_testing")
                
                if !isTesting {
                    Task { @MainActor in
                        ServiceContainer.shared.toastManager.show("⚠️ Recording cancelled or empty", type: .error)
                    }
                }
            }
        }
    }

    private func handleRecordingFinished(url: URL) {
        AppLogger.recording.info("📹 handleRecordingFinished called with: \(url.lastPathComponent)")

        // Stop camera to ensure user knows recording has finished
        cameraState.stopCamera()
        cameraEnabled = false

        // Hide PiP window since recording is done
        self.windowManager.updatePiPState(isCameraActive: false, isRecording: false)

        // Add to timeline
        Task { @MainActor in
            AppLogger.recording.info("📹 Starting new project and importing recording...")
            ServiceContainer.shared.toastManager.show("📹 Importing recording...")

            // IMPORTANT: Each recording starts a NEW project - don't mix with old timeline
            self.projectState.startNewProject()
            
            // Wait for project creation and state propagation
            try? await Task.sleep(nanoseconds: 100_000_000) // 100ms yield

            await self.projectState.addVideoToTimeline(url: url)

            AppLogger.recording.info("📹 Recording imported. Switching to editor...")

            // FORCE UI UPDATE: Ensure AppMode switches BEFORE restoring window
            self.switchToEditing()
            
            // Allow a brief moment for the view hierarchy to rebuild for editing mode
            try? await Task.sleep(nanoseconds: 200_000_000) // 200ms yield

            // CRITICAL: Bring app back to foreground so user can see the editor
            self.windowManager.restoreMainWindow()

            // Confirm to user
            ServiceContainer.shared.toastManager.show("✅ Recording imported!")
        }
    }

    func togglePause() {
        recordingState.togglePause(isScreenSharing: windowManager.isScreenSharing)
    }

    func toggleScreenShare() {
        // CRITICAL FIX: When turning OFF screen share, we must restore the main window
        // BEFORE hiding the PiP window. Otherwise, NSApp.windows iteration in restoreMainWindow
        // will encounter a deallocating window and crash with EXC_BAD_ACCESS.
        
        let wasScreenSharing = windowManager.isScreenSharing
        
        if wasScreenSharing {
            // Screen Share turning OFF:
            // 1. FIRST: Restore main window while PiP is still valid
            windowManager.restoreMainWindow()
            
            // 2. THEN: Toggle state and hide PiP
            windowManager.isScreenSharing = false
            windowManager.updatePiPState(isCameraActive: false, isRecording: recordingState.isRecording) // Force camera off in PiP when stopping screen share
            
            // 3. CRITICAL: Stop recording if it's running (User expectation: Stop Share = Stop Recording)
            if recordingState.isRecording {
                AppLogger.recording.info("🛑 AppState: Screen Share stopped. Stopping active recording.")
                toggleRecording()
            }
        } else {
            // Screen Share turning ON:
            // Normal order is fine
            windowManager.isScreenSharing = true
            windowManager.updatePiPState(isCameraActive: cameraState.isActive, isRecording: recordingState.isRecording)
            
            // Auto-start camera if needed for PiP
            if !cameraState.isActive {
                AppLogger.camera.info("AppState: Auto-starting camera for screen share PiP")
                cameraEnabled = true
                cameraState.startCamera()
            }
            
            // Hide main app, show PiP
            windowManager.minimizeMainWindow()
        }

        // If recording, switch the recording source
        if recordingState.isRecording {
            let newSource: RecordingSource = windowManager.isScreenSharing ? .screen : .camera
            AppLogger.recording.info("AppState: Switching recording source to \(newSource)")
            recordingState.switchSource(newSource)
        }
    }

    func toggleCamera() {
        cameraState.toggleCamera()
    }

    func toggleMic() {
        ServiceContainer.shared.logManager.logUserAction("Action Executed", details: "Toggle Mic")
        recordingState.toggleMic()
    }

    func importVideo() {
        ServiceContainer.shared.logManager.logUserAction("Action Executed", details: "Show Import Picker")
        projectState.showImportPicker()
    }

    func startNewRecording() {
        ServiceContainer.shared.logManager.logUserAction("Action Executed", details: "Start New Project")
        projectState.startNewProject()
    }

    func togglePiPVisibility() {
        ServiceContainer.shared.logManager.logUserAction("Action Executed", details: "Toggle PiP")
        Task { @MainActor in
            self.windowManager.togglePiPVisibility(
                isCameraActive: self.cameraState.isActive,
                isRecording: self.recordingState.isRecording
            )
        }
    }

    func addVideoToTimeline(url: URL) {
        ServiceContainer.shared.logManager.logUserAction("Action Executed", details: "Add Video: \(url.lastPathComponent)")
        Task { @MainActor in
            await projectState.addVideoToTimeline(url: url)
        }
    }

    // MARK: - Mode Switching

    func switchToRecording() {
        // DEBUG: Trap the ghost switch using NSLog since file system might be sandboxed
        let trace = Thread.callStackSymbols.joined(separator: "\n")
        NSLog("👻 [SWITCH_TO_RECORDING] Called! Stack Trace:\n\(trace)")
        
        // CRITICAL DEBUGER: If we are testing, this SHOULD NOT HAPPEN in the export workflow
        if ProcessInfo.processInfo.arguments.contains("-ui_testing") {
             // We allow it if explicitly testing recording workflow, but for now we suspect this is the bug
             // fatalError("TEST FAILURE: Unexpected switch to recording mode! \nStack: \(trace)") 
             // Commented out fatalError to rely on log first, or maybe we SHOULD crash to be sure?
             // Let's crash to get attention.
             fatalError("TEST FAILURE: Unexpected switch to recording mode! Check console logs for stack trace.")
        }

        // CRITICAL: Switch mode IMMEDIATELY for responsive UI
        appMode = .recording

        // Camera operations happen AFTER mode switch
        if !windowManager.isScreenSharing {
            cameraEnabled = true
            cameraState.startCamera()
        }
        
        // Start Audio for Metering
        audioService.start()
    }

    func switchToEditing() {
        // CRITICAL: Switch mode IMMEDIATELY for responsive UI
        appMode = .editing

        // Camera cleanup happens AFTER mode switch
        if !recordingState.isRecording {
            cameraEnabled = false
            cameraState.stopCamera()
            audioService.stop()
        }
    }
}
