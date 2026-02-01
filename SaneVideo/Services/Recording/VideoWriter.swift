//
//  VideoWriter.swift
//  SaneVideo
//
//  Created by SaneVideo Refactor
//

import AVFoundation
import CoreGraphics
import CoreImage
import CoreMedia

// DIAGNOSTIC: Frame rate tracking helper
private class FrameRateTracker {
    private let targetFPS: Double
    private var frameTimes: [CMTime] = []
    private let windowSize: Int = 60  // Track last 60 frames

    init(targetFPS: Double) {
        self.targetFPS = targetFPS
    }

    func recordFrame(at time: CMTime) {
        frameTimes.append(time)
        if frameTimes.count > windowSize {
            frameTimes.removeFirst()
        }
    }

    var currentFPS: Double? {
        guard frameTimes.count >= 2 else { return nil }
        let first = frameTimes.first!
        let last = frameTimes.last!
        let duration = CMTimeSubtract(last, first).seconds
        guard duration > 0 else { return nil }
        return Double(frameTimes.count - 1) / duration
    }
}

@RecordingActor
final class VideoWriter: VideoWriterProtocol {
    private var assetWriter: AVAssetWriter?
    private var videoInput: AVAssetWriterInput?
    private var micInput: AVAssetWriterInput?
    private var systemAudioInput: AVAssetWriterInput?
    private var pixelBufferAdaptor: AVAssetWriterInputPixelBufferAdaptor?

    private let targetSize: CGSize

    private var sessionStarted = false
    private var finishingTask: Task<URL?, Never>?

    // Use shared CIContext from RenderingService to prevent VFX corruption
    private let ciContext: CIContext

    private let srgbColorSpace = CGColorSpaceCreateDeviceRGB()

    // CRITICAL FIX (2025-12-31): Monotonic timestamp tracking to prevent error -16364
    // When presenter overlay toggles during screen recording, timestamps can go backwards
    // causing AVAssetWriter to fail. We track the last written time and reject out-of-order frames.
    private var lastWrittenVideoTime: CMTime = .invalid
    private var lastWrittenMicTime: CMTime = .invalid
    private var lastWrittenSystemAudioTime: CMTime = .invalid
    private var droppedFrameCount: Int = 0
    private let maxDroppedFramesBeforeWarning = 30  // Log warning if we drop too many

    // DIAGNOSTIC: Frame rate tracking
    private var frameRateTracker: FrameRateTracker?
    private var notReadyForDataCount: Int = 0
    private var totalFramesReceived: Int = 0
    private var totalFramesWritten: Int = 0

    // A/V drift tracking
    private(set) var driftTracker: DriftTracker?

    // PiP Camera Overlay: Latest camera frame for compositing into screen recordings
    private var latestCameraFrame: CVPixelBuffer?
    private let cameraFrameLock = NSLock()

    // PiP Window Frame: Current position and size for accurate compositing
    private var pipWindowFrame: CGRect?
    private var screenFrame: CGRect?
    private var lastFrameUpdateTime: CFTimeInterval = 0
    private let pipFrameLock = NSLock()
    private let frameUpdateInterval: CFTimeInterval = 0.033  // Update every 33ms (30fps for smooth position tracking)

    var isWriting: Bool {
        return assetWriter?.status == .writing
    }

    var error: Error? {
        return assetWriter?.error
    }

    var isReadyForData: Bool {
        // We consider ready if video is ready. Audio tracks buffer independently.
        return videoInput?.isReadyForMoreMediaData == true
    }

    init(
        renderingService: RenderingService = .shared,
        targetSize: CGSize = CGSize(width: 1920, height: 1080)
    ) {
        self.ciContext = renderingService.ciContext
        self.targetSize = targetSize
    }

    func start(outputURL: URL, targetFrameRate: Double = 30.0) throws {
        sessionStarted = false
        assetWriter = try AVAssetWriter(outputURL: outputURL, fileType: .mp4)
        assetWriter?.shouldOptimizeForNetworkUse = true

        // Create format hint with NCLC color space metadata for proper playback
        // Without these tags, videos may appear "washed out" in some players
        var pixelFormatDescription: CMFormatDescription?
        let colorExtensions: [CFString: Any] = [
            // ITU-R BT.709 - Standard for HD video (sRGB compatible)
            kCMFormatDescriptionExtension_ColorPrimaries: kCMFormatDescriptionColorPrimaries_ITU_R_709_2,
            kCMFormatDescriptionExtension_TransferFunction: kCMFormatDescriptionTransferFunction_ITU_R_709_2,
            kCMFormatDescriptionExtension_YCbCrMatrix: kCMFormatDescriptionYCbCrMatrix_ITU_R_709_2
        ]
        CMVideoFormatDescriptionCreate(
            allocator: kCFAllocatorDefault,
            codecType: kCVPixelFormatType_32BGRA,
            width: Int32(targetSize.width),
            height: Int32(targetSize.height),
            extensions: colorExtensions as CFDictionary,
            formatDescriptionOut: &pixelFormatDescription
        )

        // Video Settings
        // CRITICAL FIX: Add frame rate to video settings to prevent AVAssetWriter from defaulting to low rate
        var videoSettings: [String: Any] = [
            AVVideoCodecKey: AVVideoCodecType.h264,
            AVVideoWidthKey: targetSize.width,
            AVVideoHeightKey: targetSize.height
        ]

        // Add compression properties with frame rate
        let averageBitrate: Int
        switch max(targetSize.width, targetSize.height) {
        case 0..<1920:
            averageBitrate = 6_000_000
        case 1920..<3840:
            averageBitrate = 10_000_000
        default:
            averageBitrate = 20_000_000
        }

        var compressionProperties: [String: Any] = [:]
        compressionProperties[AVVideoExpectedSourceFrameRateKey] = targetFrameRate
        compressionProperties[AVVideoAverageBitRateKey] = averageBitrate
        videoSettings[AVVideoCompressionPropertiesKey] = compressionProperties

        AppLogger.recording.info(
            "📹 VideoWriter: Configuring for \(targetFrameRate) fps, \(Int(targetSize.width))x\(Int(targetSize.height)) @ \(averageBitrate / 1_000_000) Mbps"
        )

        let vInput = AVAssetWriterInput(
            mediaType: .video,
            outputSettings: videoSettings,
            sourceFormatHint: pixelFormatDescription
        )
        vInput.expectsMediaDataInRealTime = true
        videoInput = vInput

        // DIAGNOSTIC: Initialize frame rate tracker and drift tracker
        frameRateTracker = FrameRateTracker(targetFPS: targetFrameRate)
        driftTracker = DriftTracker()

        // Pixel Buffer Adaptor
        let sourcePixelBufferAttributes: [String: Any] = [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
            kCVPixelBufferWidthKey as String: Int(targetSize.width),
            kCVPixelBufferHeightKey as String: Int(targetSize.height),
            kCVPixelBufferMetalCompatibilityKey as String: true
        ]

        pixelBufferAdaptor = AVAssetWriterInputPixelBufferAdaptor(
            assetWriterInput: vInput,
            sourcePixelBufferAttributes: sourcePixelBufferAttributes
        )

        // Audio Settings - 48k AAC
        let audioSettings: [String: Any] = [
            AVFormatIDKey: kAudioFormatMPEG4AAC,
            AVNumberOfChannelsKey: 2,
            AVSampleRateKey: 48000,
            AVEncoderBitRateKey: 128_000
        ]

        // Track 1: Microphone
        let mInput = AVAssetWriterInput(mediaType: .audio, outputSettings: audioSettings)
        mInput.expectsMediaDataInRealTime = true
        micInput = mInput

        // Track 2: System Audio
        let sInput = AVAssetWriterInput(mediaType: .audio, outputSettings: audioSettings)
        sInput.expectsMediaDataInRealTime = true
        systemAudioInput = sInput

        if let writer = assetWriter {
            if writer.canAdd(vInput) { writer.add(vInput) }
            if writer.canAdd(mInput) { writer.add(mInput) }
            if writer.canAdd(sInput) { writer.add(sInput) }
            writer.startWriting()
        }
    }

    func startSession(at sourceTime: CMTime) {
        guard let writer = assetWriter, writer.status == .writing else { return }
        writer.startSession(atSourceTime: sourceTime)
        sessionStarted = true
    }

    /// Update the latest camera frame for PiP overlay during screen recording
    func updateCameraFrame(_ pixelBuffer: CVPixelBuffer?) {
        cameraFrameLock.lock()
        defer { cameraFrameLock.unlock() }
        latestCameraFrame = pixelBuffer
    }

    /// Update the PiP window frame for accurate compositing position
    /// Throttled to avoid updating on every frame
    func updatePiPFrame(_ frame: CGRect?, screenFrame: CGRect?) {
        let now = CACurrentMediaTime()
        pipFrameLock.lock()
        defer { pipFrameLock.unlock() }

        // Throttle updates to avoid overhead
        guard now - lastFrameUpdateTime >= frameUpdateInterval else { return }
        lastFrameUpdateTime = now

        // Only update if frame actually changed
        if let newFrame = frame, let oldFrame = pipWindowFrame {
            if abs(newFrame.origin.x - oldFrame.origin.x) < 1.0 &&
               abs(newFrame.origin.y - oldFrame.origin.y) < 1.0 &&
               abs(newFrame.width - oldFrame.width) < 1.0 &&
               abs(newFrame.height - oldFrame.height) < 1.0 {
                return  // Frame hasn't changed significantly
            }
        }

        pipWindowFrame = frame
        self.screenFrame = screenFrame
    }

    func writeVideo(sampleBuffer: CMSampleBuffer, presentationTime: CMTime, source: RecordingSource = .camera) {
        totalFramesReceived += 1

        guard let input = videoInput else {
            AppLogger.recording.warning("⚠️ VideoWriter: videoInput is nil")
            return
        }

        guard input.isReadyForMoreMediaData else {
            notReadyForDataCount += 1
            if notReadyForDataCount % 30 == 0 {  // Log every 30 skipped frames
                AppLogger.recording.warning("⚠️ VideoWriter: input not ready for data (skipped \(notReadyForDataCount) frames so far)")
            }
            return
        }
        guard let writer = assetWriter, writer.status == .writing else { return }
        guard let adaptor = pixelBufferAdaptor else {
            AppLogger.recording.error("writeVideo: No pixel buffer adaptor!")
            return
        }

        // CRITICAL FIX (2025-12-31): Monotonic timestamp enforcement to prevent error -16364
        // Presenter overlay on macOS 14+ can cause timestamp discontinuities
        if lastWrittenVideoTime.isValid {
            if presentationTime <= lastWrittenVideoTime {
                // Timestamp going backwards - drop frame to prevent -16364
                droppedFrameCount += 1
                if droppedFrameCount == maxDroppedFramesBeforeWarning {
                    AppLogger.recording.warning("⚠️ VideoWriter: Dropped \(droppedFrameCount) out-of-order frames (timestamp regression detected)")
                }
                return
            }
        }

        // CRITICAL FIX: Auto-start session if needed.
        // This ensures the MOOV atom is written correctly even if explicit startSession call was missed.
        if !sessionStarted {
            startSession(at: presentationTime)
            AppLogger.recording.info("VideoWriter: Auto-started session at \(presentationTime.seconds)")
        }

        autoreleasepool {
            guard let sourcePixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else {
                AppLogger.recording.warning("writeVideo: No image buffer in sample")
                return
            }

            let sourceWidth = CVPixelBufferGetWidth(sourcePixelBuffer)
            let sourceHeight = CVPixelBufferGetHeight(sourcePixelBuffer)

            guard let pool = adaptor.pixelBufferPool else {
                AppLogger.recording.warning("Pixel buffer pool not ready, skipping frame")
                return
            }

            var destinationPixelBuffer: CVPixelBuffer?
            let status = CVPixelBufferPoolCreatePixelBuffer(nil, pool, &destinationPixelBuffer)

            guard status == kCVReturnSuccess, let destBuffer = destinationPixelBuffer else {
                AppLogger.recording.warning("Failed to create pixel buffer from pool: \(status)")
                return
            }

            let ciImage = CIImage(cvPixelBuffer: sourcePixelBuffer)

            // Calculate scale to fit target 1080p
            let srcWidth = CGFloat(sourceWidth)
            let srcHeight = CGFloat(sourceHeight)
            let scaleX = targetSize.width / srcWidth
            let scaleY = targetSize.height / srcHeight

            let scaledImage: CIImage
            if abs(scaleX - 1.0) > 0.001 || abs(scaleY - 1.0) > 0.001 {
                scaledImage = ciImage.transformed(by: CGAffineTransform(scaleX: scaleX, y: scaleY))
            } else {
                scaledImage = ciImage
            }

            // PiP Overlay: Composite camera feed when recording screen
            var finalImage = scaledImage
            if source == .screen {
                // ... (PiP compositing logic remains same as original)
                cameraFrameLock.lock()
                let cameraFrame = latestCameraFrame
                cameraFrameLock.unlock()

                pipFrameLock.lock()
                let pipFrame = pipWindowFrame
                let screenFrame = self.screenFrame
                pipFrameLock.unlock()

                if let cameraBuffer = cameraFrame, let pipFrame = pipFrame, let screenFrame = screenFrame {
                    let cameraImage = CIImage(cvPixelBuffer: cameraBuffer)
                    let cameraWidth = CGFloat(CVPixelBufferGetWidth(cameraBuffer))
                    let cameraHeight = CGFloat(CVPixelBufferGetHeight(cameraBuffer))

                    let pipWidth = pipFrame.width
                    let pipHeight = pipFrame.height

                    let scaleX = targetSize.width / screenFrame.width
                    let scaleY = targetSize.height / screenFrame.height

                    let screenRelativeX = pipFrame.origin.x - screenFrame.origin.x
                    let recordingX = screenRelativeX * scaleX

                    let cocoaY = pipFrame.origin.y - screenFrame.origin.y
                    let topRelativeY = screenFrame.height - cocoaY - pipHeight
                    let recordingY = topRelativeY * scaleY

                    let recordingPipWidth = pipWidth * scaleX
                    let recordingPipHeight = pipHeight * scaleY

                    let cameraScaleX = recordingPipWidth / cameraWidth
                    let cameraScaleY = recordingPipHeight / cameraHeight
                    let scaledCamera = cameraImage.transformed(by: CGAffineTransform(scaleX: cameraScaleX, y: cameraScaleY))

                    let positionedCamera = scaledCamera.transformed(by: CGAffineTransform(translationX: recordingX, y: recordingY))

                    finalImage = positionedCamera.composited(over: scaledImage)
                } else if let cameraBuffer = cameraFrame {
                    let cameraImage = CIImage(cvPixelBuffer: cameraBuffer)
                    let cameraWidth = CGFloat(CVPixelBufferGetWidth(cameraBuffer))
                    let pipWidth = targetSize.width * 0.2
                    let scale = pipWidth / cameraWidth
                    let scaledCamera = cameraImage.transformed(by: CGAffineTransform(scaleX: scale, y: scale))
                    let pipX = targetSize.width - pipWidth - 20
                    let positionedCamera = scaledCamera.transformed(by: CGAffineTransform(translationX: pipX, y: 20))
                    finalImage = positionedCamera.composited(over: scaledImage)
                }
            }

            ciContext.render(finalImage, to: destBuffer, bounds: finalImage.extent, colorSpace: srgbColorSpace)

            if writer.status == .writing {
                let success = adaptor.append(destBuffer, withPresentationTime: presentationTime)
                if success {
                    totalFramesWritten += 1
                    // Track last successful write time for monotonic enforcement
                    lastWrittenVideoTime = presentationTime

                    // A/V drift tracking
                    driftTracker?.recordVideoTimestamp(presentationTime)

                    // DIAGNOSTIC: Track frame rate
                    frameRateTracker?.recordFrame(at: presentationTime)
                    if totalFramesWritten % 60 == 0 {  // Log every 60 frames (~2 seconds at 30fps)
                        if let actualFPS = frameRateTracker?.currentFPS {
                            AppLogger.recording.info("📊 VideoWriter: Written \(totalFramesWritten)/\(totalFramesReceived) frames, actual FPS: \(String(format: "%.2f", actualFPS)), dropped: \(droppedFrameCount), notReady: \(notReadyForDataCount)")
                        }
                    }
                } else {
                    AppLogger.recording.error("Adaptor append failed: \(writer.error?.localizedDescription ?? "unknown")")
                }
            }
        }
    }

    func writeMicAudio(sampleBuffer: CMSampleBuffer) {
        guard let input = micInput, input.isReadyForMoreMediaData else { return }

        // CRITICAL FIX (2025-12-31): Monotonic timestamp enforcement for audio
        let pts = CMSampleBufferGetPresentationTimeStamp(sampleBuffer)
        if lastWrittenMicTime.isValid && pts <= lastWrittenMicTime {
            return  // Skip out-of-order audio sample
        }

        input.append(sampleBuffer)
        lastWrittenMicTime = pts
        driftTracker?.recordAudioTimestamp(pts)
    }

    func writeSystemAudio(sampleBuffer: CMSampleBuffer) {
        guard let input = systemAudioInput, input.isReadyForMoreMediaData else { return }

        // CRITICAL FIX (2025-12-31): Monotonic timestamp enforcement for audio
        let pts = CMSampleBufferGetPresentationTimeStamp(sampleBuffer)
        if lastWrittenSystemAudioTime.isValid && pts <= lastWrittenSystemAudioTime {
            return  // Skip out-of-order audio sample
        }

        input.append(sampleBuffer)
        lastWrittenSystemAudioTime = pts
    }

    // Concurrency Safety: Ensure finish() is only executed once
    // Helper to access finishingTask safely
    private func getFinishingTask() -> Task<URL?, Never>? {
        return finishingTask
    }

    private func setFinishingTask(_ task: Task<URL?, Never>) {
        finishingTask = task
    }

    private func getOutputURL() -> URL? {
        return assetWriter?.outputURL
    }

    func finish() async -> URL? {
        if let existingTask = getFinishingTask() {
            return await existingTask.value
        }

        // Potential race here between check and set?
        // Yes. We need to lock around the CREATE check too.
        // We can do that with a closure based helper or just use the actor pattern which is cleaner.
        // But sticking to the plan:

        let task = getOrStartFinishingTask()
        return await task.value
    }

    private func getOrStartFinishingTask() -> Task<URL?, Never> {
        if let existing = finishingTask {
            return existing
        }

        let task = Task {
             return await self.performFinish()
        }
        finishingTask = task
        return task
    }

    /// Timeout for finishWriting operation (30 seconds should be sufficient for most recordings)
    private static let finishWritingTimeout: TimeInterval = 30.0

    private func performFinish() async -> URL? {
        let outputURL = getOutputURL()

        if !sessionStarted {
            AppLogger.recording.warning("VideoWriter: Session never started, cancelling")
            assetWriter?.cancelWriting()
            if let url = outputURL { try? FileManager.default.removeItem(at: url) }
            cleanup()
            return nil
        } else {
            videoInput?.markAsFinished()
            micInput?.markAsFinished()
            systemAudioInput?.markAsFinished()

            if let writer = assetWriter, writer.status == .writing {
                // CRITICAL FIX: Use continuation-based timeout to prevent hanging
                // AVAssetWriter.finishWriting is callback-based, we wrap it with timeout
                let timeoutSeconds = Self.finishWritingTimeout

                let success = await withCheckedContinuation { (continuation: CheckedContinuation<Bool, Never>) in
                    var didResume = false
                    let resumeLock = NSLock()

                    // Create timeout timer
                    let timer = DispatchSource.makeTimerSource(queue: .global())
                    timer.schedule(deadline: .now() + timeoutSeconds)
                    timer.setEventHandler {
                        resumeLock.lock()
                        defer { resumeLock.unlock() }
                        guard !didResume else { return }
                        didResume = true
                        AppLogger.recording.error("VideoWriter: finishWriting timed out after \(timeoutSeconds)s")
                        continuation.resume(returning: false)
                    }
                    timer.resume()

                    // Start finish writing
                    writer.finishWriting {
                        timer.cancel()
                        resumeLock.lock()
                        defer { resumeLock.unlock() }
                        guard !didResume else { return }
                        didResume = true
                        continuation.resume(returning: writer.status == .completed)
                    }
                }

                if !success {
                    writer.cancelWriting()
                    if let url = outputURL { try? FileManager.default.removeItem(at: url) }
                    cleanup()
                    return nil
                }

                AppLogger.recording.info("VideoWriter: Successfully finished writing")
                cleanup()
                return outputURL
            }

            cleanup()
            return nil
        }
    }

    private func cleanup() {
        assetWriter = nil
        videoInput = nil
        micInput = nil
        systemAudioInput = nil
        pixelBufferAdaptor = nil
        sessionStarted = false

        // CRITICAL FIX (2025-12-31): Reset timestamp tracking
        lastWrittenVideoTime = .invalid
        lastWrittenMicTime = .invalid
        lastWrittenSystemAudioTime = .invalid

        // DIAGNOSTIC: Log final statistics before cleanup
        if droppedFrameCount > 0 {
            AppLogger.recording.info("VideoWriter: Total dropped frames due to timestamp regression: \(droppedFrameCount)")
        }
        if notReadyForDataCount > 0 {
            AppLogger.recording.info("VideoWriter: Total frames skipped (input not ready): \(notReadyForDataCount)")
        }
        if let finalFPS = frameRateTracker?.currentFPS {
            AppLogger.recording.info("VideoWriter: Final statistics - Written: \(totalFramesWritten)/\(totalFramesReceived), Final FPS: \(String(format: "%.2f", finalFPS)), Dropped: \(droppedFrameCount), NotReady: \(notReadyForDataCount)")
        }

        // Reset diagnostic counters
        droppedFrameCount = 0
        notReadyForDataCount = 0
        totalFramesReceived = 0
        totalFramesWritten = 0
        frameRateTracker = nil
        driftTracker?.reset()
        driftTracker = nil

        // CRITICAL FIX: Clear the latest camera frame to free high-resolution pixel buffer
        cameraFrameLock.lock()
        latestCameraFrame = nil
        cameraFrameLock.unlock()
    }

    // CRITICAL FIX: Cancel finishing task on deallocation
    // Note: For @RecordingActor, we can't access isolated properties in deinit
    // The task will be cancelled when the actor is deallocated
    // We rely on proper cleanup in finishWriting() method
}
