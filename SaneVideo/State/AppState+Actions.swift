//
//  AppState+Actions.swift
//  SaneVideo
//
//  Created by Antigravity
//

import AVFoundation
import Foundation
import SwiftUI

extension AppState {

  // MARK: - Recording Actions

  func toggleRecording() {
    if recordingState.isRecording {
      stopRecording()
    } else {
      startRecording()
    }
  }

  func startRecording() {
    AppLogger.recording.info("🔴 AppState: Initiating recording sequence...")

    // 1. Ensure camera is active if we are in camera mode (not screen sharing)
    // or if camera is enabled. (Skip during tests to avoid popups)
    let isTesting = ProcessInfo.processInfo.arguments.contains("-uitesting")
    if !isTesting && !windowManager.isScreenSharing && !cameraState.isActive {
      AppLogger.camera.info("📷 AppState: Auto-starting camera for recording")
      cameraEnabled = true
      cameraState.startCamera()
    }

    // 2. Start Recording via RecordingState (which handles countdown)
    recordingState.startRecording(isScreenSharing: windowManager.isScreenSharing)

    // 3. Hide App if Screen Sharing (so we don't record the window)
    if windowManager.isScreenSharing {
      windowManager.minimizeMainWindow()
    }
  }

  func stopRecording() {
    // CRITICAL FIX: Ignore stop requests if we are already in editing mode
    guard appMode == .recording else {
      AppLogger.recording.warning("🛑 AppState: stopRecording ignored (Mode is .editing)")
      return
    }

    AppLogger.recording.info("📹 AppState: Stopping recording...")

    recordingState.stopRecording { [weak self] url in
      guard let self else { return }

      // ALWAYS close PiP and return to app
      Task { @MainActor in
        self.windowManager.restoreMainWindow()
        self.cameraState.stopCamera()
        self.cameraEnabled = false

        if self.windowManager.isScreenSharing {
          self.windowManager.isScreenSharing = false
        }

        self.windowManager.updatePiPState(isCameraActive: false, isRecording: false)
        self.windowManager.hideFloatingControls()
      }

      if let url = url {
        Task { @MainActor in
          AppLogger.general.info("📹 Recording saved to: \(url.path)")
          self.handleRecordingFinished(url: url)
        }
      } else {
        AppLogger.general.warning("⚠️ No recording URL returned")
        let isTesting = TestEnvironment.isUITesting
        if !isTesting {
          Task { @MainActor in
            ServiceContainer.shared.toastManager.show(
              "⚠️ Recording cancelled or empty", type: .error)
          }
        }
      }
    }
  }

  func handleRecordingFinished(url: URL) {
    AppLogger.recording.info("📹 handleRecordingFinished called with: \(url.lastPathComponent)")

    cameraState.stopCamera()
    cameraEnabled = false
    self.windowManager.updatePiPState(isCameraActive: false, isRecording: false)

    Task { @MainActor in
      AppLogger.recording.info("📹 Starting new project and importing recording...")
      ServiceContainer.shared.toastManager.show("📹 Importing recording...")

      self.projectState.startNewProject()
      try? await Task.sleep(nanoseconds: 100_000_000)

      await self.projectState.addVideoToTimeline(url: url)

      AppLogger.recording.info("📹 Recording imported. Switching to editor...")
      self.switchToEditing()
      try? await Task.sleep(nanoseconds: 200_000_000)

      self.windowManager.restoreMainWindow()
      ServiceContainer.shared.toastManager.show("✅ Recording imported!")
    }
  }

  // MARK: - Coordination Actions

  func togglePause() {
    recordingState.togglePause(isScreenSharing: windowManager.isScreenSharing)
  }

  func toggleScreenShare() {
    let wasScreenSharing = windowManager.isScreenSharing

    if wasScreenSharing {
      windowManager.restoreMainWindow()
      windowManager.isScreenSharing = false
      windowManager.updatePiPState(
        isCameraActive: cameraState.isActive,
        isRecording: recordingState.isRecording
      )
    } else {
      windowManager.isScreenSharing = true

      var effectiveCameraActive = cameraState.isActive
      if !cameraState.isActive {
        AppLogger.camera.info("AppState: Auto-starting camera for screen share PiP")
        cameraEnabled = true
        cameraState.startCamera()
        effectiveCameraActive = true
      }

      windowManager.updatePiPState(
        isCameraActive: effectiveCameraActive,
        isRecording: recordingState.isRecording
      )
      windowManager.minimizeMainWindow()
    }

    if recordingState.isRecording {
      let newSource: RecordingSource = windowManager.isScreenSharing ? .screen : .camera
      recordingState.switchSource(newSource)

      let toastMessage = windowManager.isScreenSharing ? "🖥️ Screen Share Active" : "📷 Camera Active"
      ServiceContainer.shared.toastManager.show(toastMessage)
    }
  }

  func toggleCamera() {
    cameraState.toggleCamera()
  }

  func toggleMic() {
    recordingState.toggleMic()
  }

  func togglePiPVisibility() {
    Task { @MainActor in
      self.windowManager.togglePiPVisibility(
        isCameraActive: self.cameraState.isActive,
        isRecording: self.recordingState.isRecording
      )
    }
  }

  // MARK: - Project Actions

  func importVideo() {
    projectState.showImportPicker()
  }

  func startNewRecording() {
    projectState.startNewProject()
  }

  func addVideoToTimeline(url: URL) {
    Task { @MainActor in
      await projectState.addVideoToTimeline(url: url)
    }
  }
}
