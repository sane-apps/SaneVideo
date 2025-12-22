//
//  RecordingCoordinator.swift
//  SaneVideo
//
//  Created by SaneVideo Refactor
//

import Foundation
import SwiftUI

/// Manages the high-level orchestration of recording, window management, and camera states.
/// Decomposes the "God Mode" logic from AppState.
@MainActor
class RecordingCoordinator {
    private unowned let appState: AppState

    // Shortcuts to dependencies
    private var recordingState: RecordingState { appState.recordingState }
    private var cameraState: CameraState { appState.cameraState }
    private var windowManager: WindowManager { appState.windowManager }
    private var projectState: ProjectState { appState.projectState }

    init(appState: AppState) {
        self.appState = appState
    }

    // MARK: - Recording Actions

    func toggleRecording() {
        if recordingState.isRecording {
            stopRecording()
        } else {
            startRecording()
        }
    }

    func startRecording() {
        AppLogger.recording.info("🎬 Coordinator: Initiating recording sequence...")

        // 1. Ensure camera is active if needed
        if !windowManager.isScreenSharing, !cameraState.isActive {
            AppLogger.camera.info("🎬 Coordinator: Auto-starting camera for recording")
            appState.cameraEnabled = true
            cameraState.startCamera()
        }

        // 2. Start Recording via RecordingState (handles countdown & engine)
        recordingState.startRecording(isScreenSharing: windowManager.isScreenSharing)

        // 3. Window Management (Hide App if Screen Sharing)
        if windowManager.isScreenSharing {
            // Use granular minimization so we don't hide the PiP window
            windowManager.minimizeMainWindow()
        }
    }

    func stopRecording() {
        let trace = Thread.callStackSymbols.joined(separator: "\n")
        NSLog("🛑 [RecordingCoordinator] stopRecording called! Stack:\n\(trace)")

        // CRITICAL FIX: Ignore stop requests if we are already in editing mode
        // This prevents "Recording cancelled" errors when bootstrapping logic triggers cleanup
        guard appState.appMode == .recording else {
            AppLogger.recording.warning("🛑 Coordinator: stopRecording ignored (Mode is .editing)")
            return
        }

        AppLogger.recording.info("🎬 Coordinator: Stopping recording...")

        recordingState.stopRecording { [weak self] url in
            guard let self = self else { return }

            // ALWAYS cleanup UI state
            Task { @MainActor in
                self.performStopCleanup()
            }

            if let url = url {
                Task { @MainActor in
                    AppLogger.general.info("📹 Recording saved to: \(url.path)")
                    // Delegate to AppState or ProjectState for project creation
                    // Ideally this logic should be here or in ProjectCoordinator
                    self.handleRecordingFinished(url: url)
                }
            } else {
                AppLogger.general.warning("⚠️ No recording URL returned")
                Task { @MainActor in
                    ServiceContainer.shared.toastManager.show("⚠️ Recording cancelled or empty", type: .error)
                }
            }
        }
    }

    private func performStopCleanup() {
        cameraState.stopCamera()
        appState.cameraEnabled = false

        // Exit screen sharing mode automatically
        if windowManager.isScreenSharing {
            windowManager.isScreenSharing = false
        }

        windowManager.updatePiPState(isCameraActive: false, isRecording: false)

        // Bring app back to foreground
        windowManager.restoreMainWindow()
    }

    private func handleRecordingFinished(url: URL) {
        AppLogger.recording.info("🎬 Coordinator: Handling finished recording")

        // UI Cleanup (redundant but safe)
        cameraState.stopCamera()
        appState.cameraEnabled = false
        windowManager.updatePiPState(isCameraActive: false, isRecording: false)

        // Add to timeline
        Task { @MainActor in
            AppLogger.recording.info("📹 Starting new project and importing recording...")
            ServiceContainer.shared.toastManager.show("📹 Importing recording...")

            // Persistence Fix: Check if we already have an active project (e.g. user renamed it)
            if projectState.currentProject != nil {
                AppLogger.recording.info("📹 Adding recording to existing project")
            } else {
                projectState.startNewProject()
            }

            await projectState.addVideoToTimeline(url: url)

            AppLogger.recording.info("📹 Recording imported. Switching to editor...")

            // Auto-switch to editing mode
            appState.switchToEditing()

            // CRITICAL: Bring app back to foreground
            windowManager.restoreMainWindow()

            ServiceContainer.shared.toastManager.show("✅ Recording imported!")
        }
    }

    // MARK: - Screen Share Logic

    func toggleScreenShare() {
        // 1. Toggle the screen sharing state
        windowManager.toggleScreenShare(
            isRecording: recordingState.isRecording,
            isCameraActive: cameraState.isActive
        )

        // 2. Handle Window Visibility
        if windowManager.isScreenSharing {
            // Screen Share ON:
            // Auto-start camera if needed for PiP
            if !cameraState.isActive {
                AppLogger.camera.info("🎬 Coordinator: Auto-starting camera for screen share PiP")
                appState.cameraEnabled = true
                cameraState.startCamera()
            }

            // Hide main app, show PiP
            windowManager.minimizeMainWindow()

        } else {
            // Screen Share OFF:
            // Restore main app
            windowManager.restoreMainWindow()

            // Explicitly force PiP update
            windowManager.updatePiPState(isCameraActive: cameraState.isActive, isRecording: recordingState.isRecording)
        }

        // 3. If recording, switch the recording source
        if recordingState.isRecording {
            let newSource: RecordingSource = windowManager.isScreenSharing ? .screen : .camera
            AppLogger.recording.info("🎬 Coordinator: Switching recording source to \(newSource)")
            recordingState.switchSource(newSource)
        }
    }
}
