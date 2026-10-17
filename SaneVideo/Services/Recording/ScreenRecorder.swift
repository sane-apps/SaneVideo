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

/// Modern screen recorder using SCContentSharingPicker (macOS 14+)
/// This eliminates manual permission handling and provides native macOS UI
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
  /// CRITICAL: This may become stale if display configuration changes
  var baseFilter: SCContentFilter?

  /// Track when baseFilter was set to detect staleness
  private var baseFilterTimestamp: Date?

  /// Output URL for direct recording
  private var currentOutputURL: URL?

  /// Callback triggered when the stream stops (e.g. user cancelled via system UI)
  var onStop: ((Error?) -> Void)?

  var onPresenterOverlayChanged: ((Bool) -> Void)?

  /// Callback triggered when user selects content in the picker
  var onContentSelected: (() -> Void)?

  /// The screen/display frame being recorded (for PiP compositing)
  /// Returns the frame in global screen coordinates for accurate PiP positioning
  var recordingFrame: CGRect? {
    guard let filter = baseFilter else { return nil }
    // For display captures, get the actual display frame including origin
    // includedDisplays requires macOS 15.2+
    if #available(macOS 15.2, *) {
      if let scDisplay = filter.includedDisplays.first {
        // Get the actual NSScreen for this display to get its frame in global coords
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
    // For window captures or macOS 15.0-15.1, we don't have the frame easily accessible
    // Return nil and let VideoWriter use fallback positioning
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

  /// Start screen recording by presenting the system picker
  /// - Parameter outputURL: Optional URL to record directly to file using SCRecordingOutput
  func start(outputURL: URL? = nil) async throws {
    // CRITICAL FIX: Bypass picker in ALL test environments (unit tests AND UI tests)
    // SCContentSharingPicker crashes in unit test environment
    if TestEnvironment.isTesting {
      AppLogger.recording.info(
        "🧪 [TEST] ScreenRecorder: Bypassing system picker (test environment)")
      self.currentOutputURL = outputURL
      // In a real scenario, handleContentSelected would be called by the picker.
      // Here we just stay in a "ready" state for RecordingEngine to "record" samples.
      return
    }

    // CRITICAL: Guard against stopping state
    guard !isStopping else {
      AppLogger.recording.warning("Screen recorder is stopping, cannot start")
      throw NSError(
        domain: "SaneVideo",
        code: -101,
        userInfo: [NSLocalizedDescriptionKey: "Screen recorder is stopping"]
      )
    }

    self.currentOutputURL = outputURL

    // CRITICAL: Stop existing stream if running (prevents multiple streams)
    if activeStream != nil {
      AppLogger.recording.warning("Screen recorder already running, stopping first...")
      await stop()
      try await Task.sleep(nanoseconds: 100_000_000)  // 100ms cleanup delay

      // CRITICAL: Re-check stopping state after cleanup
      guard !isStopping else {
        throw NSError(
          domain: "SaneVideo",
          code: -101,
          userInfo: [NSLocalizedDescriptionKey: "Screen recorder is stopping"]
        )
      }
    }

    // CRITICAL: Check if picker is already active (prevents multiple presentations)
    let picker = SCContentSharingPicker.shared
    if picker.isActive {
      AppLogger.recording.warning("Picker already active, reusing existing selection...")
      // If we have a baseFilter, reuse it
      if let existingFilter = baseFilter {
        onContentSelected?()
        await handleContentSelected(filter: existingFilter)
        return
      }
      // Otherwise, wait a moment and check again
      try await Task.sleep(nanoseconds: 500_000_000)  // 500ms
      if let existingFilter = baseFilter {
        onContentSelected?()
        await handleContentSelected(filter: existingFilter)
        return
      }
      // If still no filter, proceed to present (might be a different picker)
    }

    loggedScreenAudioFormat = false

    // CRITICAL: Only register if not already registered (prevents duplicate observers)
    // (picker already declared above)
    // Check if we're already an observer by checking if picker.isActive and we have baseFilter
    if !picker.isActive || baseFilter == nil {
      picker.add(self)
    }

    picker.isActive = true

    // TAHOE FIX: Limit stream count to prevent redundant picker triggers
    picker.maximumStreamCount = 1

    // TAHOE PERSISTENCE FIX: Check if we already have a valid selection to reuse.
    // This prevents the picker from popping up every time the user switches between Camera and Screen.
    // CRITICAL FIX: Check for staleness - if filter is older than 5 minutes, get fresh one
    if let existingFilter = baseFilter,
       let timestamp = baseFilterTimestamp,
       Date().timeIntervalSince(timestamp) < 300 { // 5 minutes
      AppLogger.recording.info("📺 Reusing existing screen capture filter...")
      await handleContentSelected(filter: existingFilter)
      return
    } else if baseFilter != nil {
      // Filter exists but is stale - clear it
      AppLogger.recording.info("📺 Existing filter is stale, requesting fresh selection")
      baseFilter = nil
      baseFilterTimestamp = nil
    }

    AppLogger.recording.info("📺 No existing filter found. Presenting screen picker...")

    // CRITICAL: Check if picker is already showing (prevents multiple presentations)
    // Note: There's no direct API to check this, so we rely on baseFilter check above
    // If picker was already presented but user hasn't selected yet, we'll get a callback

    // Present the picker with default style (allows windows, displays, apps)
    // User selects content → delegate callback receives SCContentFilter
    var config = SCContentSharingPickerConfiguration()
    config.allowedPickerModes = [
      .singleWindow, .multipleWindows, .singleApplication, .multipleApplications, .singleDisplay
    ]

    // CRITICAL FIX: Exclude PiP and Controls windows from picker
    // This prevents our own windows from appearing as options to share
    let excludedIDs = ServiceContainer.shared.appState.windowManager.excludedWindowIDs
    if !excludedIDs.isEmpty {
      // Convert CGWindowID (UInt32) to Int for SCContentSharingPickerConfiguration
      config.excludedWindowIDs = excludedIDs.map { Int($0) }
      AppLogger.recording.info("📺 Excluding \(excludedIDs.count) windows from picker: \(excludedIDs)")
    }

    picker.configuration = config
    picker.defaultConfiguration = config

    picker.present()

    AppLogger.recording.info("📺 Screen picker presented successfully")
  }

  /// Stop screen recording
  func stop() async {
    // CRITICAL FIX: In test environment, there's no stream to stop
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

    // Stop the active stream
    if let stream = activeStream {
      AppLogger.recording.info("🛑 ScreenRecorder: Initiating stream stop sequence...")

      // 1. If we have a recording output, handle it
      if recordingOutput != nil {
        AppLogger.recording.info("🎥 ScreenRecorder: Stopping recording output...")
        // SCRecordingOutput is stopped when the stream is stopped or can be removed
        // For safety, we can try to remove it if possible, but stopCapture is the main one.
      }

      // 2. Stop capture and wait for completion
      do {
        try await stream.stopCapture()
        AppLogger.recording.info("✅ ScreenRecorder: SCStream.stopCapture() completed")
      } catch {
        AppLogger.recording.warning("⚠️ ScreenRecorder: stopCapture error: \(error.localizedDescription)")
      }
    }

    // 3. Clear references after stop completes
    activeStream = nil
    recordingOutput = nil

    // TAHOE FIX: Do NOT deactivate picker or remove observer here.
    // Keeping picker.isActive = true preserves the selection persistence in the system UI.
    // We only remove/deactivate in a "total teardown" if needed.
    AppLogger.recording.info("Screen stream stopped, but picker remains active for persistence.")
  }

  /// Complete teardown (e.g. app closing)
  func teardown() {
    // CRITICAL FIX: In test environment, skip picker operations to avoid crashes
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

  /// Handle user's content selection and start the stream
  func handleContentSelected(filter: SCContentFilter) async {

    // TAHOE OPTIMIZATION: If we already have an active stream, just update its filter.
    // This is much faster and completely flicker-free.
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
      // Create stream configuration (Apple Silicon optimized)
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

      // Show cursor
      config.showsCursor = true

      // Scaling mode - optimized quality
      config.scalesToFit = true

      // System Audio Capture (macOS 13+)
      config.capturesAudio = true
      // Default false matches Apple docs and preserves playback audio when the user is
      // sharing content inside SaneVideo itself.
      config.excludesCurrentProcessAudio = false

      // Microphone Capture (macOS 15+)
      // DISABLED: Using SCStream for mic triggers system Voice Processing (VPIO)
      // which degrades system audio quality ("tinny" sound).
      // We rely on our dedicated AudioService for high-fidelity mic capture.
      config.captureMicrophone = false

      config.channelCount = 2
      config.sampleRate = 48000

      // Create stream with user's selected content filter
      self.baseFilter = filter
      self.baseFilterTimestamp = Date()

      // Start the first stream with the exact picker-provided filter. Rebuilding the
      // filter before startCapture can lose the picker authorization and surface as
      // SCStreamErrorDomain -3801 ("user declined TCC") even after permission is granted.
      let newStream = SCStream(filter: filter, configuration: config, delegate: self)

      // WindowManager.swift now handles this 150ms after the PiP appears,
      // which completely eliminates the startup flicker.

      // Add video stream output
      try newStream.addStreamOutput(
        self,
        type: .screen,
        sampleHandlerQueue: DispatchQueue(label: "com.sanevideo.screen")
      )

      // Add system audio stream output
      try newStream.addStreamOutput(
        self,
        type: .audio,
        sampleHandlerQueue: DispatchQueue(label: "com.sanevideo.system-audio")
      )

      // Microphone output removed since captureMicrophone is false

      // 5. Setup SCRecordingOutput if an output URL was provided
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

      // Start capture
      try await newStream.startCapture()

      // Store active stream
      activeStream = newStream

      // CRITICAL FIX: Mark that screen recording permission is definitely granted
      // This helps PermissionManager avoid re-requesting permission on next launch
      UserDefaults.standard.set(true, forKey: "screenRecordingEverGranted")

      AppLogger.recording.info("✅ Screen capture started successfully")

    } catch {
      AppLogger.recording.error("❌ Failed to start screen capture: \(error.localizedDescription)")
      // Error will propagate through the recording engine's error handler
    }
  }
}

// MARK: - Delegate conformances in ScreenRecorder+Delegates.swift
