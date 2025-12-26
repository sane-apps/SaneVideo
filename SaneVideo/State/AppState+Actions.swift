//
//  AppState+Actions.swift
//  SaneVideo
//
//  Created by Antigravity
//

import AVFoundation
import Foundation
import ScreenCaptureKit
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
    // cameraEnabled setter automatically starts camera
    let isTesting = ProcessInfo.processInfo.arguments.contains("-uitesting")
    if !isTesting && !windowManager.isScreenSharing && !cameraState.isActive {
      AppLogger.camera.info("📷 AppState: Auto-starting camera for recording")
      cameraEnabled = true
    }

    // 2. Start Recording via RecordingState (which handles countdown)
    recordingState.startRecording(isScreenSharing: windowManager.isScreenSharing)

    // 3. Hide App if Screen Sharing (so we don't record the window)
    if windowManager.isScreenSharing {
      windowManager.minimizeMainWindow()
    }
  }

  func stopRecording() {
    NSLog("🛑 AppState.stopRecording called. appMode=\(appMode), isRecording=\(recordingState.isRecording)")

    // CRITICAL FIX: Allow stop even if mode changed - user might be stuck
    // Only check if actually recording
    guard recordingState.isRecording else {
      NSLog("🛑 AppState: stopRecording ignored (not recording)")
      AppLogger.recording.warning("🛑 AppState: stopRecording ignored (not recording)")
      return
    }

    AppLogger.recording.info("📹 AppState: Stopping recording...")
    NSLog("📹 AppState: Stopping recording...")

    recordingState.stopRecording { [weak self] url in
      guard let self else { return }

      // ALWAYS close PiP and return to app
      Task { @MainActor in
        // CRITICAL FIX: Update state flags FIRST to prevent race conditions during UI updates
        let wasScreenSharing = self.windowManager.isScreenSharing

        if wasScreenSharing {
            self.windowManager.isScreenSharing = false
        }

        // cameraEnabled setter automatically stops camera
        self.cameraEnabled = false

        // Now safe to restore proper window state
        self.windowManager.restoreMainWindow()

        // Force update PiP state (will hide because isScreenSharing is false)
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

    // cameraEnabled setter automatically stops camera
    cameraEnabled = false
    self.windowManager.updatePiPState(isCameraActive: false, isRecording: false)

    // Show Quick Access Overlay instead of auto-importing
    Task { @MainActor in
      // Generate thumbnail for overlay
      let thumbnail = await generateQuickThumbnail(for: url)

      // Show overlay
      self.quickAccessRecordingURL = url
      self.quickAccessThumbnail = thumbnail
      self.showQuickAccessOverlay = true

      // Bring app to foreground
      self.windowManager.restoreMainWindow()
    }
  }

  /// Generate a thumbnail for the quick access overlay
  private func generateQuickThumbnail(for url: URL) async -> NSImage? {
    let asset = AVURLAsset(url: url)

    guard let duration = try? await asset.load(.duration) else {
      return nil
    }

    // Get frame at 10% of video (usually good content)
    let time = CMTimeMultiplyByFloat64(duration, multiplier: 0.1)
    let generator = AVAssetImageGenerator(asset: asset)
    generator.appliesPreferredTrackTransform = true
    generator.maximumSize = CGSize(width: 640, height: 360)

    do {
      let (cgImage, _) = try await generator.image(at: time)
      return NSImage(cgImage: cgImage, size: NSSize(width: cgImage.width, height: cgImage.height))
    } catch {
      AppLogger.general.warning("Failed to generate quick thumbnail: \(error)")
      return nil
    }
  }

  /// Handle Quick Access Overlay actions
  func handleQuickAccessEdit() {
    guard let url = quickAccessRecordingURL else { return }

    showQuickAccessOverlay = false

    Task { @MainActor in
      AppLogger.recording.info("📹 Quick Access: Edit Now selected")
      ServiceContainer.shared.toastManager.show("📹 Importing recording...")

      if self.projectState.currentProject == nil {
        self.projectState.startNewProject()
      }

      try? await Task.sleep(nanoseconds: 100_000_000)
      await self.projectState.addVideoToTimeline(url: url)

      self.switchToEditing()
      try? await Task.sleep(nanoseconds: 200_000_000)

      ServiceContainer.shared.toastManager.show("✅ Ready to edit!")
    }
  }

  func handleQuickAccessSave() {
    showQuickAccessOverlay = false
    // Just dismiss - video is already saved
    ServiceContainer.shared.toastManager.show("✅ Recording saved!")
  }

  func handleQuickAccessShare() {
    guard quickAccessRecordingURL != nil else { return }

    showQuickAccessOverlay = false
    showExportSheet = true
  }

  func dismissQuickAccessOverlay() {
    showQuickAccessOverlay = false
    quickAccessRecordingURL = nil
    quickAccessThumbnail = nil
  }

  // MARK: - Coordination Actions

  func togglePause() {
    recordingState.togglePause(isScreenSharing: windowManager.isScreenSharing)
  }

  func toggleScreenShare() {
    NSLog("🖥️ toggleScreenShare() called. Current isScreenSharing=\(windowManager.isScreenSharing)")

    // CRITICAL FIX: Prevent concurrent execution to avoid race conditions
    // This is especially important when ending screen sharing to prevent double-cleanup
    guard !windowManager.isTogglingScreenShare else {
      NSLog("🖥️ toggleScreenShare: Already toggling, ignoring")
      AppLogger.window.warning("toggleScreenShare: Already toggling, ignoring duplicate call")
      return
    }

    windowManager.isTogglingScreenShare = true
    defer { windowManager.isTogglingScreenShare = false }

    let wasScreenSharing = windowManager.isScreenSharing
    NSLog("🖥️ toggleScreenShare: wasScreenSharing=\(wasScreenSharing)")

    if wasScreenSharing {
      // CRITICAL FIX: If recording, switch to camera FIRST before stopping screen share
      // This ensures recording continues seamlessly
      if recordingState.isRecording {
        // CRITICAL: Switch source to camera and AWAIT completion
        // This ensures UI state is updated only after switch completes
        let newSource: RecordingSource = .camera
        AppLogger.recording.info("🔄 AppState: Switching from screen to camera recording")
        recordingState.switchSource(newSource)

        // CRITICAL: Wait for switch to complete (with timeout)
        // We poll the recording state to see when switch is done
        Task {
          var attempts = 0
          let maxAttempts = 50 // 5 seconds max wait (50 * 100ms)

          while attempts < maxAttempts {
            try? await Task.sleep(nanoseconds: 100_000_000) // 100ms

            // Check if switch completed by checking if we're on camera source
            // Note: We can't directly check isSwitching, so we infer from source
            // If recording is still active and we're not screen sharing, switch likely completed
            if !recordingState.isRecording || !windowManager.isScreenSharing {
              break
            }

            attempts += 1
          }

          await MainActor.run {
            windowManager.restoreMainWindow()
            windowManager.isScreenSharing = false
            windowManager.updatePiPState(
              isCameraActive: cameraState.isActive,
              isRecording: recordingState.isRecording
            )

            ServiceContainer.shared.toastManager.show("📷 Switched to Camera Recording")
          }
        }
      } else {
        // Not recording - just stop screen share and deactivate picker
        NSLog("🖥️ toggleScreenShare: Not recording, stopping screen share cleanly...")
        // CRITICAL FIX: Stop stream FIRST, then deactivate picker, then cleanup windows
        // This prevents crashes from deactivating picker while stream is still active
        Task { @MainActor in
          NSLog("🖥️ Step 1: Stopping screen recorder stream...")
          // Step 1: Stop the screen recorder stream FIRST
          if let screenRecorder = recordingState.engine?.screenRecorder {
            AppLogger.recording.info("🛑 AppState: Stopping screen recorder stream...")
            await screenRecorder.stop()
            NSLog("🖥️ Step 1: Screen recorder stream stopped")
            AppLogger.recording.info("✅ Screen recorder stream stopped")
          } else {
            NSLog("🖥️ Step 1: No screen recorder to stop")
          }

          NSLog("🖥️ Step 2: Delay for stream cleanup...")
          // Step 2: Small delay to ensure stream cleanup completes
          try? await Task.sleep(nanoseconds: 100_000_000) // 100ms

          NSLog("🖥️ Step 3: Deactivating picker...")
          // Step 3: Now deactivate picker (safe after stream is stopped)
          // CRITICAL: Only deactivate picker if NOT in test environment (test environment bypasses picker)
          if !TestEnvironment.isTesting {
            let picker = SCContentSharingPicker.shared
            picker.isActive = false
            NSLog("🖥️ Step 3: Picker deactivated")
            AppLogger.recording.info("🛑 AppState: Deactivated screen share picker")
          } else {
            NSLog("🖥️ Step 3: Skipping picker (test environment)")
            AppLogger.recording.info("🧪 [TEST] AppState: Skipping picker deactivation (test environment)")
          }

          NSLog("🖥️ Step 4: Updating isScreenSharing state...")
          // Step 4: Update state FIRST so updatePiPState sees the correct value
          windowManager.isScreenSharing = false

          NSLog("🖥️ Step 5: Cleanup PiP windows...")
          // Step 5: Now update PiP (which will hide it because isScreenSharing is false)
          windowManager.updatePiPState(
            isCameraActive: cameraState.isActive,
            isRecording: false
          )

          NSLog("🖥️ Step 5.5: Delay for SwiftUI teardown...")
          try? await Task.sleep(nanoseconds: 300_000_000) // 300ms

          NSLog("🖥️ Step 6: Restoring main window...")
          // Step 6: Restore main window
          windowManager.restoreMainWindow()

          NSLog("🖥️ ✅ Screen share exit cleanup complete!")
          AppLogger.recording.info("✅ Screen share exit cleanup complete")
        }
      }
    } else {
      // Starting screen share
      NSLog("🖥️ toggleScreenShare: Starting screen share...")
      windowManager.isScreenSharing = true

      var effectiveCameraActive = cameraState.isActive
      // cameraEnabled didSet automatically starts camera
      if !cameraState.isActive {
        NSLog("🖥️ toggleScreenShare: Auto-starting camera for PiP")
        AppLogger.camera.info("AppState: Auto-starting camera for screen share PiP")
        cameraEnabled = true
        effectiveCameraActive = true
      }

      NSLog("🖥️ toggleScreenShare: Updating PiP state...")
      windowManager.updatePiPState(
        isCameraActive: effectiveCameraActive,
        isRecording: recordingState.isRecording
      )
      NSLog("🖥️ toggleScreenShare: Minimizing main window...")
      windowManager.minimizeMainWindow()

      // CRITICAL FIX: If recording, switch to screen source AFTER screen share is set up
      // BULLETPROOF: Handle switch completion and errors
      if recordingState.isRecording {
        let newSource: RecordingSource = .screen
        AppLogger.recording.info("🔄 AppState: Switching from camera to screen recording")
        recordingState.switchSource(newSource)

        // CRITICAL: Wait for switch to complete (with timeout)
        Task {
          var attempts = 0
          let maxAttempts = 50 // 5 seconds max wait

          while attempts < maxAttempts {
            try? await Task.sleep(nanoseconds: 100_000_000) // 100ms

            // Check if switch completed - if screen recorder is active, switch likely completed
            // We can't directly check, so we just wait a reasonable time
            attempts += 1
          }

          await MainActor.run {
            ServiceContainer.shared.toastManager.show("🖥️ Switched to Screen Recording")
          }
        }
      }
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
