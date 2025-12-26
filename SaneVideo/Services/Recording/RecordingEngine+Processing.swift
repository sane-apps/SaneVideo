//
//  RecordingEngine+Processing.swift
//  SaneVideo
//

import AppKit
import AVFoundation
import CoreMedia
import Foundation

extension RecordingEngine {
  // MARK: - Sample Processing (Running on processingQueue)

  @RecordingActor func processSample(_ sampleBuffer: CMSampleBuffer, source: RecordingSource) {
    autoreleasepool {
      // Update camera frame for PiP overlay (always, even during screen recording)
      if source == .camera, let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) {
        videoWriter?.updateCameraFrame(pixelBuffer)
      }

      // Update PiP window frame for accurate compositing (only during screen recording)
      // CRITICAL FIX: VideoWriter.updatePiPFrame has its own throttling (10fps) so we just
      // call it directly with nil values - it will fetch the frame when needed.
      // DO NOT create nested Tasks for every frame as this caused deadlocks!

      // Debug guard failures during critical recalibration phase
      if timeCoordinator.startTimeNeedsRecalibration, source == currentSource {
        if isPaused { AppLogger.recording.debug("Drop: isPaused") }
        if !isRecording { AppLogger.recording.debug("Drop: !isRecording") }
        if videoWriter == nil { AppLogger.recording.error("Drop: videoWriter is nil") }
        if let w = videoWriter, !w.isWriting {
          AppLogger.recording.error(
            "Drop: videoWriter is NOT writing. Error: \(String(describing: w.error))")
        }
      }

      // CRITICAL FIX: Allow frames from both currentSource AND pendingSource during the transition.
      // This prevents "dead air" while waiting for the screen picker/stream to start.
      let isTargetSource = (source == currentSource) || (source == pendingSource)

      // CRITICAL: Check basic validity first, but allow writer to be invalid/not-writing momentarily during switch
      guard !isPaused, isRecording, isTargetSource else { return }

      // If we received a sample from the pending source, officially switch over.
      // Doing this BEFORE checking writer.isWriting ensures we don't timeout even if the writer is gap-gapped.
      if source == pendingSource {
        AppLogger.recording.info(
          "Seamless Handoff: Received first frame from \(source). Switching currentSource.")
        currentSource = source
        pendingSource = nil

        // Cancel timeout immediately upon receiving valid frame from new source
        sourceSwitchTimeoutTask?.cancel()
        sourceSwitchTimeoutTask = nil
      }

      // Now ensure writer is ready for actual writing
      guard let writer = videoWriter, writer.isWriting else {
         // If we switched but writer isn't ready (segment gap), it's okay to drop a frame
         // taking care not to error out legit failures (handled by next check)
         return
      }

      // CRITICAL FIX: Check writer status explicitly and error out if failed
      if !writer.isWriting, isRecording, !isPaused, !isSwitching {
        let errorDescription = writer.error?.localizedDescription ?? "Unknown writer error"
        Task { @MainActor in
          self.onError?(AppError.recordingEngineError("Recording failed: \(errorDescription)"))
        }
        return
      }

      let samplePresentationTime = CMSampleBufferGetPresentationTimeStamp(sampleBuffer)

      // Delegate time processing to coordinator
      let result = timeCoordinator.processSampleTime(samplePresentationTime)

      if result.isFirstSample {
        videoWriter?.startSession(at: result.presentationTime)
      }

      // Cancel timeout since we received samples from new source (if recalibrated)
      // Note: processSampleTime handles turning off the recalibration flag internally
      if !timeCoordinator.startTimeNeedsRecalibration {
        sourceSwitchTimeoutTask?.cancel()
        sourceSwitchTimeoutTask = nil
      }

      videoWriter?.writeVideo(sampleBuffer: sampleBuffer, presentationTime: result.presentationTime, source: source)
    }
  }

  @RecordingActor func processAudioSample(_ sampleBuffer: CMSampleBuffer) {
    autoreleasepool {
      // Skip audio when muted.
      // NOTE: We now allow Mic Audio during Screen Recording (PiP) for voiceover.
      guard !isMicMuted else { return }
      guard !isPaused, isRecording, let writer = videoWriter, writer.isWriting else { return }

      // CRITICAL FIX: Block audio during time recalibration (Source Switch)
      guard !timeCoordinator.startTimeNeedsRecalibration else { return }

      let bufferToWrite = timeCoordinator.adjustBufferTime(sampleBuffer)

      // Handle first sample (Mic Audio arriving before Video)
      if timeCoordinator.startTime == .zero {
        let presentationTime = bufferToWrite.presentationTimeStamp
        timeCoordinator.startTime = presentationTime
        timeCoordinator.startTimeNeedsRecalibration = false
        videoWriter?.startSession(at: presentationTime)

        AppLogger.recording.info(
          "Recording started (Mic Audio first). First sample time: \(presentationTime.seconds)")
      }

      if timeCoordinator.startTime != .zero,
        bufferToWrite.presentationTimeStamp >= timeCoordinator.startTime {
        // Write to dedicated Mic Track
        videoWriter?.writeMicAudio(sampleBuffer: bufferToWrite)

        // Real-time Sound Analysis
        soundAnalysisService.analyze(sampleBuffer: sampleBuffer)
      }
    }
  }

  @RecordingActor func processSystemAudioSample(_ sampleBuffer: CMSampleBuffer) {
    autoreleasepool {
      // Only use system audio during screen recording
      guard currentSource == .screen else { return }
      guard !isPaused, isRecording, let writer = videoWriter, writer.isWriting else { return }

      // CRITICAL FIX: Block audio during time recalibration (Source Switch)
      guard !timeCoordinator.startTimeNeedsRecalibration else { return }

      let bufferToWrite = timeCoordinator.adjustBufferTime(sampleBuffer)

      // Handle first sample (System Audio arriving before Video)
      if timeCoordinator.startTime == .zero {
        let presentationTime = bufferToWrite.presentationTimeStamp
        timeCoordinator.startTime = presentationTime
        timeCoordinator.startTimeNeedsRecalibration = false
        videoWriter?.startSession(at: presentationTime)

        AppLogger.recording.info(
          "Recording started (System Audio first). First sample time: \(presentationTime.seconds)")
      }

      if timeCoordinator.startTime != .zero,
        bufferToWrite.presentationTimeStamp >= timeCoordinator.startTime {
        // Write to dedicated System Audio Track
        videoWriter?.writeSystemAudio(sampleBuffer: bufferToWrite)

        // Real-time Sound Analysis (also for system audio)
        // DISABLED to prevent analyzer thrashing (Mono/Stereo flip flop)
        // soundAnalysisService.analyze(sampleBuffer: sampleBuffer)
      }
    }
  }
}
