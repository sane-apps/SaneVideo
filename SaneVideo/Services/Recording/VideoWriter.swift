//
//  VideoWriter.swift
//  SaneVideo
//
//  Created by SaneVideo Refactor
//

import AVFoundation
import CoreImage
import CoreMedia

@RecordingActor
final class VideoWriter {
    private var assetWriter: AVAssetWriter?
    private var videoInput: AVAssetWriterInput?
    private var micInput: AVAssetWriterInput?
    private var systemAudioInput: AVAssetWriterInput?
    private var pixelBufferAdaptor: AVAssetWriterInputPixelBufferAdaptor?

    private let targetSize = CGSize(width: 1920, height: 1080)
    
    private var sessionStarted = false
    private var finishingTask: Task<URL?, Never>?

    // Use shared CIContext from RenderingService to prevent VFX corruption
    private let ciContext: CIContext

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

    init(renderingService: RenderingService = .shared) {
        self.ciContext = renderingService.ciContext
    }

    func start(outputURL: URL) throws {
        sessionStarted = false
        assetWriter = try AVAssetWriter(outputURL: outputURL, fileType: .mp4)
        assetWriter?.shouldOptimizeForNetworkUse = true

        // Create format hint for 32BGRA pixel format
        var pixelFormatDescription: CMFormatDescription?
        CMVideoFormatDescriptionCreate(
            allocator: kCFAllocatorDefault,
            codecType: kCVPixelFormatType_32BGRA,
            width: Int32(targetSize.width),
            height: Int32(targetSize.height),
            extensions: nil,
            formatDescriptionOut: &pixelFormatDescription
        )

        // Video Settings
        let videoSettings: [String: Any] = [
            AVVideoCodecKey: AVVideoCodecType.h264,
            AVVideoWidthKey: targetSize.width,
            AVVideoHeightKey: targetSize.height
        ]

        let vInput = AVAssetWriterInput(
            mediaType: .video,
            outputSettings: videoSettings,
            sourceFormatHint: pixelFormatDescription
        )
        vInput.expectsMediaDataInRealTime = true
        videoInput = vInput

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

    func writeVideo(sampleBuffer: CMSampleBuffer, presentationTime: CMTime) {
        
        guard let input = videoInput, input.isReadyForMoreMediaData else { return }
        guard let writer = assetWriter, writer.status == .writing else { return }
        guard let adaptor = pixelBufferAdaptor else {
            AppLogger.recording.error("writeVideo: No pixel buffer adaptor!")
            return
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

            let srgbColorSpace = CGColorSpaceCreateDeviceRGB()
            ciContext.render(scaledImage, to: destBuffer, bounds: scaledImage.extent, colorSpace: srgbColorSpace)

            if writer.status == .writing {
                let success = adaptor.append(destBuffer, withPresentationTime: presentationTime)
                if !success {
                    AppLogger.recording.error("Adaptor append failed: \(writer.error?.localizedDescription ?? "unknown")")
                }
            }
        }
    }

    func writeMicAudio(sampleBuffer: CMSampleBuffer) {
        guard let input = micInput, input.isReadyForMoreMediaData else { return }
        input.append(sampleBuffer)
    }

    func writeSystemAudio(sampleBuffer: CMSampleBuffer) {
        guard let input = systemAudioInput, input.isReadyForMoreMediaData else { return }
        input.append(sampleBuffer)
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
                await writer.finishWriting()

                if writer.status == .completed {
                    AppLogger.recording.info("VideoWriter: Successfully finished writing")
                    cleanup()
                    return outputURL
                } else {
                    AppLogger.recording.error("VideoWriter: Finish failed with status \(writer.status.rawValue)")
                    cleanup()
                    return nil
                }
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
    }
}
