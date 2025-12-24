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
                    // Delegate to AppState to show Quick Access Overlay
                    self.appState.handleRecordingFinished(url: url)
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

    // REMOVED: handleRecordingFinished now handled by AppState to show Quick Access Overlay

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
