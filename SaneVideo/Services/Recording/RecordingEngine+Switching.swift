import AVFoundation
import Foundation
import OSLog

// MARK: - Source Switching (Unified Session Architecture)

extension RecordingEngine {
  /// Switch recording source instantaneously within a single continuous session.
  /// This is the "Right Way" as all inputs are normalized by VideoWriter's CIContext.
  func switchSource(source: RecordingSource) {
    Task { @RecordingActor in
      guard !isStopping else {
        AppLogger.recording.warning("Cannot switch source while stopping")
        return
      }
      // Prevent overlapping switches
      guard !isSwitching else {
        AppLogger.recording.warning(
          "Source switch already in progress, ignoring request to switch to \(source)")
        return
      }
      guard currentSource != source else { return }

      let previousSource = currentSource
      AppLogger.recording.info("Switching source from \(previousSource) to \(source)")

      isSwitching = true
      defer { isSwitching = false }

      // Mark new source as pending for graceful handoff
      pendingSource = source

      // TAHOE FIX: Trigger recalibration to align timestamps during the handoff
      timeCoordinator.startTimeNeedsRecalibration = true

      // Switch the actual source (camera/screen)
      await performSourceSwitch(from: previousSource, to: source)

      AppLogger.recording.info("Source switch initiated. Pending: \(source)")
    }
  }

  /// Perform the actual source switch with smooth overlapping transition
  /// NOTE: Camera session is NOT stopped during screen recording because PiP needs it for preview overlay
  @RecordingActor
  private func performSourceSwitch(from previousSource: RecordingSource, to newSource: RecordingSource) async {
    if newSource == .camera {
      // Switch to camera: Start camera first (if needed), then stop screen recorder
      // This ensures smooth transition with no gap
      AppLogger.recording.info("Switching to camera: Ensuring camera is active first...")
      
      // Ensure camera is running BEFORE stopping screen recorder
      let cameraWasActive = await MainActor.run { [weak self] in
        guard let self = self else { return false }
        return self.cameraService.isActive
      }
      
      if !cameraWasActive {
        // Start camera on MainActor
        await MainActor.run { [weak self] in
          guard let self = self else { return }
          Task {
            do {
              try await self.cameraService.start()
              AppLogger.recording.info("Camera started for smooth transition")
            } catch {
              AppLogger.recording.error(
                "Failed to start camera during switch: \(error.localizedDescription)")
            }
          }
        }
        
        // Small delay to let camera stabilize, then stop screen recorder
        try? await Task.sleep(nanoseconds: 50_000_000)  // 0.05s - reduced delay
      } else {
        AppLogger.recording.info("Camera already running, preparing to stop screen recorder...")
        // Minimal delay for smooth handoff
        try? await Task.sleep(nanoseconds: 33_000_000)  // ~1 frame at 30fps
      }
      
      // Now stop screen recorder (camera is guaranteed to be running)
      await screenRecorder.stop()
      AppLogger.recording.info("Screen recorder stopped, camera transition complete")
    } else {
      // Switch to screen: Start screen recorder first, camera stays running for PiP
      AppLogger.recording.info(
        "Switching to screen recording, keeping camera active for PiP overlay")

      // Start screen recorder immediately - no delay needed since camera is already running
      do {
        try await screenRecorder.start()
        AppLogger.recording.info("Screen recorder started, smooth transition to screen mode")
      } catch {
        AppLogger.recording.error("Failed to start screen recorder: \(error.localizedDescription)")
        let appError = AppError.recordingEngineError(
          "Screen recording failed: \(error.localizedDescription)")
        await MainActor.run { [weak self] in
          self?.onError?(appError)
        }
      }
    }
  }

  func setMuted(_ muted: Bool) {
    Task { @RecordingActor in
      isMicMuted = muted
      AppLogger.recording.info("Mic muting set to: \(muted)")
    }
  }
}
