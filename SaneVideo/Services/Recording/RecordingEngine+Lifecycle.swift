//
//  RecordingEngine+Lifecycle.swift
//  SaneVideo
//
//  Consolidated from RecordingEngine+Setup.swift and RecordingEngine+Switching.swift
//

import AVFoundation
import AppKit
import Combine
import CoreMedia
import Foundation
import OSLog

// MARK: - Setup & Monitoring

extension RecordingEngine {
  @MainActor
  func setupSoundAnalysisMonitoring() {
    soundAnalysisService.onSoundDetected = { result in
      AppLogger.recording.info(
        "Sound Detected: \(result.label) at \(result.timeRange.start.seconds)")
    }
  }

  @MainActor
  func setupDiskMonitor() {
    diskSpaceMonitor.onLowDiskSpace = { [weak self] error in
      guard let self = self else { return }

      Task {
        AppLogger.recording.error("Low disk space - stopping recording: \(error)")
        _ = await self.stopRecording()

        await MainActor.run {
          self.onError?(
            error as? AppError ?? AppError.recordingEngineError(error.localizedDescription))
        }
      }
    }
  }

  @MainActor
  func setupSleepObservers() {
    let center = NSWorkspace.shared.notificationCenter
    center.addObserver(
      self, selector: #selector(handleSleep), name: NSWorkspace.willSleepNotification, object: nil)
    center.addObserver(
      self, selector: #selector(handleWake), name: NSWorkspace.didWakeNotification, object: nil)
  }

  @MainActor
  func setupInterruptionObservers() {
    let center = NotificationCenter.default

    center.addObserver(
      self, selector: #selector(handleSessionWasInterrupted),
      name: AVCaptureSession.wasInterruptedNotification, object: nil)
    center.addObserver(
      self, selector: #selector(handleSessionInterruptionEnded),
      name: AVCaptureSession.interruptionEndedNotification, object: nil)
    center.addObserver(
      self, selector: #selector(handleSessionRuntimeError),
      name: AVCaptureSession.runtimeErrorNotification, object: nil)

    center.addObserver(
      self, selector: #selector(handleAudioConfigurationChange),
      name: .AVAudioEngineConfigurationChange, object: nil)
  }

  func setupSubscriptions() {
    Task { @RecordingActor [weak self] in
      guard let self = self else { return }
      for await buffer in cameraService.sampleBufferSubject.values {
        self.processSample(buffer, source: .camera)
      }
    }

    Task { @RecordingActor [weak self] in
      guard let self = self else { return }
      for await buffer in screenRecorder.sampleBufferSubject.values {
        self.processSample(buffer, source: .screen)
      }
    }

    Task { @RecordingActor [weak self] in
      guard let self = self else { return }
      for await buffer in screenRecorder.audioSampleBufferSubject.values {
        self.processSystemAudioSample(buffer)
      }
    }

    Task { @RecordingActor [weak self] in
      guard let self = self else { return }
      for await buffer in audioService.sampleBufferSubject.values {
        self.processAudioSample(buffer)
      }
    }

    Task { [weak self] in
      guard let self = self else { return }
      for await isActive in cameraService.isActivePublisher.values where !isActive {
        AppLogger.recording.info("Camera stopped - clearing frame in VideoWriter")
        await self.clearCameraFrame()
      }
    }

    setupScreenRecorderBinding()
    setupScreenRecorderOverlayBinding()
  }

  @MainActor
  private func setupScreenRecorderBinding() {
    screenRecorder.onStop = { [weak self] error in
      self?.handleScreenRecorderStopped(error: error)
    }
  }

  @MainActor
  private func setupScreenRecorderOverlayBinding() {
    screenRecorder.onPresenterOverlayChanged = { [weak self] active in
      self?.onPresenterOverlayChanged?(active)
    }

    screenRecorder.onContentSelected = { [weak self] in
      self?.onContentSelected?()
    }
  }

  @MainActor
  private func handleScreenRecorderStopped(error: Error?) {
    Task { @RecordingActor in
      let errorMessage = error?.localizedDescription ?? "User cancelled or stopped externally"
      AppLogger.recording.info("Screen recording stream stopped: \(errorMessage)")

      if isSwitching, pendingSource == .screen {
        AppLogger.recording.error("Screen recorder stopped/cancelled during switch TO screen. Rolling back.")
        pendingSource = nil
        currentSource = .camera
        isSwitching = false
        timeCoordinator.startTimeNeedsRecalibration = false
        sourceSwitchTimeoutTask?.cancel()
        sourceSwitchTimeoutTask = nil

        await MainActor.run { [weak self] in
          self?.onError?(AppError.recordingEngineError("Screen sharing was cancelled"))
        }
        return
      }

      let wasScreenSharing = currentSource == .screen || pendingSource == .screen
      if wasScreenSharing {
        AppLogger.recording.info("Notifying system that screen share ended externally.")
        await MainActor.run {
          self.onScreenRecordingStoppedExternally?()
        }
      }

      if pendingSource == .screen { pendingSource = nil }
      if isSwitching && currentSource == .screen { isSwitching = false }
    }
  }

  // MARK: - UI Test Helpers

  @RecordingActor
  func generateMockVideo(to url: URL) async {
    AppLogger.recording.info("[UI TEST] Generating mock video at: \(url.path)")

    try? FileManager.default.removeItem(at: url)

    guard let writer = try? AVAssetWriter(outputURL: url, fileType: .mp4) else {
      AppLogger.recording.error("[UI TEST] Failed to create asset writer")
      return
    }

    let settings: [String: Any] = [
      AVVideoCodecKey: AVVideoCodecType.h264,
      AVVideoWidthKey: 1280,
      AVVideoHeightKey: 720
    ]

    let input = AVAssetWriterInput(mediaType: .video, outputSettings: settings)
    input.expectsMediaDataInRealTime = false

    guard writer.canAdd(input) else { return }
    writer.add(input)

    let adaptor = AVAssetWriterInputPixelBufferAdaptor(
      assetWriterInput: input, sourcePixelBufferAttributes: nil)

    guard writer.startWriting() else { return }

    writer.startSession(atSourceTime: .zero)

    while !input.isReadyForMoreMediaData {
      try? await Task.sleep(nanoseconds: 10 * 1_000_000)
    }

    if let buffer = await createMockPixelBuffer() {
      adaptor.append(buffer, withPresentationTime: .zero)
      let frameTime = CMTime(value: 1, timescale: 30)
      while !input.isReadyForMoreMediaData { try? await Task.sleep(nanoseconds: 1_000_000) }
      adaptor.append(buffer, withPresentationTime: frameTime)

      let endTime = CMTime(value: 30, timescale: 30)
      while !input.isReadyForMoreMediaData { try? await Task.sleep(nanoseconds: 1_000_000) }
      adaptor.append(buffer, withPresentationTime: endTime)
    }

    input.markAsFinished()
    await writer.finishWriting()
  }

  @RecordingActor
  func createMockPixelBuffer() async -> CVPixelBuffer? {
    var pixelBuffer: CVPixelBuffer?
    let attrs =
      [
        kCVPixelBufferCGImageCompatibilityKey: kCFBooleanTrue,
        kCVPixelBufferCGBitmapContextCompatibilityKey: kCFBooleanTrue
      ] as CFDictionary

    let status = CVPixelBufferCreate(
      kCFAllocatorDefault, 1280, 720, kCVPixelFormatType_32ARGB, attrs, &pixelBuffer)
    guard status == kCVReturnSuccess else { return nil }
    return pixelBuffer
  }
}

// MARK: - Source Switching

extension RecordingEngine {
  func switchSource(source: RecordingSource) {
    Task { @RecordingActor in
      guard isRecording else {
        AppLogger.recording.warning("Cannot switch source: not recording")
        return
      }

      guard !isStopping else {
        AppLogger.recording.warning("Cannot switch source while stopping")
        return
      }

      guard !isSwitching else {
        AppLogger.recording.warning(
          "Source switch already in progress, ignoring request to switch to \(source)")
        return
      }

      guard currentSource != source else {
        AppLogger.recording.debug("Already on source \(source), ignoring switch request")
        return
      }

      let previousSource = currentSource
      AppLogger.recording.info("Switching source from \(previousSource) to \(source)")

      isSwitching = true
      pendingSource = source
      timeCoordinator.startTimeNeedsRecalibration = true

      await MainActor.run {
        let sourceName = source == .camera ? "Camera" : "Screen"
        ServiceContainer.shared.toastManager.show("Switching to \(sourceName)...")
      }

      let timeoutDuration: UInt64 = (source == .screen) ? 120_000_000_000 : 10_000_000_000

      sourceSwitchTimeoutTask = Task { @RecordingActor [weak self] in
        try? await Task.sleep(nanoseconds: timeoutDuration)
        guard let self = self else { return }

        if self.isSwitching, self.pendingSource == source {
          let timeoutSecs = timeoutDuration / 1_000_000_000
          AppLogger.recording.error("Source switch timeout after \(timeoutSecs)s. Rolling back.")

          self.pendingSource = nil
          self.currentSource = previousSource
          self.isSwitching = false
          self.timeCoordinator.startTimeNeedsRecalibration = false

          await MainActor.run { [weak self] in
            ServiceContainer.shared.toastManager.show("Switch timed out, continuing on previous source", type: .error)
            self?.onError?(
              AppError.recordingEngineError("Source switch timed out. Recording may be corrupted."))
          }
        }
      }

      defer {
        if pendingSource == nil {
          isSwitching = false
        }
      }

      await performSourceSwitch(from: previousSource, to: source)

      if pendingSource == nil {
        sourceSwitchTimeoutTask?.cancel()
        sourceSwitchTimeoutTask = nil
        AppLogger.recording.info("Source switch completed successfully")
      }
    }
  }

  @RecordingActor
  private func performSourceSwitch(
    from previousSource: RecordingSource, to newSource: RecordingSource
  ) async {
    guard isRecording, !isStopping, isSwitching, pendingSource == newSource else {
      AppLogger.recording.warning("Switch cancelled or state changed during switch")
      pendingSource = nil
      isSwitching = false
      timeCoordinator.startTimeNeedsRecalibration = false
      return
    }

    if newSource == .camera {
      AppLogger.recording.info("Switching to camera: Ensuring camera is active first...")

      let cameraWasActive = await MainActor.run { [weak self] in
        guard let self = self else { return false }
        return self.cameraService.isActive
      }

      guard isRecording, !isStopping, isSwitching, pendingSource == newSource else {
        AppLogger.recording.warning("Switch cancelled during camera check")
        pendingSource = nil
        isSwitching = false
        timeCoordinator.startTimeNeedsRecalibration = false
        return
      }

      if !cameraWasActive {
        do {
          try await cameraService.start()
          AppLogger.recording.info("Camera started for smooth transition")
        } catch {
          AppLogger.recording.error(
            "Failed to start camera during switch: \(error.localizedDescription)")
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

        guard isRecording, !isStopping, isSwitching, pendingSource == newSource else {
          AppLogger.recording.warning("Switch cancelled after camera start")
          pendingSource = nil
          isSwitching = false
          timeCoordinator.startTimeNeedsRecalibration = false
          return
        }

        try? await Task.sleep(nanoseconds: 50_000_000)

        guard isRecording, !isStopping, isSwitching, pendingSource == newSource else {
          AppLogger.recording.warning("Switch cancelled before stopping screen recorder")
          pendingSource = nil
          isSwitching = false
          timeCoordinator.startTimeNeedsRecalibration = false
          return
        }
      } else {
        AppLogger.recording.info("Camera already running, preparing to stop screen recorder...")
        try? await Task.sleep(nanoseconds: 33_000_000)

        guard isRecording, !isStopping, isSwitching, pendingSource == newSource else {
          AppLogger.recording.warning("Switch cancelled before stopping screen recorder")
          pendingSource = nil
          isSwitching = false
          timeCoordinator.startTimeNeedsRecalibration = false
          return
        }
      }

      await screenRecorder.stop()
      AppLogger.recording.info("Screen recorder stopped, camera transition complete")

      if pendingSource == newSource {
        AppLogger.recording.info("Waiting for first camera frame to complete switch...")
      }
    } else {
      AppLogger.recording.info(
        "Switching to screen recording, keeping camera active for PiP overlay")

      guard isRecording, !isStopping, isSwitching, pendingSource == newSource else {
        AppLogger.recording.warning("Switch cancelled before starting screen recorder")
        pendingSource = nil
        isSwitching = false
        timeCoordinator.startTimeNeedsRecalibration = false
        return
      }

      do {
        try await screenRecorder.start()
        AppLogger.recording.info("Screen recorder started, smooth transition to screen mode")

        guard isRecording, !isStopping, isSwitching, pendingSource == newSource else {
          AppLogger.recording.warning("Switch cancelled after screen recorder start")
          return
        }

        AppLogger.recording.info("Waiting for first screen frame to complete switch...")
      } catch {
        AppLogger.recording.error(
          "Failed to start screen recorder: \(error.localizedDescription)")
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
