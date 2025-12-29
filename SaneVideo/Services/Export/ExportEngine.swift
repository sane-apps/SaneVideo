//
//  ExportEngine.swift
//  SaneVideo
//
//  Created by SaneVideo Refactor
//

import AVFoundation
import Combine
import CoreMedia
import VideoToolbox

@MainActor
class ExportEngine: ExportServiceProtocol {

  // MARK: - Properties

  private let compositor = ExportCompositor()
  private let progressTracker = ExportProgressTracker()
  private var exportCancellables = Set<AnyCancellable>()
  private var permanentCancellables = Set<AnyCancellable>()

  // Cancellation support
  private var currentExportTask: Task<URL, Error>?

  class ExportSessionState: @unchecked Sendable {
    var isCancelled: Bool = false
  }
  private var currentExportState: ExportSessionState?

  // Performance tracking
  private var currentExportStartTime: Date?
  private var currentExportSettings: SaneExportSettings?

  // MARK: - Public State

  private(set) var isExporting = false
  private(set) var progress: Double = 0

  // Helper for internal use to resolve build error
  private var isCancelled: Bool {
    currentExportState?.isCancelled ?? false
  }

  // MARK: - Initialization

  init() {}

  // MARK: - Export

  func export(
    project: VideoProject,
    settings: SaneExportSettings,
    outputURL: URL,
    progressHandler: @escaping @Sendable (Double) -> Void
  ) async throws -> URL {
    guard !isExporting else {
      throw ExportError.alreadyExporting
    }

    // Pre-flight disk space check
    try validateDiskSpace(for: project, settings: settings, outputURL: outputURL)

    isExporting = true
    let state = ExportSessionState()
    currentExportState = state
    progress = 0
    currentExportStartTime = Date()
    currentExportSettings = settings

    let exportTask = Task {
      try await performAssetWriterExport(
        project: project,
        settings: settings,
        outputURL: outputURL,
        progressHandler: progressHandler
      )
    }

    currentExportTask = exportTask

    do {
      let resultURL = try await exportTask.value
      try await handleExportCompletion(outputURL: resultURL, error: nil)
      return resultURL
    } catch {
      // If strictly cancelled, clean up but maybe don't throw to UI if handled?
      // Usually we throw so UI can show error or "Cancelled" state.
      try await handleExportCompletion(outputURL: outputURL, error: error)
      throw error
    }
  }

  // MARK: - AVAssetWriter Implementation

  private func performAssetWriterExport(
    project: VideoProject,
    settings: SaneExportSettings,
    outputURL: URL,
    progressHandler: @escaping @Sendable (Double) -> Void
  ) async throws -> URL {

    AppLogger.export.info(
      "🚀 Starting AVAssetWriter export: \(settings.resolution.displayName) @ \(settings.bitrate/1_000_000) Mbps"
    )

    // 1. Prepare Composition
    let compositionResult = try await compositor.createComposition(from: project)
    let composition = compositionResult.composition
    let videoComposition = try await compositor.createVideoComposition(
      for: composition,
      baseVideoComposition: compositionResult.videoComposition,
      settings: settings
    )
    let audioMix = compositionResult.audioMix

    // 2. Setup Reader
    let reader = try AVAssetReader(asset: composition)

    // CRITICAL: Guard against empty video tracks - crashes with "videoTracks count >= 1" assertion
    let videoTracks = composition.tracks(withMediaType: .video)
    guard !videoTracks.isEmpty else {
      throw ExportError.invalidProject("Project has no video clips to export")
    }

    // Video Output
    let videoSettings: [String: Any] = [
      kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
      kCVPixelBufferIOSurfacePropertiesKey as String: [:]  // Essential for performance
    ]
    let readerVideoOutput = AVAssetReaderVideoCompositionOutput(
      videoTracks: videoTracks,
      videoSettings: videoSettings
    )
    if let vc = videoComposition {
        readerVideoOutput.videoComposition = vc
    }
    readerVideoOutput.alwaysCopiesSampleData = false

    if reader.canAdd(readerVideoOutput) {
      reader.add(readerVideoOutput)
    } else {
      throw ExportError.failedToCreateSession  // Reuse logic error
    }

    // Audio Output
    var readerAudioOutput: AVAssetReaderAudioMixOutput?
    if !composition.tracks(withMediaType: .audio).isEmpty {
      let audioSettings: [String: Any] = [
        AVFormatIDKey: kAudioFormatLinearPCM,
        AVLinearPCMBitDepthKey: 16,
        AVLinearPCMIsBigEndianKey: false,
        AVLinearPCMIsFloatKey: false,
        AVLinearPCMIsNonInterleaved: false
      ]
      let audioOutput = AVAssetReaderAudioMixOutput(
        audioTracks: composition.tracks(withMediaType: .audio),
        audioSettings: audioSettings
      )
      audioOutput.audioMix = audioMix

      if reader.canAdd(audioOutput) {
        reader.add(audioOutput)
        readerAudioOutput = audioOutput
      }
    }

    // 3. Setup Writer
    if FileManager.default.fileExists(atPath: outputURL.path) {
      try FileManager.default.removeItem(at: outputURL)
    }

    let writer = try AVAssetWriter(outputURL: outputURL, fileType: .mp4)

    // Video Input
    let compressionProps: [String: Any] = [
      AVVideoAverageBitRateKey: settings.bitrate,
      AVVideoProfileLevelKey: getProfileLevel(for: settings.codec),
      AVVideoExpectedSourceFrameRateKey: settings.frameRate,
      // Keyframe interval usually 1x-3x framerate
      AVVideoMaxKeyFrameIntervalKey: Int(settings.frameRate * 2)
    ]

    let writerVideoSettings: [String: Any] = [
      AVVideoCodecKey: settings.codec,
      AVVideoWidthKey: settings.resolution.size.width,
      AVVideoHeightKey: settings.resolution.size.height,
      AVVideoCompressionPropertiesKey: compressionProps
    ]

    let writerVideoInput = AVAssetWriterInput(
      mediaType: .video, outputSettings: writerVideoSettings)
    writerVideoInput.expectsMediaDataInRealTime = false

    if writer.canAdd(writerVideoInput) {
      writer.add(writerVideoInput)
    }

    // Audio Input
    var writerAudioInput: AVAssetWriterInput?
    if readerAudioOutput != nil {
      let writerAudioSettings: [String: Any] = [
        AVFormatIDKey: kAudioFormatMPEG4AAC,
        AVNumberOfChannelsKey: 2,
        AVSampleRateKey: 44100,
        AVEncoderBitRateKey: 192000
      ]
      let input = AVAssetWriterInput(mediaType: .audio, outputSettings: writerAudioSettings)
      input.expectsMediaDataInRealTime = false
      if writer.canAdd(input) {
        writer.add(input)
        writerAudioInput = input
      }
    }

    // 4. Start Processing
    guard reader.startReading() else {
      throw reader.error ?? ExportError.unknown
    }
    guard writer.startWriting() else {
      throw writer.error ?? ExportError.unknown
    }

    writer.startSession(atSourceTime: .zero)

    // Process queues
    let processingQueue = DispatchQueue(label: "com.sanevideo.export", qos: .userInitiated)
    let group = DispatchGroup()

  // Duration for progress
  let duration = composition.duration.seconds
  guard duration > 0 else { throw ExportError.unknown }

  // Wrappers for non-Sendable types in @Sendable closures
  struct UncheckedWriter: @unchecked Sendable { let writer: AVAssetWriter }
  struct UncheckedReader: @unchecked Sendable { let reader: AVAssetReader }
  struct UncheckedVideoInput: @unchecked Sendable { let input: AVAssetWriterInput }
  struct UncheckedVideoOutput: @unchecked Sendable { let output: AVAssetReaderVideoCompositionOutput }
  struct UncheckedAudioInput: @unchecked Sendable { let input: AVAssetWriterInput }
  struct UncheckedAudioOutput: @unchecked Sendable { let output: AVAssetReaderAudioMixOutput }

  let uncheckedWriter = UncheckedWriter(writer: writer)
  let uncheckedReader = UncheckedReader(reader: reader)
  let uncheckedVideoInput = UncheckedVideoInput(input: writerVideoInput)
  let uncheckedVideoOutput = UncheckedVideoOutput(output: readerVideoOutput)

  // Thread-safe state for concurrent access
  final class ExportProgressState: @unchecked Sendable {
    private let lock = NSLock()
    private var _lastProgressUpdate = Date()
    private var _exportError: Error?

    var lastProgressUpdate: Date {
      get { lock.withLock { _lastProgressUpdate } }
      set { lock.withLock { _lastProgressUpdate = newValue } }
    }

    var exportError: Error? {
      get { lock.withLock { _exportError } }
      set { lock.withLock { _exportError = newValue } }
    }
  }
  let progressState = ExportProgressState()

    // Capture cancellation state
    let sessionState = self.currentExportState

  // Video Writer
  group.enter()
  writerVideoInput.requestMediaDataWhenReady(on: processingQueue) { [weak self] in
    let videoInput = uncheckedVideoInput.input
    let videoOutput = uncheckedVideoOutput.output

    var shouldContinue = true
    while videoInput.isReadyForMoreMediaData && shouldContinue {
      // RELIABILITY FIX: autoreleasepool prevents memory buildup during long exports (8K, 2+ hours)
      autoreleasepool {
        if sessionState?.isCancelled == true {
          videoInput.markAsFinished()
          group.leave()
          shouldContinue = false
          return
        }

        if let buffer = videoOutput.copyNextSampleBuffer() {
          if videoInput.append(buffer) {
            // Update Progress
            let pts = CMSampleBufferGetPresentationTimeStamp(buffer).seconds
            let currentProgress = pts / duration

            // Debounce updates to main thread
            if Date().timeIntervalSince(progressState.lastProgressUpdate) > 0.1 {
              progressState.lastProgressUpdate = Date()
              Task { @MainActor [weak self] in
                self?.progress = currentProgress
                progressHandler(currentProgress)
              }
            }
          } else {
            // Write failed
            progressState.exportError = uncheckedWriter.writer.error
            videoInput.markAsFinished()
            group.leave()
            shouldContinue = false
            return
          }
        } else {
          // Done
          videoInput.markAsFinished()
          group.leave()
          shouldContinue = false
          return
        }
      }
    }
  }

  // Audio Writer
  if let writerAudioInput = writerAudioInput, let readerAudioOutput = readerAudioOutput {
    let uncheckedAudioIn = UncheckedAudioInput(input: writerAudioInput)
    let uncheckedAudioOut = UncheckedAudioOutput(output: readerAudioOutput)

    group.enter()
    writerAudioInput.requestMediaDataWhenReady(on: processingQueue) {
      let audioInput = uncheckedAudioIn.input
      let audioOutput = uncheckedAudioOut.output

      while audioInput.isReadyForMoreMediaData {
        if sessionState?.isCancelled == true {
          audioInput.markAsFinished()
          group.leave()
          return
        }

        if let buffer = audioOutput.copyNextSampleBuffer() {
          if !audioInput.append(buffer) {
            progressState.exportError = uncheckedWriter.writer.error
            audioInput.markAsFinished()
            group.leave()
            return
          }
        } else {
          audioInput.markAsFinished()
          group.leave()
          return
        }
      }
    }
  }

  // Timeout for finishWriting operation (60 seconds for complex exports)
  let finishWritingTimeout: TimeInterval = 60.0

  // Wait for inputs to finish
  // We use a safe continuation to bridge the dispatch group wrap
  return try await withCheckedThrowingContinuation { continuation in
    group.notify(queue: processingQueue) {
      // CRITICAL FIX: Use uncheckedWriter/uncheckedReader directly to avoid
      // capturing non-Sendable AVAssetWriter/AVAssetReader in @Sendable closures

      if let error = progressState.exportError {
        continuation.resume(throwing: error)
        return
      }

      if sessionState?.isCancelled == true {
        uncheckedReader.reader.cancelReading()
        uncheckedWriter.writer.cancelWriting()
        continuation.resume(throwing: ExportError.cancelled)
        return
      }

      // CRITICAL FIX: Add timeout to finishWriting to prevent indefinite hangs
      // Use nonisolated(unsafe) to safely share state across closures on same queue
      nonisolated(unsafe) var finishCompleted = false
      let timeoutWorkItem = DispatchWorkItem {
        guard !finishCompleted else { return }
        AppLogger.export.error("❌ Export finishWriting timed out after \(finishWritingTimeout)s")
        uncheckedWriter.writer.cancelWriting()
        continuation.resume(throwing: ExportError.timeout)
      }
      // Wrap in UnsafeSendable to cross @Sendable boundary
      let wrappedTimeout = UnsafeSendable(timeoutWorkItem)

      processingQueue.asyncAfter(deadline: .now() + finishWritingTimeout, execute: timeoutWorkItem)

      // Use uncheckedWriter to avoid Sendable warning in completion closure
      uncheckedWriter.writer.finishWriting {
        finishCompleted = true
        wrappedTimeout.value.cancel()

        if uncheckedWriter.writer.status == .completed {
          continuation.resume(returning: outputURL)
        } else {
          continuation.resume(throwing: uncheckedWriter.writer.error ?? ExportError.unknown)
        }
      }
    }
  }
  }

  // MARK: - Helpers

  private func getProfileLevel(for codec: AVVideoCodecType) -> String {
    // Simple profile selection using string literals to avoid import issues
    // Note: These match the standard keys from VideoToolbox
    if codec == .hevc {
      return "HEVC_Main_AutoLevel"
    } else {
      return "H264_High_AutoLevel"
    }
  }

  /// Pre-flight disk space validation
  /// Estimates required space and checks available capacity before export
  private func validateDiskSpace(for project: VideoProject, settings: SaneExportSettings, outputURL: URL) throws {
    // Calculate project duration
    let duration = project.timeline.duration.seconds
    guard duration > 0 else { return } // Empty project will fail later anyway

    // Estimate file size: (video bitrate + audio bitrate) * duration / 8 bytes
    let videoBitrate = Double(settings.bitrate)
    let audioBitrate: Double = 128_000 // ~128 kbps for AAC
    let totalBitrate = videoBitrate + audioBitrate

    let estimatedBytes = Int64((totalBitrate * duration) / 8.0)
    // Add 30% overhead for container, metadata, B-frames, etc.
    let requiredSpace = Int64(Double(estimatedBytes) * 1.3)

    // Check available space on output volume
    let outputVolume = outputURL.deletingLastPathComponent()
    do {
      let values = try outputVolume.resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey])
      if let available = values.volumeAvailableCapacityForImportantUsage {
        if available < requiredSpace {
          AppLogger.export.error("Insufficient disk space. Required: \(requiredSpace) bytes, Available: \(available) bytes")
          throw ExportError.insufficientDiskSpace(required: requiredSpace, available: available)
        }
        AppLogger.export.info("Disk space check passed. Required: \(requiredSpace) bytes, Available: \(available) bytes")
      }
    } catch let error as ExportError {
      throw error // Re-throw disk space error
    } catch {
      // Log but continue if we can't check (better than blocking)
      AppLogger.export.warning("Failed to check disk space: \(error.localizedDescription). Proceeding with export.")
    }
  }

  private func handleExportCompletion(outputURL: URL, error: Error?) async throws {
    isExporting = false
    currentExportTask = nil

    // Record performance metrics
    if let startTime = currentExportStartTime,
      let settings = currentExportSettings {
      let duration = Date().timeIntervalSince(startTime)
      let operationName = "Export_\(settings.resolution.rawValue)_\(settings.codec.rawValue)"
      let performanceMetrics = ServiceContainer.shared.performanceMetrics

      performanceMetrics.recordOperation(
        name: operationName,
        duration: duration,
        metadata: [
          "resolution": settings.resolution.rawValue,
          "codec": settings.codec.rawValue,
          "bitrate": "\(settings.bitrate)",
          "method": "AVAssetWriter",
          "success": error == nil ? "true" : "false"
        ]
      )

      // Clear tracking
      currentExportStartTime = nil
      currentExportSettings = nil
    }

    if let error = error {
      // Clean up partial file on error
      if FileManager.default.fileExists(atPath: outputURL.path) {
        try? FileManager.default.removeItem(at: outputURL)
      }
      // Add custom logging or toast here if needed
      AppLogger.export.error("❌ Export finished with error: \(error)")
    } else {
      // Force 100% progress
      self.progress = 1.0
      AppLogger.export.info("✅ Export finished successfully")
    }
  }

  func cancelExport() {
    guard isExporting else { return }
    currentExportState?.isCancelled = true
    currentExportTask?.cancel()
    // Completion logic handles the cleanup
  }
}
