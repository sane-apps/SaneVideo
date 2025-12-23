//
//  RecordingEngine+Setup.swift
//  SaneVideo
//

import AVFoundation
import Combine
import CoreMedia
import Foundation

extension RecordingEngine {
  // MARK: - Monitoring

  func setupSoundAnalysisMonitoring() {
    Task {
      for await classification in soundAnalysisService.resultsStream.values
      where classification.confidence > 0.7 {
        AppLogger.recording.info(
          "🎯 Detected sound: \(classification.label.displayName) (\(Int(classification.confidence * 100))%)"
        )
      }
    }
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

    Task { @MainActor [weak self] in
      self?.setupScreenRecorderBinding()
      self?.setupScreenRecorderOverlayBinding()
    }
  }

  @MainActor
  private func setupScreenRecorderBinding() {
    screenRecorder.onStop = { [weak self] error in
      self?.handleScreenRecorderStopped(error: error)
    }
  }

  @MainActor
  private func setupScreenRecorderOverlayBinding() {
    screenRecorder.onPresenterOverlayChanged = { [weak self] isPresenterOverlayActive in
      // Forward to AppState via closure callback on MainActor
      self?.onPresenterOverlayChanged?(isPresenterOverlayActive)
    }
  }

  @MainActor
  private func handleScreenRecorderStopped(error: Error?) {
    Task { @RecordingActor in
      // Only act if we expect to be recording from screen and aren't already stopping
      if isRecording, currentSource == .screen, !isStopping {
        let errorMessage = error?.localizedDescription ?? "User cancelled"
        AppLogger.recording.info("Screen recording stopped externally: \(errorMessage)")

        // Nicely ask the app to revert to camera mode.
        await MainActor.run {
          self.onScreenRecordingStoppedExternally?()
        }
      }
    }
  }
}
