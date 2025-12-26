//
//  RecordingEngine+Setup.swift
//  SaneVideo
//

import AVFoundation
import AppKit
import Combine
import CoreMedia
import Foundation

extension RecordingEngine {
  // MARK: - Monitoring

  @MainActor
  func setupSoundAnalysisMonitoring() {
    soundAnalysisService.onSoundDetected = { result in
      AppLogger.recording.info(
        "🔊 Sound Detected: \(result.label) at \(result.timeRange.start.seconds)")
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

    // Capture Session Interruptions (Camera/Mic hardware issues)
    center.addObserver(
      self, selector: #selector(handleSessionWasInterrupted),
      name: AVCaptureSession.wasInterruptedNotification, object: nil)
    center.addObserver(
      self, selector: #selector(handleSessionInterruptionEnded),
      name: AVCaptureSession.interruptionEndedNotification, object: nil)
    center.addObserver(
      self, selector: #selector(handleSessionRuntimeError),
      name: AVCaptureSession.runtimeErrorNotification, object: nil)

    // Audio Engine Changes (Device unplugged/switched)
    center.addObserver(
      self, selector: #selector(handleAudioConfigurationChange),
      name: .AVAudioEngineConfigurationChange, object: nil)
  }

  func setupSubscriptions() {
    // High-performance sample processing using AsyncStreams (Swift 6 "Right Way")
    // This avoids creating 60+ Tasks per second and provides native backpressure

    // 1. Camera Samples
    Task { @RecordingActor [weak self] in
      guard let self = self else { return }
      for await buffer in cameraService.sampleBufferSubject.values {
        self.processSample(buffer, source: .camera)
      }
    }

    // 2. Screen Samples
    Task { @RecordingActor [weak self] in
      guard let self = self else { return }
      for await buffer in screenRecorder.sampleBufferSubject.values {
        self.processSample(buffer, source: .screen)
      }
    }

    // 3. System Audio
    Task { @RecordingActor [weak self] in
      guard let self = self else { return }
      for await buffer in screenRecorder.audioSampleBufferSubject.values {
        self.processSystemAudioSample(buffer)
      }
    }

    // 4. Microphone
    // CRITICAL FIX: Always use AudioService for generic microphone capture
    // ScreenRecorder mic capture is disabled to avoid VPIO issues
    Task { @RecordingActor [weak self] in
      guard let self = self else { return }
      for await buffer in audioService.sampleBufferSubject.values {
        // Forward mic samples regardless of current source (Camera or Screen)
        self.processAudioSample(buffer)
      }
    }

    // 5. Camera Status (Clear frame on stop to prevent PiP "freezing")
    Task { [weak self] in
      guard let self = self else { return }
      for await isActive in await cameraService.isActivePublisher.values {
        if !isActive {
          AppLogger.recording.info("📷 Camera stopped - clearing frame in VideoWriter")
          await self.clearCameraFrame()
        }
      }
    }

    // CRITICAL FIX: Setup bindings synchronously to prevent race condition
    // where onStop is nil when user cancels screen picker immediately after starting
    // RecordingEngine is @MainActor, so we can call these directly
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
      // Forward to AppState via closure callback on MainActor
      self?.onPresenterOverlayChanged?(active)
    }
  }

  @MainActor
  private func handleScreenRecorderStopped(error: Error?) {
    Task { @RecordingActor in
      let errorMessage = error?.localizedDescription ?? "User cancelled or stopped externally"
      AppLogger.recording.info("🛑 Screen recording stream stopped: \(errorMessage)")

      // CRITICAL: If we're in the middle of switching TO screen, rollback the switch
      if isSwitching, pendingSource == .screen {
        AppLogger.recording.error("🔄 Screen recorder stopped/cancelled during switch TO screen. Rolling back.")
        pendingSource = nil
        currentSource = .camera // Rollback to previous source
        isSwitching = false
        timeCoordinator.startTimeNeedsRecalibration = false
        sourceSwitchTimeoutTask?.cancel()
        sourceSwitchTimeoutTask = nil

        await MainActor.run { [weak self] in
          self?.onError?(AppError.recordingEngineError("Screen sharing was cancelled"))
        }
        return
      }

      // CRITICAL: Notify caller that screen sharing has ended (intentional or otherwise)
      // This ensures AppState/WindowManager can restore the main window and update UI state.
      // We do this if we were either recording from screen OR just using it for preview.
      let wasScreenSharing = currentSource == .screen || pendingSource == .screen
      if wasScreenSharing {
        AppLogger.recording.info("Notifying system that screen share ended externally.")
        await MainActor.run {
          self.onScreenRecordingStoppedExternally?()
        }
      }

      // Cleanup
      if pendingSource == .screen { pendingSource = nil }
      if isSwitching && currentSource == .screen { isSwitching = false }
    }
  }

  // MARK: - UI Test Helpers

  @RecordingActor
  func generateMockVideo(to url: URL) async {
    AppLogger.recording.info("🎥 [UI TEST] Generating mock video at: \(url.path)")

    // Delete existing if any
    try? FileManager.default.removeItem(at: url)

    guard let writer = try? AVAssetWriter(outputURL: url, fileType: .mp4) else {
      AppLogger.recording.error("❌ [UI TEST] Failed to create asset writer")
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

    guard writer.startWriting() else { return }

    writer.startSession(atSourceTime: .zero)

    let adaptor = AVAssetWriterInputPixelBufferAdaptor(
      assetWriterInput: input, sourcePixelBufferAttributes: nil)

    // Wait for input
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
