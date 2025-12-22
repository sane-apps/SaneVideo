import Foundation
import Combine
import CoreMedia
@preconcurrency import ScreenCaptureKit

/// Modern screen recorder using SCContentSharingPicker (macOS 14+)
/// This eliminates manual permission handling and provides native macOS UI
@MainActor
class ScreenRecorder: NSObject, SCContentSharingPickerObserver, SCStreamDelegate {
    // MARK: - Publishers
    
    /// Publisher for screen frames (nonisolated for Swift 6 concurrency)
    nonisolated(unsafe) let sampleBufferSubject = PassthroughSubject<CMSampleBuffer, Never>()
    
    /// Publisher for system audio (YouTube, Spotify, etc.)
    nonisolated(unsafe) let audioSampleBufferSubject = PassthroughSubject<CMSampleBuffer, Never>()
    
    /// Publisher for microphone audio (consolidated in stream)
    nonisolated(unsafe) let micSampleBufferSubject = PassthroughSubject<CMSampleBuffer, Never>()
    
    // MARK: - Private State
    
    private var activeStream: SCStream?
    private var recordingOutput: SCRecordingOutput?
    private var isStopping = false
    private let targetSize = CGSize(width: 1920, height: 1080)
    nonisolated(unsafe) private var loggedScreenAudioFormat = false
    
    /// Output URL for direct recording
    private var currentOutputURL: URL?

    /// Callback triggered when the stream stops (e.g. user cancelled via system UI)
    var onStop: ((Error?) -> Void)?
    
    /// Callback triggered when Presenter Overlay state changes (active/inactive)
    var onPresenterOverlayChanged: ((Bool) -> Void)?

    // MARK: - Public Interface
    
    /// Start screen recording by presenting the system picker
    /// - Parameter outputURL: Optional URL to record directly to file using SCRecordingOutput
    func start(outputURL: URL? = nil) async throws {
        let isTesting = ProcessInfo.processInfo.arguments.contains("-uitesting")
        if isTesting {
            AppLogger.recording.info("🧪 [UI TEST] ScreenRecorder: Bypassing system picker")
            self.currentOutputURL = outputURL
            // In a real scenario, handleContentSelected would be called by the picker.
            // Here we just stay in a "ready" state for RecordingEngine to "record" samples.
            return
        }
        
        // Guard against stopping state
        guard !isStopping else {
            AppLogger.recording.warning("Screen recorder is stopping, cannot start")
            throw NSError(
                domain: "SaneVideo",
                code: -101,
                userInfo: [NSLocalizedDescriptionKey: "Screen recorder is stopping"]
            )
        }
        
        self.currentOutputURL = outputURL
        
        // Stop existing stream if running
        if activeStream != nil {
            AppLogger.recording.warning("Screen recorder already running, stopping first...")
            await stop()
            try await Task.sleep(nanoseconds: 100_000_000) // 100ms cleanup delay
        }
        
        loggedScreenAudioFormat = false
        
        let picker = SCContentSharingPicker.shared
        
        // Register as observer
        picker.add(self)
        picker.isActive = true
        
        AppLogger.recording.info("📺 Presenting screen picker to user...")
        
        // Present the picker with default style (allows windows, displays, apps)
        // User selects content → delegate callback receives SCContentFilter
        var config = SCContentSharingPickerConfiguration()
        config.allowedPickerModes = [.singleWindow, .multipleWindows, .singleApplication, .multipleApplications, .singleDisplay]
        picker.configuration = config
        
        picker.present()
        
        AppLogger.recording.info("📺 Screen picker presented successfully")
    }
    
    /// Stop screen recording
    func stop() async {
        guard !isStopping else {
            AppLogger.recording.warning("Already stopping, skipping")
            return
        }
        
        isStopping = true
        defer { isStopping = false }
        
        // Stop the active stream
        if let stream = activeStream {
            do {
                try await stream.stopCapture()
                AppLogger.recording.info("Screen Recorder Stopped")
            } catch {
                AppLogger.recording.warning("Screen Recorder stop error (non-fatal): \(error.localizedDescription)")
            }
        }
        
        activeStream = nil
        
        // Deactivate picker
        let picker = SCContentSharingPicker.shared
        picker.isActive = false
        picker.remove(self)
    }
    
    // MARK: - SCContentSharingPickerObserver
    
    /// Called when user selects content in the picker
    nonisolated func contentSharingPicker(
        _ picker: SCContentSharingPicker,
        didUpdateWith filter: SCContentFilter,
        for stream: SCStream?
    ) {
        Task { @MainActor in
            AppLogger.recording.info("📺 User selected content, starting capture...")
            await handleContentSelected(filter: filter)
        }
    }
    
    /// Called when user cancels the picker
    nonisolated func contentSharingPicker(
        _ picker: SCContentSharingPicker,
        didCancelFor stream: SCStream?
    ) {
        AppLogger.recording.info("📺 User cancelled screen picker")
        // Graceful cancellation - no error needed
    }
    
    /// Called when picker fails to start
    nonisolated func contentSharingPickerStartDidFailWithError(_ error: Error) {
        AppLogger.recording.error("📺 Picker failed to start: \(error.localizedDescription)")
    }
    
    // MARK: - Private Methods
    
    /// Handle user's content selection and start the stream
    private func handleContentSelected(filter: SCContentFilter) async {
        do {
            // Create stream configuration (Apple Silicon optimized)
            let config = SCStreamConfiguration()
            
            // Resolution - 1080p for good quality/performance balance
            config.width = Int(targetSize.width)
            config.height = Int(targetSize.height)
            
            // Frame rate - 60fps for smooth recording
            config.minimumFrameInterval = CMTime(value: 1, timescale: 60)
            
            // Pixel format - BGRA for best M1 performance
            config.pixelFormat = kCVPixelFormatType_32BGRA
            
            // Color space - Display P3 for HDR support on Tahoe
            config.colorSpaceName = CGColorSpace.displayP3
            
            // HDR Capture (macOS 15.4 / 26 Tahoe +)
            // Note: Temporarily disabled due to SDK mismatch in build environment
            /*
            if #available(macOS 15.4, *) {
                config.captureHDR = true
            }
            */
            
            // Queue depth - optimized for low latency
            config.queueDepth = 5
            
            // Show cursor
            config.showsCursor = true
            
            // Scaling mode - optimized quality
            config.scalesToFit = true
            
            // System Audio Capture (macOS 13+)
            config.capturesAudio = true
            config.excludesCurrentProcessAudio = true
            
            // Microphone Capture (macOS 15+)
            // This consolidates all audio into a single stream for perfect sync
            config.captureMicrophone = true
            
            config.channelCount = 2
            config.sampleRate = 48000
            
            // Create stream with user's selected content filter
            // Use self as delegate to handle stream errors and interruptions
            let newStream = SCStream(filter: filter, configuration: config, delegate: self)
            
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

            // Add microphone audio stream output
            try newStream.addStreamOutput(
                self,
                type: .microphone,
                sampleHandlerQueue: DispatchQueue(label: "com.sanevideo.mic-audio")
            )
            
            // 5. Setup SCRecordingOutput if an output URL was provided
            if let outputURL = currentOutputURL {
                let recordingConfig = SCRecordingOutputConfiguration()
                recordingConfig.outputURL = outputURL
                recordingConfig.outputFileType = .mp4
                // Use H.264 for compatibility, or HEVC for better compression
                recordingConfig.videoCodecType = .h264
                
                let output = SCRecordingOutput(configuration: recordingConfig, delegate: self)
                try newStream.addRecordingOutput(output)
                self.recordingOutput = output
                AppLogger.recording.info("🎥 Configured SCRecordingOutput for direct file recording")
            }
            
            // Start capture
            try await newStream.startCapture()
            
            // Store active stream
            activeStream = newStream
            
            AppLogger.recording.info("✅ Screen capture started successfully")
            
        } catch {
            AppLogger.recording.error("❌ Failed to start screen capture: \(error.localizedDescription)")
            // Error will propagate through the recording engine's error handler
        }
    }
}

// MARK: - SCRecordingOutputDelegate

extension ScreenRecorder: SCRecordingOutputDelegate {
    nonisolated func recordingOutputDidStartRecording(_ recordingOutput: SCRecordingOutput) {
        AppLogger.recording.info("🎥 SCRecordingOutput started recording")
    }
    
    nonisolated func recordingOutputDidFinishRecording(_ recordingOutput: SCRecordingOutput) {
        AppLogger.recording.info("🎥 SCRecordingOutput finished recording")
    }
    
    nonisolated func recordingOutput(_ recordingOutput: SCRecordingOutput, didFailWithError error: Error) {
        AppLogger.recording.error("🎥 SCRecordingOutput failed: \(error.localizedDescription)")
    }
}

// MARK: - SCStreamOutput

extension ScreenRecorder: SCStreamOutput {
    nonisolated func stream(
        _ stream: SCStream,
        didOutputSampleBuffer sampleBuffer: CMSampleBuffer,
        of type: SCStreamOutputType
    ) {
        switch type {
        case .screen:
            sampleBufferSubject.send(sampleBuffer)
            
        case .audio:
            // Log audio format once for debugging
            if !loggedScreenAudioFormat,
               let format = CMSampleBufferGetFormatDescription(sampleBuffer),
               let asbdPointer = CMAudioFormatDescriptionGetStreamBasicDescription(format)?.pointee {
                AppLogger.recording.info("Screen audio format sampleRate=\(asbdPointer.mSampleRate), channels=\(asbdPointer.mChannelsPerFrame), formatID=\(asbdPointer.mFormatID)")
                loggedScreenAudioFormat = true
            }
            audioSampleBufferSubject.send(sampleBuffer)
            
        case .microphone:
            // Send mic samples for real-time analysis
            // Note: RecordingEngine will now receive these via this subject
            // instead of its own AudioService subscription when in screen mode
            micSampleBufferSubject.send(sampleBuffer)
            
        @unknown default:
            break
        }
    }
}

// MARK: - SCStreamDelegate (Error Handling)

extension ScreenRecorder {
    /// Called when the stream encounters an error (display unplugged, permission revoked, etc.)
    nonisolated func stream(_ stream: SCStream, didStopWithError error: any Error) {
        Task { @MainActor in
            AppLogger.recording.error("Screen stream stopped with error: \(error.localizedDescription)")
            
            // Notify listener if this was not an intentional stop
            if !self.isStopping {
                self.onStop?(error)
            }
            
            // Clean up the stream
            self.activeStream = nil
            
            // Deactivate picker
            let picker = SCContentSharingPicker.shared
            picker.isActive = false
            picker.remove(self)
            
            // Note: RecordingEngine will detect the stream stopped via sample buffer interruption
            // and will handle the error appropriately
        }
    }
    
    /// Called when the system's Presenter Overlay (video effect) is activated
    nonisolated func outputVideoEffectDidStartForStream(_ stream: SCStream) {
        Task { @MainActor in
            AppLogger.recording.info("🎥 Presenter Overlay STARTED. Hiding App PiP.")
            self.onPresenterOverlayChanged?(true)
        }
    }
    
    /// Called when the system's Presenter Overlay (video effect) is deactivated
    nonisolated func outputVideoEffectDidStopForStream(_ stream: SCStream) {
        Task { @MainActor in
            AppLogger.recording.info("🎥 Presenter Overlay STOPPED. Restoring App PiP.")
            self.onPresenterOverlayChanged?(false)
        }
    }
}
