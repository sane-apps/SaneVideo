import AVFoundation
@preconcurrency import Combine
import CoreMedia
import Foundation
@preconcurrency import ScreenCaptureKit
import SwiftUI

private struct SampleBufferSubjectBox: @unchecked Sendable {
  let subject = PassthroughSubject<CMSampleBuffer, Never>()

  func send(_ sampleBuffer: CMSampleBuffer) {
    subject.send(sampleBuffer)
  }
}

/// Screen recorder built on SCContentSharingPicker (macOS 14+), which supplies the permission and selection UI.
@MainActor
class ScreenRecorder: NSObject, ScreenRecorderProtocol, SCContentSharingPickerObserver, SCStreamDelegate {
  // MARK: - Publishers

  private nonisolated let screenSampleBufferBox = SampleBufferSubjectBox()
  private nonisolated let systemAudioSampleBufferBox = SampleBufferSubjectBox()
  private nonisolated let micSampleBufferBox = SampleBufferSubjectBox()

  /// Publisher for screen frames (nonisolated for Swift 6 concurrency)
  nonisolated var sampleBufferSubject: PassthroughSubject<CMSampleBuffer, Never> {
    screenSampleBufferBox.subject
  }

  /// Publisher for system audio (YouTube, Spotify, etc.)
  nonisolated var audioSampleBufferSubject: PassthroughSubject<CMSampleBuffer, Never> {
    systemAudioSampleBufferBox.subject
  }

  /// Publisher for microphone audio (consolidated in stream)
  nonisolated var micSampleBufferSubject: PassthroughSubject<CMSampleBuffer, Never> {
    micSampleBufferBox.subject
  }

  // MARK: - Private State

  var activeStream: SCStream?
  private var recordingOutput: SCRecordingOutput?
  var isStopping = false
  /// Target output resolution for ScreenCaptureKit frames.
  /// Set by RecordingEngine from UserPreferences before starting capture.
  var targetSize: CGSize = CGSize(width: 1920, height: 1080)

  /// Target output FPS for ScreenCaptureKit frames.
  /// Set by RecordingEngine from UserPreferences before starting capture.
  var targetFrameRate: Double = 60.0
  nonisolated(unsafe) var loggedScreenAudioFormat = false

  /// The original filter selected by the user (usually a display capture)
  /// We keep this to reconstruct the filter when adding/removing exception windows (PiP)
  /// May go stale if the display configuration changes.
  var baseFilter: SCContentFilter?

  /// Track when baseFilter was set to detect staleness
  private var baseFilterTimestamp: Date?

  private var currentOutputURL: URL?

  /// Callback triggered when the stream stops (e.g. user cancelled via system UI)
  var onStop: ((Error?) -> Void)?

  var onPresenterOverlayChanged: ((Bool) -> Void)?

  var onContentSelected: (() -> Void)?

  /// The recorded display's frame in global screen coordinates, for PiP compositing.
  var recordingFrame: CGRect? {
    guard let filter = baseFilter else { return nil }
    // includedDisplays requires macOS 15.2+.
    if #available(macOS 15.2, *) {
      if let scDisplay = filter.includedDisplays.first {
        if let nsScreen = NSScreen.screens.first(where: { screen in
          // Match by size (SCDisplay doesn't expose displayID directly in a convenient way)
          Int(screen.frame.width) == scDisplay.width && Int(screen.frame.height) == scDisplay.height
        }) {
          return nsScreen.frame
        }
        // Fallback: assume main display at origin
        return CGRect(x: 0, y: 0, width: CGFloat(scDisplay.width), height: CGFloat(scDisplay.height))
      }
    }
    // Window captures and macOS 15.0-15.1 give no frame; VideoWriter falls back to default positioning.
    return nil
  }

  override init() {
    super.init()
  }

  deinit {
    NotificationCenter.default.removeObserver(self)
  }

  nonisolated func publishScreenSample(_ sampleBuffer: CMSampleBuffer) {
    screenSampleBufferBox.send(sampleBuffer)
  }

  nonisolated func publishSystemAudioSample(_ sampleBuffer: CMSampleBuffer) {
    systemAudioSampleBufferBox.send(sampleBuffer)
  }

  nonisolated func publishMicSample(_ sampleBuffer: CMSampleBuffer) {
    micSampleBufferBox.send(sampleBuffer)
  }

  // MARK: - Public Interface

  /// - Parameter outputURL: Optional URL to record directly to file using SCRecordingOutput
  func start(outputURL: URL? = nil) async throws {
    // Bypass the picker in all tests; SCContentSharingPicker crashes under unit tests.
    if TestEnvironment.isTesting {
      AppLogger.recording.info(
        "🧪 [TEST] ScreenRecorder: Bypassing system picker (test environment)")
      self.currentOutputURL = outputURL
      // In tests, stay ready so RecordingEngine can record samples without a picker.
      return
    }

    guard !isStopping else {
      AppLogger.recording.warning("Screen recorder is stopping, cannot start")
      throw NSError(
        domain: "SaneVideo",
        code: -101,
        userInfo: [NSLocalizedDescriptionKey: "Screen recorder is stopping"]
      )
    }

    self.currentOutputURL = outputURL

    if activeStream != nil {
      AppLogger.recording.warning("Screen recorder already running, stopping first...")
      await stop()
      try await Task.sleep(nanoseconds: 100_000_000)  // 100ms cleanup delay

      guard !isStopping else {
        throw NSError(
          domain: "SaneVideo",
          code: -101,
          userInfo: [NSLocalizedDescriptionKey: "Screen recorder is stopping"]
        )
      }
    }

    // Check if picker is already active (prevents multiple presentations)
    let picker = SCContentSharingPicker.shared
    if picker.isActive {
      AppLogger.recording.warning("Picker already active, reusing existing selection...")
      if let existingFilter = baseFilter {
        onContentSelected?()
        await handleContentSelected(filter: existingFilter)
        return
      }
      try await Task.sleep(nanoseconds: 500_000_000)  // 500ms
      if let existingFilter = baseFilter {
        onContentSelected?()
        await handleContentSelected(filter: existingFilter)
        return
      }
      // If still no filter, proceed to present (might be a different picker)
    }

    loggedScreenAudioFormat = false

    // Register once: skip if the picker is active and we already have a filter.
    if !picker.isActive || baseFilter == nil {
      picker.add(self)
    }

    picker.isActive = true

    // Limit stream count to prevent redundant picker triggers
    picker.maximumStreamCount = 1

    // Reuse a recent selection so the picker does not reappear on every camera/screen switch; refresh after 5 minutes.
    if let existingFilter = baseFilter,
       let timestamp = baseFilterTimestamp,
       Date().timeIntervalSince(timestamp) < 300 { // 5 minutes
      AppLogger.recording.info("📺 Reusing existing screen capture filter...")
      await handleContentSelected(filter: existingFilter)
      return
    } else if baseFilter != nil {
      AppLogger.recording.info("📺 Existing filter is stale, requesting fresh selection")
      baseFilter = nil
      baseFilterTimestamp = nil
    }

    AppLogger.recording.info("📺 No existing filter found. Presenting screen picker...")

    var config = SCContentSharingPickerConfiguration()
    config.allowedPickerModes = [
      .singleWindow, .multipleWindows, .singleApplication, .multipleApplications, .singleDisplay
    ]

    // Keep our own PiP and controls windows out of the picker.
    let excludedIDs = ServiceContainer.shared.appState.windowManager.excludedWindowIDs
    if !excludedIDs.isEmpty {
      config.excludedWindowIDs = excludedIDs.map { Int($0) }
      AppLogger.recording.info("📺 Excluding \(excludedIDs.count) windows from picker: \(excludedIDs)")
    }

    picker.configuration = config
    picker.defaultConfiguration = config

    picker.present()

    AppLogger.recording.info("📺 Screen picker presented successfully")
  }

  func stop() async {
    if TestEnvironment.isTesting {
      AppLogger.recording.info("🧪 [TEST] ScreenRecorder: stop() called in test environment (no-op)")
      activeStream = nil
      return
    }

    guard activeStream != nil else { return }
    guard !isStopping else {
      AppLogger.recording.warning("Already stopping, skipping")
      return
    }

    isStopping = true
    defer { isStopping = false }

    if let stream = activeStream {
      AppLogger.recording.info("🛑 ScreenRecorder: Initiating stream stop sequence...")

      if recordingOutput != nil {
        AppLogger.recording.info("🎥 ScreenRecorder: Stopping recording output...")
        // Stopping the stream also stops SCRecordingOutput.
      }

      do {
        try await stream.stopCapture()
        AppLogger.recording.info("✅ ScreenRecorder: SCStream.stopCapture() completed")
      } catch {
        AppLogger.recording.warning("⚠️ ScreenRecorder: stopCapture error: \(error.localizedDescription)")
      }
    }

    activeStream = nil
    recordingOutput = nil

    // Leave the picker active so the system keeps the selection.
    AppLogger.recording.info("Screen stream stopped, but picker remains active for persistence.")
  }

  /// Complete teardown (e.g. app closing)
  func teardown() {
    if TestEnvironment.isTesting {
      AppLogger.recording.info(
        "🧪 [TEST] ScreenRecorder: teardown() called in test environment (no-op)")
      activeStream = nil
      return
    }

    let picker = SCContentSharingPicker.shared
    picker.isActive = false
    picker.remove(self)
    activeStream = nil
    AppLogger.recording.info("ScreenRecorder teardown complete")
  }

  // MARK: - Filter Updates

  // MARK: - Private Methods

  func handleContentSelected(filter: SCContentFilter) async {

    // Updating the filter on an existing stream is faster and avoids flicker.
    if let stream = activeStream {
      AppLogger.recording.info("🔄 Updating existing stream with new content selection...")
      self.baseFilter = filter
      self.baseFilterTimestamp = Date()
      do {
        try await stream.updateContentFilter(filter)
        AppLogger.recording.info("✅ Existing stream filter updated successfully")

        return
      } catch {
        AppLogger.recording.warning(
          "⚠️ Failed to update filter on active stream, falling back to recreation: \(error.localizedDescription)"
        )
        // Fallthrough to recreate the stream if update fails
      }
    }

    do {
      let config = SCStreamConfiguration()

      // Resolution - match user preference to avoid unnecessary scaling work
      config.width = Int(targetSize.width)
      config.height = Int(targetSize.height)

      // Frame rate - match user preference to avoid capturing excess frames
      let fps = max(1, min(240, Int(targetFrameRate.rounded())))
      config.minimumFrameInterval = CMTime(value: 1, timescale: CMTimeScale(fps))

      // Pixel format - BGRA for best M1 performance
      config.pixelFormat = kCVPixelFormatType_32BGRA

      // Color space - Display P3 for HDR-like support on Tahoe
      config.colorSpaceName = CGColorSpace.displayP3

      // Queue depth - optimized for low latency
      config.queueDepth = 5

      config.showsCursor = true

      config.scalesToFit = true

      config.capturesAudio = true
      // Default false matches Apple docs and preserves playback audio when the user is
      // sharing content inside SaneVideo itself.
      config.excludesCurrentProcessAudio = false

      // Mic capture through SCStream turns on Voice Processing, which makes system audio sound tinny; AudioService captures the mic instead.
      config.captureMicrophone = false

      config.channelCount = 2
      config.sampleRate = 48000

      self.baseFilter = filter
      self.baseFilterTimestamp = Date()

      // Start the first stream with the exact picker-provided filter. Rebuilding the
      // filter before startCapture can lose the picker authorization and surface as
      // SCStreamErrorDomain -3801 ("user declined TCC") even after permission is granted.
      let newStream = SCStream(filter: filter, configuration: config, delegate: self)

      try newStream.addStreamOutput(
        self,
        type: .screen,
        sampleHandlerQueue: DispatchQueue(label: "com.sanevideo.screen")
      )

      try newStream.addStreamOutput(
        self,
        type: .audio,
        sampleHandlerQueue: DispatchQueue(label: "com.sanevideo.system-audio")
      )

      if let outputURL = currentOutputURL {
        let recordingConfig = SCRecordingOutputConfiguration()
        recordingConfig.outputURL = outputURL
        recordingConfig.outputFileType = .mp4
        // Use HEVC (H.265) for better compression on modern Macs, fallback to H.264
        if #available(macOS 15.0, *) {
          recordingConfig.videoCodecType = .hevc
          AppLogger.recording.info("🎥 Using HEVC (H.265) for hardware recording")
        } else {
          recordingConfig.videoCodecType = .h264
        }

        let output = SCRecordingOutput(configuration: recordingConfig, delegate: self)
        try newStream.addRecordingOutput(output)
        self.recordingOutput = output
        AppLogger.recording.info("🎥 Configured SCRecordingOutput for direct file recording")
      }

      try await newStream.startCapture()

      activeStream = newStream

      // Lets PermissionManager skip re-requesting permission on the next launch.
      UserDefaults.standard.set(true, forKey: "screenRecordingEverGranted")

      AppLogger.recording.info("✅ Screen capture started successfully")

    } catch {
      AppLogger.recording.error("❌ Failed to start screen capture: \(error.localizedDescription)")
      // Error will propagate through the recording engine's error handler
    }
  }
}

// MARK: - Delegate conformances in ScreenRecorder+Delegates.swift
