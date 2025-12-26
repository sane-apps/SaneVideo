import AVFoundation
import Foundation
import OSLog

// MARK: - Source Switching (Unified Session Architecture)

extension RecordingEngine {
  /// Switch recording source instantaneously within a single continuous session.
  /// This is the "Right Way" as all inputs are normalized by VideoWriter's CIContext.
  /// BULLETPROOF: Handles all edge cases including cancellation, timeouts, and concurrent operations.
  func switchSource(source: RecordingSource) {
    Task { @RecordingActor in
      // CRITICAL: Check if recording is active
      guard isRecording else {
        AppLogger.recording.warning("Cannot switch source: not recording")
        return
      }

      // CRITICAL: Cannot switch while stopping
      guard !isStopping else {
        AppLogger.recording.warning("Cannot switch source while stopping")
        return
      }

      // CRITICAL: Prevent overlapping switches
      guard !isSwitching else {
        AppLogger.recording.warning(
          "Source switch already in progress, ignoring request to switch to \(source)")
        return
      }

      // CRITICAL: No-op if already on target source
      guard currentSource != source else {
        AppLogger.recording.debug("Already on source \(source), ignoring switch request")
        return
      }

      let previousSource = currentSource
      AppLogger.recording.info("🔄 Switching source from \(previousSource) to \(source)")

      // CRITICAL: Set flags BEFORE any async work to prevent race conditions
      isSwitching = true
      pendingSource = source
      timeCoordinator.startTimeNeedsRecalibration = true

      // CRITICAL FIX: Show user feedback immediately
      await MainActor.run {
        let sourceName = source == .camera ? "Camera" : "Screen"
        ServiceContainer.shared.toastManager.show("🔄 Switching to \(sourceName)...")
      }

      // CRITICAL: Create timeout task BEFORE starting switch
      // If switch takes too long, rollback.
      // NOTE: Screen picking requires user interaction, so we allow a much longer timeout (2 mins).
      // Camera switching should be near-instant (10s is plenty).
      let timeoutDuration: UInt64 = (source == .screen) ? 120_000_000_000 : 10_000_000_000

      sourceSwitchTimeoutTask = Task { @RecordingActor [weak self] in
        try? await Task.sleep(nanoseconds: timeoutDuration)
        guard let self = self else { return }

        // Only timeout if still switching and pending source hasn't been cleared
        if self.isSwitching, self.pendingSource == source {
          let timeoutSecs = timeoutDuration / 1_000_000_000
          AppLogger.recording.error("⏱️ Source switch timeout after \(timeoutSecs)s. Rolling back.")

          // Rollback state
          self.pendingSource = nil
          self.currentSource = previousSource
          self.isSwitching = false
          self.timeCoordinator.startTimeNeedsRecalibration = false

          // CRITICAL FIX: Show user-friendly feedback
          await MainActor.run { [weak self] in
            ServiceContainer.shared.toastManager.show("⚠️ Switch timed out, continuing on previous source", type: .error)
            self?.onError?(
              AppError.recordingEngineError("Source switch timed out. Recording may be corrupted."))
          }
        }
      }

      // CRITICAL: Use defer to ensure cleanup even if switch fails
      defer {
        // Only clear isSwitching if we're not in a timeout state
        // The timeout task will clear it if needed
        if pendingSource == nil {
          isSwitching = false
        }
      }

      // Perform the actual switch
      await performSourceSwitch(from: previousSource, to: source)

      // CRITICAL: If switch completed successfully, clear timeout
      if pendingSource == nil {
        sourceSwitchTimeoutTask?.cancel()
        sourceSwitchTimeoutTask = nil
        AppLogger.recording.info("✅ Source switch completed successfully")
      }
    }
  }

  /// Perform the actual source switch with smooth overlapping transition
  /// NOTE: Camera session is NOT stopped during screen recording because PiP needs it for preview overlay
  /// BULLETPROOF: Handles all failure modes with proper rollback
  @RecordingActor
  private func performSourceSwitch(
    from previousSource: RecordingSource, to newSource: RecordingSource
  ) async {
    // CRITICAL: Check if we're still supposed to be switching
    // (might have been cancelled or stopped)
    guard isRecording, !isStopping, isSwitching, pendingSource == newSource else {
      AppLogger.recording.warning("Switch cancelled or state changed during switch")
      pendingSource = nil
      isSwitching = false
      timeCoordinator.startTimeNeedsRecalibration = false
      return
    }

    if newSource == .camera {
      // Switch to camera: Start camera first (if needed), then stop screen recorder
      // This ensures smooth transition with no gap
      AppLogger.recording.info("🔄 Switching to camera: Ensuring camera is active first...")

      // Ensure camera is running BEFORE stopping screen recorder
      let cameraWasActive = await MainActor.run { [weak self] in
        guard let self = self else { return false }
        return self.cameraService.isActive
      }

      // CRITICAL: Re-check state after MainActor hop
      guard isRecording, !isStopping, isSwitching, pendingSource == newSource else {
        AppLogger.recording.warning("Switch cancelled during camera check")
        pendingSource = nil
        isSwitching = false
        timeCoordinator.startTimeNeedsRecalibration = false
        return
      }

      if !cameraWasActive {
        // Start camera on MainActor and AWAIT it to ensure it's ready
        // CRITICAL: cameraService is @MainActor, call directly (we're already in async context)
        do {
          try await cameraService.start()
          AppLogger.recording.info("✅ Camera started for smooth transition")
        } catch {
          AppLogger.recording.error(
            "❌ Failed to start camera during switch: \(error.localizedDescription)")
          // CRITICAL: Rollback switch on failure
          pendingSource = nil
          currentSource = previousSource
          isSwitching = false
          timeCoordinator.startTimeNeedsRecalibration = false
          await MainActor.run { [weak self] in
            self?.onError?(
              AppError.recordingEngineError("Camera switch failed: \(error.localizedDescription)"))
          }
          return
        }

        // CRITICAL: Re-check state after camera start
        guard isRecording, !isStopping, isSwitching, pendingSource == newSource else {
          AppLogger.recording.warning("Switch cancelled after camera start")
          pendingSource = nil
          isSwitching = false
          timeCoordinator.startTimeNeedsRecalibration = false
          return
        }

        // Small delay to let camera stabilize, then stop screen recorder
        try? await Task.sleep(nanoseconds: 50_000_000)  // 0.05s

        // CRITICAL: Final state check before stopping screen recorder
        guard isRecording, !isStopping, isSwitching, pendingSource == newSource else {
          AppLogger.recording.warning("Switch cancelled before stopping screen recorder")
          pendingSource = nil
          isSwitching = false
          timeCoordinator.startTimeNeedsRecalibration = false
          return
        }
      } else {
        AppLogger.recording.info("Camera already running, preparing to stop screen recorder...")
        // Minimal delay for smooth handoff
        try? await Task.sleep(nanoseconds: 33_000_000)  // ~1 frame at 30fps

        // CRITICAL: Re-check state
        guard isRecording, !isStopping, isSwitching, pendingSource == newSource else {
          AppLogger.recording.warning("Switch cancelled before stopping screen recorder")
          pendingSource = nil
          isSwitching = false
          timeCoordinator.startTimeNeedsRecalibration = false
          return
        }
      }

      // Now stop screen recorder (camera is guaranteed to be running)
      await screenRecorder.stop()
      AppLogger.recording.info("✅ Screen recorder stopped, camera transition complete")

      // CRITICAL: Final state check - if we got here, switch succeeded
      // The first frame from camera will clear pendingSource in processSample
      if pendingSource == newSource {
        // If no frames arrive, we'll timeout (handled by timeout task)
        AppLogger.recording.info("⏳ Waiting for first camera frame to complete switch...")
      }
    } else {
      // Switch to screen: Start screen recorder first, camera stays running for PiP
      AppLogger.recording.info(
        "🔄 Switching to screen recording, keeping camera active for PiP overlay")

      // CRITICAL: Re-check state before starting screen recorder
      guard isRecording, !isStopping, isSwitching, pendingSource == newSource else {
        AppLogger.recording.warning("Switch cancelled before starting screen recorder")
        pendingSource = nil
        isSwitching = false
        timeCoordinator.startTimeNeedsRecalibration = false
        return
      }

      // Start screen recorder immediately - no delay needed since camera is already running
      do {
        try await screenRecorder.start()
        AppLogger.recording.info("✅ Screen recorder started, smooth transition to screen mode")

        // CRITICAL: Re-check state after screen recorder start
        guard isRecording, !isStopping, isSwitching, pendingSource == newSource else {
          AppLogger.recording.warning("Switch cancelled after screen recorder start")
          // Don't rollback currentSource here - let first frame handle it
          return
        }

        // The first frame from screen will clear pendingSource in processSample
        AppLogger.recording.info("⏳ Waiting for first screen frame to complete switch...")
      } catch {
        AppLogger.recording.error(
          "❌ Failed to start screen recorder: \(error.localizedDescription)")
        // CRITICAL: Rollback switch on failure
        pendingSource = nil
        currentSource = previousSource
        isSwitching = false
        timeCoordinator.startTimeNeedsRecalibration = false
        let appError = AppError.recordingEngineError(
          "Screen recording failed: \(error.localizedDescription)")
        await MainActor.run { [weak self] in
          self?.onError?(appError)
        }
        return
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
