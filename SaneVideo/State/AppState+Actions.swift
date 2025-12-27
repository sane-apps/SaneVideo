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

    // 1. Ensure camera is active for recording (Camera mode OR screen sharing PiP)
    // Skip during tests to avoid popups. cameraEnabled setter automatically starts camera.
    let isTesting = ProcessInfo.processInfo.arguments.contains("-uitesting")
    if !isTesting && !cameraState.isActive {
      AppLogger.camera.info("📷 AppState: Auto-starting camera for recording (PiP support)")
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

      // CRITICAL: UX Delight - Audible feedback on success (as requested)
      ServiceContainer.shared.soundManager.playSuccess()
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
    guard let url = quickAccessRecordingURL else {
      NSLog("📹 handleQuickAccessEdit: No URL available!")
      return
    }

    NSLog("📹 handleQuickAccessEdit: URL = \(url.path)")
    showQuickAccessOverlay = false

    Task { @MainActor in
      NSLog("📹 Quick Access: Edit Now selected for \(url.lastPathComponent)")

      // CRITICAL FIX: Switch to editing mode IMMEDIATELY for responsiveness
      // This prevents the "nothing happened" scenario if import takes time
      self.switchToEditing()

      // Show loading feedback
      ServiceContainer.shared.toastManager.show("📹 Importing recording...")

      if self.projectState.currentProject == nil {
        self.projectState.startNewProject()
      }

      // CRITICAL FIX: Wait longer for video file to be fully written and finalized
      // Video files need time for:
      // 1. Disk flush to complete
      // 2. Moov atom to be finalized (moved to front of file)
      // 3. File system metadata to be updated
      // The retry logic in addVideoToTimeline will handle any remaining issues
      try? await Task.sleep(nanoseconds: 500_000_000) // 500ms initial delay

      await self.projectState.addVideoToTimeline(url: url)

      // Removed second sleep - not needed if we switched mode early
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
    // NOTE: Do NOT use defer here - flag is reset inside Task completion to prevent race conditions

    let wasScreenSharing = windowManager.isScreenSharing
    NSLog("🖥️ toggleScreenShare: wasScreenSharing=\(wasScreenSharing)")

    if wasScreenSharing {
      // Logic for STOPPING screen share

      // CRITICAL FIX: If recording, switch to camera FIRST before stopping screen share
      // This ensures recording continues seamlessly
      if recordingState.isRecording {
        // CRITICAL: Switch source to camera and AWAIT completion
        let newSource: RecordingSource = .camera
        AppLogger.recording.info("🔄 AppState: Switching from screen to camera recording")
        recordingState.switchSource(newSource)

        Task { @MainActor in
          // Wait for switch to complete (max 5 seconds)
          var attempts = 0
          let maxAttempts = 50

          while attempts < maxAttempts {
            try? await Task.sleep(nanoseconds: 100_000_000) // 100ms
            if !recordingState.isRecording || !windowManager.isScreenSharing { break }
            attempts += 1
          }

          if attempts >= maxAttempts {
            AppLogger.recording.warning("Source switch timed out after 5s")
          }

          windowManager.restoreMainWindow()
          windowManager.isScreenSharing = false
          windowManager.updatePiPState(
            isCameraActive: cameraState.isActive,
            isRecording: recordingState.isRecording
          )

          windowManager.isTogglingScreenShare = false
          ServiceContainer.shared.toastManager.show("📷 Switched to Camera Recording")
        }
      } else {
        // Not recording - clean shutdown sequence
        NSLog("🖥️ toggleScreenShare: Not recording, stopping screen share cleanly...")

        Task { @MainActor in
            // Step 1: Stop the screen recorder stream FIRST
            NSLog("🖥️ Step 1: Stopping screen recorder stream...")
            if let screenRecorder = recordingState.engine?.screenRecorder {
              await screenRecorder.stop()
              NSLog("🖥️ Step 1: ✅ Screen recorder stream stopped")
            }

            // Step 2: Update state IMMEDIATELY after stream stops
            NSLog("🖥️ Step 2: Updating state...")
            windowManager.isScreenSharing = false

            // Step 3: Hide PiP window
            NSLog("🖥️ Step 3: Hiding PiP...")
            windowManager.updatePiPState(
              isCameraActive: cameraState.isActive,
              isRecording: false
            )

            // Step 4: Wait for window close to complete
            NSLog("🖥️ Step 4: Waiting for window cleanup...")
            try? await Task.sleep(nanoseconds: 150_000_000) // 150ms

            // Step 5: Preserve picker state for persistence (Tahoe style)
            // We do NOT deactivate SCContentSharingPicker here.
            // Keeping it active allows the OS to remember the previous selection
            // so the user doesn't have to re-select the window next time.
            NSLog("🖥️ Step 5: Picker remains active for selection persistence")

            // Step 6: Restore main window
            NSLog("🖥️ Step 6: Restoring main window...")
            windowManager.restoreMainWindow()

            // CRITICAL: Always reset toggle flag
            windowManager.isTogglingScreenShare = false
            NSLog("🖥️ toggleScreenShare: ✅ Sequence complete")
        }
      }
    } else {
      // Logic for STARTING screen share
      NSLog("🖥️ toggleScreenShare: Starting screen share...")

      // Start camera for PiP overlay if not active
      if !cameraState.isActive {
        NSLog("🖥️ toggleScreenShare: Auto-starting camera for PiP")
        AppLogger.camera.info("AppState: Auto-starting camera for screen share PiP")
        cameraEnabled = true
      }

      // Hide main window BEFORE picker shows for cleaner look
      windowManager.minimizeMainWindow()

      // Update state for new mode
      windowManager.isScreenSharing = true

      // CRITICAL FIX: Do NOT show PiP here - it will appear in the picker!
      // PiP is shown via onContentSelected callback AFTER user selects content
      NSLog("🖥️ toggleScreenShare: Deferring PiP display until after content selection")

      Task { @MainActor in
        // Small delay to let UI settle
        try? await Task.sleep(nanoseconds: 100_000_000) // 100ms

        if !TestEnvironment.isTesting {
           let picker = SCContentSharingPicker.shared

           // CRITICAL: Deactivate picker first to reset any cached state
           picker.isActive = false

           // CRITICAL FIX: Register ScreenRecorder as observer BEFORE presenting picker
           // This ensures onContentSelected fires when user makes a selection
           if let screenRecorder = self.recordingState.engine?.screenRecorder {
             picker.add(screenRecorder)
             NSLog("🖥️ ScreenRecorder registered as picker observer")
           }

           // Configure picker with allowed modes
           var config = SCContentSharingPickerConfiguration()
           config.allowedPickerModes = [
             .singleWindow, .multipleWindows, .singleApplication, .multipleApplications, .singleDisplay
           ]

           picker.configuration = config
           picker.defaultConfiguration = config
           picker.isActive = true
           picker.present()
           NSLog("🖥️ Picker presented (PiP not yet shown)")
        }

        windowManager.isTogglingScreenShare = false
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
