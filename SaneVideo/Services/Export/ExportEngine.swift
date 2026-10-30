import AVFoundation
import Combine
import CoreMedia
import VideoToolbox

@MainActor
class ExportEngine: ExportServiceProtocol {
    // MARK: - Properties

    private let compositor = ExportCompositor()
    private let smartCropService = SmartCropService()
    private let progressTracker = ExportProgressTracker()
    private var exportCancellables = Set<AnyCancellable>()
    private var permanentCancellables = Set<AnyCancellable>()

    private var currentExportTask: Task<URL, Error>?

    class ExportSessionState: @unchecked Sendable {
        var isCancelled: Bool = false
    }

    private var currentExportState: ExportSessionState?

    private var currentExportStartTime: Date?
    private var currentExportSettings: SaneExportSettings?

    // MARK: - Public State

    private(set) var isExporting = false
    private(set) var progress: Double = 0

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
            progressHandler(1.0)
            return resultURL
        } catch {
            try await handleExportCompletion(outputURL: outputURL, error: error)
            throw error
        }
    }

    // MARK: - AVAssetWriter Implementation

    /// Maps each clip's smart-crop keyframes (times in its file) onto the timeline: past trims, Clean Up
    /// cuts and speed, at the clip's place. Keyframes in cut or trimmed-off parts are dropped.
    nonisolated static func timelineCropKeyframes(
        clips: [VideoClip],
        keyframesByFile: [URL: [CMTime: SuggestedCrop]]
    ) -> [CMTime: SuggestedCrop] {
        var mapped: [CMTime: SuggestedCrop] = [:]
        for clip in clips {
            for (sourceTime, crop) in keyframesByFile[clip.url] ?? [:] {
                if let timelineTime = clip.timelineTime(forSourceTime: sourceTime) {
                    mapped[timelineTime] = crop
                }
            }
        }
        return mapped
    }

    private func performAssetWriterExport(
        project: VideoProject,
        settings: SaneExportSettings,
        outputURL: URL,
        progressHandler: @escaping @Sendable (Double) -> Void
    ) async throws -> URL {
        AppLogger.export.info(
            "🚀 Starting AVAssetWriter export: \(settings.resolution.displayName) @ \(settings.bitrate / 1_000_000) Mbps"
        )

        // Smart crop runs before building the composition, which needs its keyframes.
        var smartCropKeyframes: [CMTime: SuggestedCrop]?
        if settings.smartCrop.enabled,
           let mainTrack = project.timeline.tracks.first(where: { $0.type == .video && !$0.clips.isEmpty }) {
            AppLogger.export.info("📐 Running smart crop analysis...")
            do {
                // Every clip on the main track, each file once; the first clip's raw file alone left later
                // clips uncropped and put crops at the wrong time after trims, cuts or speed changes.
                var keyframesByFile: [URL: [CMTime: SuggestedCrop]] = [:]
                for clip in mainTrack.clips where keyframesByFile[clip.url] == nil {
                    let cropResult = try await smartCropService.analyzeVideo(
                        sourceURL: clip.url,
                        settings: settings.smartCrop
                    )
                    keyframesByFile[clip.url] = cropResult.keyframes
                }
                let mapped = Self.timelineCropKeyframes(clips: mainTrack.clips, keyframesByFile: keyframesByFile)
                smartCropKeyframes = mapped
                AppLogger.export.info("📐 Smart crop: \(mapped.count) keyframes generated")
            } catch {
                AppLogger.export.warning("⚠️ Smart crop analysis failed: \(error). Continuing without smart crop.")
            }
        }

        let compositionResult = try await compositor.createComposition(from: project, settings: settings)
        let composition = compositionResult.composition
        let videoComposition = try await compositor.createVideoComposition(
            for: composition,
            baseVideoComposition: compositionResult.videoComposition,
            settings: settings,
            smartCropKeyframes: smartCropKeyframes
        )
        let audioMix = compositionResult.audioMix

        let reader = try AVAssetReader(asset: composition)

        // Guard against empty video tracks - crashes with "videoTracks count >= 1" assertion
        let videoTracks = composition.tracks(withMediaType: .video)
        guard !videoTracks.isEmpty else {
            throw ExportError.invalidProject("Project has no video clips to export")
        }

        let videoSettings: [String: Any] = [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
            kCVPixelBufferIOSurfacePropertiesKey as String: [:] // Essential for performance
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
            throw ExportError.failedToCreateSession
        }

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

        // Write in the temp folder, then move into place, so partial files and AVFoundation's own
        // scratch files never appear in the user's Exports folder.
        let tempURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("\(UUID().uuidString).\(outputURL.pathExtension)")

        if FileManager.default.fileExists(atPath: tempURL.path) {
            try FileManager.default.removeItem(at: tempURL)
        }

        // Use MOV container for alpha-supporting codecs (HEVC with Alpha, ProRes 4444)
        // MP4 doesn't properly support alpha channels
        let fileType: AVFileType = settings.codec == .hevcWithAlpha ? .mov : .mp4
        let writer = try AVAssetWriter(outputURL: tempURL, fileType: fileType)
        // Move moov atom to start of file for web streaming fast-start
        // Without this, the entire file must download before playback begins
        writer.shouldOptimizeForNetworkUse = true

        var compressionProps: [String: Any] = [
            AVVideoAverageBitRateKey: settings.bitrate,
            AVVideoExpectedSourceFrameRateKey: settings.frameRate,
            // Keyframe interval usually 1x-3x framerate
            AVVideoMaxKeyFrameIntervalKey: Int(settings.frameRate * 2)
        ]

        if let profileLevel = getProfileLevel(for: settings.codec) {
            compressionProps[AVVideoProfileLevelKey] = profileLevel
        }

        let writerVideoSettings: [String: Any] = [
            AVVideoCodecKey: settings.codec,
            AVVideoWidthKey: settings.renderSize.width,
            AVVideoHeightKey: settings.renderSize.height,
            AVVideoCompressionPropertiesKey: compressionProps,
            AVVideoColorPropertiesKey: VideoColor.rec709
        ]

        let writerVideoInput = AVAssetWriterInput(
            mediaType: .video, outputSettings: writerVideoSettings
        )
        writerVideoInput.expectsMediaDataInRealTime = false

        if writer.canAdd(writerVideoInput) {
            writer.add(writerVideoInput)
        }

        var writerAudioInput: AVAssetWriterInput?
        if readerAudioOutput != nil {
            let writerAudioSettings: [String: Any] = [
                AVFormatIDKey: kAudioFormatMPEG4AAC,
                AVNumberOfChannelsKey: 2,
                AVSampleRateKey: 48000,
                AVEncoderBitRateKey: 192_000
            ]
            let input = AVAssetWriterInput(mediaType: .audio, outputSettings: writerAudioSettings)
            input.expectsMediaDataInRealTime = false
            if writer.canAdd(input) {
                writer.add(input)
                writerAudioInput = input
            }
        }

        guard reader.startReading() else {
            throw reader.error ?? ExportError.unknown
        }
        guard writer.startWriting() else {
            throw writer.error ?? ExportError.unknown
        }

        writer.startSession(atSourceTime: .zero)

        let processingQueue = DispatchQueue(label: "com.sanevideo.export", qos: .userInitiated)
        let group = DispatchGroup()

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

        let sessionState = currentExportState
        nonisolated(unsafe) let progressCallback = progressHandler
        nonisolated(unsafe) let publishProgress: @Sendable (Double) -> Void = { [weak self] currentProgress in
            Task { @MainActor [weak self] in
                self?.progress = currentProgress
                progressCallback(currentProgress)
            }
        }

        group.enter()
        writerVideoInput.requestMediaDataWhenReady(on: processingQueue) {
            let videoInput = uncheckedVideoInput.input
            let videoOutput = uncheckedVideoOutput.output

            var shouldContinue = true
            while videoInput.isReadyForMoreMediaData, shouldContinue {
                // Autoreleasepool prevents memory buildup during long exports (8K, 2+ hours)
                autoreleasepool {
                    if sessionState?.isCancelled == true {
                        videoInput.markAsFinished()
                        group.leave()
                        shouldContinue = false
                        return
                    }

                    if let buffer = videoOutput.copyNextSampleBuffer() {
                        if videoInput.append(buffer) {
                            let pts = CMSampleBufferGetPresentationTimeStamp(buffer).seconds
                            let currentProgress = pts / duration

                            // Debounce updates to main thread
                            if Date().timeIntervalSince(progressState.lastProgressUpdate) > 0.1 {
                                progressState.lastProgressUpdate = Date()
                                publishProgress(currentProgress)
                            }
                        } else {
                            progressState.exportError = uncheckedWriter.writer.error
                            videoInput.markAsFinished()
                            group.leave()
                            shouldContinue = false
                            return
                        }
                    } else {
                        videoInput.markAsFinished()
                        group.leave()
                        shouldContinue = false
                        return
                    }
                }
            }
        }

        if let writerAudioInput, let readerAudioOutput {
            let uncheckedAudioIn = UncheckedAudioInput(input: writerAudioInput)
            let uncheckedAudioOut = UncheckedAudioOutput(output: readerAudioOutput)

            group.enter()
            writerAudioInput.requestMediaDataWhenReady(on: processingQueue) {
                let audioInput = uncheckedAudioIn.input
                let audioOutput = uncheckedAudioOut.output

                var shouldContinue = true
                while audioInput.isReadyForMoreMediaData, shouldContinue {
                    autoreleasepool {
                        if sessionState?.isCancelled == true {
                            audioInput.markAsFinished()
                            group.leave()
                            shouldContinue = false
                            return
                        }

                        if let buffer = audioOutput.copyNextSampleBuffer() {
                            if !audioInput.append(buffer) {
                                progressState.exportError = uncheckedWriter.writer.error
                                audioInput.markAsFinished()
                                group.leave()
                                shouldContinue = false
                                return
                            }
                        } else {
                            audioInput.markAsFinished()
                            group.leave()
                            shouldContinue = false
                            return
                        }
                    }
                }
            }
        }

        let finishWritingTimeout: TimeInterval = 60.0

        return try await withCheckedThrowingContinuation { continuation in
            nonisolated(unsafe) let finalizeExport: @Sendable () -> Void = {
                // Use uncheckedWriter/uncheckedReader directly to avoid
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

                // Add timeout to finishWriting to prevent indefinite hangs
                // Use nonisolated(unsafe) to safely share state across closures on same queue
                nonisolated(unsafe) var finishCompleted = false
                nonisolated(unsafe) var timeoutWorkItem: DispatchWorkItem?
                timeoutWorkItem = DispatchWorkItem {
                    guard !finishCompleted else { return }
                    AppLogger.export.error("❌ Export finishWriting timed out after \(finishWritingTimeout)s")
                    uncheckedWriter.writer.cancelWriting()
                    continuation.resume(throwing: ExportError.timeout)
                }

                processingQueue.asyncAfter(deadline: .now() + finishWritingTimeout, execute: timeoutWorkItem!)

                // Use uncheckedWriter to avoid Sendable warning in completion closure
                nonisolated(unsafe) let completeFinishWriting: @Sendable () -> Void = {
                    finishCompleted = true
                    timeoutWorkItem?.cancel()

                    if uncheckedWriter.writer.status == .completed {
                        // Atomic rename: move temp file to final destination
                        do {
                            if FileManager.default.fileExists(atPath: outputURL.path) {
                                try FileManager.default.removeItem(at: outputURL)
                            }
                            try FileManager.default.moveItem(at: tempURL, to: outputURL)
                            continuation.resume(returning: outputURL)
                        } catch {
                            try? FileManager.default.removeItem(at: tempURL)
                            continuation.resume(throwing: error)
                        }
                    } else {
                        try? FileManager.default.removeItem(at: tempURL)
                        continuation.resume(throwing: uncheckedWriter.writer.error ?? ExportError.unknown)
                    }
                }

                uncheckedWriter.writer.finishWriting(completionHandler: completeFinishWriting)
            }

            group.notify(queue: processingQueue, execute: finalizeExport)
        }
    }

    // MARK: - Helpers

    private func getProfileLevel(for codec: AVVideoCodecType) -> CFString? {
        switch codec {
        case .hevc:
            kVTProfileLevel_HEVC_Main_AutoLevel
        case .hevcWithAlpha:
            // HEVC with Alpha uses Main10 profile for alpha layer support
            kVTProfileLevel_HEVC_Main10_AutoLevel
        case .h264:
            kVTProfileLevel_H264_High_AutoLevel
        default:
            nil
        }
    }

    /// Estimates required space and checks available capacity before export
    private func validateDiskSpace(for project: VideoProject, settings: SaneExportSettings, outputURL: URL) throws {
        let duration = project.timeline.duration.seconds
        guard duration > 0 else { return } // Empty project will fail later anyway

        // Estimate file size: (video bitrate + audio bitrate) * duration / 8 bytes
        let videoBitrate = Double(settings.bitrate)
        let audioBitrate: Double = 128_000 // ~128 kbps for AAC
        let totalBitrate = videoBitrate + audioBitrate

        let estimatedBytes = Int64((totalBitrate * duration) / 8.0)
        // Add 30% overhead for container, metadata, B-frames, etc.
        let requiredSpace = Int64(Double(estimatedBytes) * 1.3)

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
            throw error
        } catch {
            // Log but continue if we can't check (better than blocking)
            AppLogger.export.warning("Failed to check disk space: \(error.localizedDescription). Proceeding with export.")
        }
    }

    private func handleExportCompletion(outputURL: URL, error: Error?) async throws {
        isExporting = false
        currentExportTask = nil

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

            currentExportStartTime = nil
            currentExportSettings = nil
        }

        if let error {
            if FileManager.default.fileExists(atPath: outputURL.path) {
                try? FileManager.default.removeItem(at: outputURL)
            }
            AppLogger.export.error("❌ Export finished with error: \(error)")
        } else {
            progress = 1.0
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
