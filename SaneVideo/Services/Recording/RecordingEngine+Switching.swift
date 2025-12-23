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

  /// Perform the actual source switch (stop old source, start new source)
  /// NOTE: Camera session is NOT stopped during screen recording because PiP needs it for preview overlay
  @RecordingActor
  private func performSourceSwitch(from _: RecordingSource, to newSource: RecordingSource) async {
    if newSource == .camera {
      // Stop screen recorder - camera should already be running
      await screenRecorder.stop()
      AppLogger.recording.info("Screen recorder stopped, camera should still be running for PiP")

      // Small delay for hardware cleanup
      try? await Task.sleep(nanoseconds: 100_000_000)  // 0.1s optimized

      // Ensure camera is running (it should be, but just in case)
      await MainActor.run { [weak self] in
        guard let self = self else { return }

        if !self.cameraService.isActive {
          Task {
            do {
              try await self.cameraService.start()
              AppLogger.recording.info("Camera restarted after source switch")
            } catch {
              AppLogger.recording.error(
                "Failed to restart camera after source switch: \(error.localizedDescription)")
            }
          }
        } else {
          AppLogger.recording.info("Camera already running, continuing with camera source")
        }
      }
    } else {
      // Switch to screen - DO NOT stop camera, PiP needs it for preview overlay
      AppLogger.recording.info(
        "Switching to screen recording, keeping camera session active for PiP preview")

      // Small delay for hardware preparation
      try? await Task.sleep(nanoseconds: 100_000_000)  // 0.1s optimized

      do {
        try await screenRecorder.start()
        AppLogger.recording.info("Screen recorder started after source switch")
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
