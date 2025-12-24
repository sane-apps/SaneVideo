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
    guard let url = quickAccessRecordingURL else { return }
    
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
    let wasScreenSharing = windowManager.isScreenSharing

    if wasScreenSharing {
      // CRITICAL FIX: If recording, switch to camera FIRST before stopping screen share
      // This ensures recording continues seamlessly
      if recordingState.isRecording {
        // Switch source to camera - this will properly stop screen recorder and start camera
        let newSource: RecordingSource = .camera
        AppLogger.recording.info("🔄 AppState: Switching from screen to camera recording")
        recordingState.switchSource(newSource)
        
        // Wait a moment for the switch to initiate, then update UI state
        Task {
          // Small delay to let switchSource start the transition
          try? await Task.sleep(nanoseconds: 100_000_000) // 100ms
          
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
        Task {
          let picker = SCContentSharingPicker.shared
          picker.isActive = false
          AppLogger.recording.info("🛑 AppState: Deactivated screen share picker")
        }
        
        windowManager.restoreMainWindow()
        windowManager.isScreenSharing = false
        windowManager.updatePiPState(
          isCameraActive: cameraState.isActive,
          isRecording: recordingState.isRecording
        )
      }
    } else {
      // Starting screen share
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
      
      // CRITICAL FIX: If recording, switch to screen source AFTER screen share is set up
      if recordingState.isRecording {
        let newSource: RecordingSource = .screen
        AppLogger.recording.info("🔄 AppState: Switching from camera to screen recording")
        recordingState.switchSource(newSource)
        
        ServiceContainer.shared.toastManager.show("🖥️ Switched to Screen Recording")
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
