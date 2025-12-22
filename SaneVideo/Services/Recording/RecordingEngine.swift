//
//  RecordingEngine.swift
//  SaneVideo
//
//  Created by SaneVideo Refactor
//

import AppKit
import AVFoundation
import Combine
import CoreMedia
import OSLog
import ScreenCaptureKit

@MainActor
class RecordingEngine: NSObject, @unchecked Sendable {
    // Error handler callback - will be called on Main Queue
    var onError: ((AppError) -> Void)?
    
    // Callback to notify AppState about system overlay changes
    @MainActor var onPresenterOverlayChanged: ((Bool) -> Void)?
    
    // Callback to notify when screen recording is stopped externally (e.g. via system menu)
    @MainActor var onScreenRecordingStoppedExternally: (() -> Void)?

    // Audio Level Publisher (Forwarded from AudioService)
    var audioLevelSubject: PassthroughSubject<Float, Never> {
        audioService.audioLevelSubject
    }

    // Helpers
    // Services
    let cameraService: CameraServiceProtocol
    @RecordingActor var videoWriter: VideoWriter?
    let screenRecorder: ScreenRecorder
    let audioService: AudioService
    let soundAnalysisService: SoundAnalysisService

    // Thread Safety: Global RecordingActor handle all serialization
    // This replaces the old manual processingQueue

    // State (Isolated to RecordingActor)
    @RecordingActor var isRecording = false
    @RecordingActor var isPaused = false
    @RecordingActor var isStopping = false // Flag to prevent rapid restart during concatenation
    @RecordingActor var currentSource: RecordingSource = .camera
    @RecordingActor var isSwitching = false // Prevention of overlapping switches
    @RecordingActor var isMicMuted = false // Mic muting state
    @RecordingActor var outputURL: URL?
    let diskSpaceMonitor = DiskSpaceMonitor()
    
    // Components
    @RecordingActor let timeCoordinator = RecordingTimeCoordinator()

    // CRITICAL FIX: Track source switch to detect if new source fails silently
    @RecordingActor var sourceSwitchTimeoutTask: Task<Void, Never>?

    // Subscriptions
    var cancellables = Set<AnyCancellable>()
    
    // Task Lifecycle Management (for cancellation on deinit)
    @RecordingActor var activeRecordingTask: Task<Void, Never>?
    @RecordingActor var activeSwitchTask: Task<Void, Never>?
    
    // Preview layer for Screen Recording
    let screenPreviewLayer = AVSampleBufferDisplayLayer()

    override init() {
        let container = ServiceContainer.shared
        cameraService = container.cameraService
        audioService = container.audioService
        soundAnalysisService = container.soundAnalysisService
        screenRecorder = ScreenRecorder()
        
        super.init()
        screenPreviewLayer.videoGravity = .resizeAspectFill
        
        setupSubscriptions()
        setupDiskMonitor()
        setupSleepObservers()
        setupInterruptionObservers()
    }

    // For testing
    init(cameraService: CameraServiceProtocol, 
         audioService: AudioService? = nil,
         soundAnalysisService: SoundAnalysisService? = nil,
         screenRecorder: ScreenRecorder? = nil) {
        let container = ServiceContainer.shared
        self.cameraService = cameraService
        self.audioService = audioService ?? container.audioService
        self.soundAnalysisService = soundAnalysisService ?? container.soundAnalysisService
        self.screenRecorder = screenRecorder ?? ScreenRecorder()
        
        super.init()
        screenPreviewLayer.videoGravity = .resizeAspectFill
        
        setupSubscriptions()
        setupDiskMonitor()
        setupSleepObservers()
        setupInterruptionObservers()
    }

    // MARK: - Internal Setup

    @MainActor
    private func setupDiskMonitor() {
        diskSpaceMonitor.onLowDiskSpace = { [weak self] error in
            guard let self = self else { return }

            Task {
                AppLogger.recording.error("Low disk space - stopping recording: \(error)")
                _ = await self.stopRecording()
                
                await MainActor.run {
                    self.onError?(error as? AppError ?? AppError.recordingEngineError(error.localizedDescription))
                }
            }
        }
    }

    @MainActor
    func verifyDiskSpace() throws {
        try diskSpaceMonitor.verifyDiskSpace()
    }

    private func setupSleepObservers() {
        let center = NSWorkspace.shared.notificationCenter
        center.addObserver(self, selector: #selector(handleSleep), name: NSWorkspace.willSleepNotification, object: nil)
        center.addObserver(self, selector: #selector(handleWake), name: NSWorkspace.didWakeNotification, object: nil)
    }
    
    private func setupInterruptionObservers() {
        let center = NotificationCenter.default
        
        // Capture Session Interruptions (Camera/Mic hardware issues)
        center.addObserver(self, selector: #selector(handleSessionWasInterrupted), name: AVCaptureSession.wasInterruptedNotification, object: nil)
        center.addObserver(self, selector: #selector(handleSessionInterruptionEnded), name: AVCaptureSession.interruptionEndedNotification, object: nil)
        center.addObserver(self, selector: #selector(handleSessionRuntimeError), name: AVCaptureSession.runtimeErrorNotification, object: nil)
        
        // Audio Engine Changes (Device unplugged/switched)
        center.addObserver(self, selector: #selector(handleAudioConfigurationChange), name: .AVAudioEngineConfigurationChange, object: nil)
    }

    @objc private func handleSleep() {
        Task { @RecordingActor in
            if isRecording, !isPaused {
                pauseRecording()
            }
        }
    }

    @objc private func handleWake() {
        // Optional: Notify user that recording was paused
    }
    
    // MARK: - Interruption Handlers
    
    @objc private func handleSessionWasInterrupted(notification: Notification) {
        Task { @RecordingActor in
            guard isRecording, !isPaused else { return }
            
            AppLogger.recording.warning("⚠️ Recording Interrupted. Pausing...")
            pauseRecording()
            
            await MainActor.run {
                ServiceContainer.shared.toastManager.show("Recording Paused: Camera Interrupted", type: .error)
            }
        }
    }

    @objc private func handleSessionInterruptionEnded(notification: Notification) {
        AppLogger.recording.info("✅ Recording Interruption Ended. Ready to resume.")
    }

    @objc private func handleSessionRuntimeError(notification: Notification) {
        guard let error = notification.userInfo?[AVCaptureSessionErrorKey] as? Error else { return }
        
        Task { @RecordingActor in
            guard isRecording else { return }
            AppLogger.recording.error("❌ Recording Runtime Error: \(error.localizedDescription)")
            
            // Try to stop safely to save what we have
            _ = await stopRecording()
            
            await MainActor.run {
               ServiceContainer.shared.errorPresenter.present(AppError.recordingEngineError("Camera Error: \(error.localizedDescription)"))
            }
        }
    }

    @objc private func handleAudioConfigurationChange(notification: Notification) {
        Task { @RecordingActor in
             guard isRecording, !isPaused else { return }
             AppLogger.recording.warning("⚠️ Audio Configuration Changed (e.g. Device Unplugged). Pausing...")
             
             pauseRecording()
             
             await MainActor.run {
                 ServiceContainer.shared.toastManager.show("Recording Paused: Check Audio Device", type: .error)
             }
        }
    }

    // MARK: - Public Interface

    @RecordingActor
    func startRecording(initialSource: RecordingSource) async {
        guard !isRecording, !isStopping else {
            AppLogger.recording.warning("Cannot start recording: already recording or stopping")
            return
        }

        // isTesting is now a class-level property
        if TestEnvironment.isUITesting {
            AppLogger.recording.info("🛠️ [UI TEST] Bypassing real recording engine")
            let tempDir = FileManager.default.temporaryDirectory
            let filename = "MockRecording_\(Date().timeIntervalSince1970).mp4"
            self.outputURL = tempDir.appendingPathComponent(filename)
            
            isRecording = true
            isPaused = false
            currentSource = initialSource
            timeCoordinator.reset()
            return
        }

        let filename = "Recording_\(Date().timeIntervalSince1970).mp4"
        guard let moviesDir = FileManager.default.urls(for: .moviesDirectory, in: .userDomainMask).first else {
            AppLogger.recording.error("Cannot find Movies directory")
            await MainActor.run { self.onError?(AppError.recordingEngineError("Cannot find Movies directory")) }
            return
        }
        let outputDir = moviesDir.appendingPathComponent("SaneVideo/Recordings")
        let url = outputDir.appendingPathComponent(filename)
        self.outputURL = url

        do {
            try FileManager.default.createDirectory(at: outputDir, withIntermediateDirectories: true)
        } catch {
            AppLogger.recording.error("Failed to create output directory: \(error)")
            await MainActor.run { self.onError?(AppError.recordingEngineError("Cannot create recording directory")) }
            return
        }

        // Use RenderingService shared instance
        let renderingService = RenderingService.shared
        self.videoWriter = VideoWriter(renderingService: renderingService)
        do {
            try self.videoWriter?.start(outputURL: url)
        } catch {
            AppLogger.recording.error("Failed to start video writer: \(error)")
            await MainActor.run { self.onError?(AppError.recordingEngineError("Failed to start recording")) }
            return
        }
        isRecording = true
        isPaused = false
        currentSource = initialSource
        timeCoordinator.reset()
        
        await MainActor.run { self.diskSpaceMonitor.start() }

        if initialSource == .camera {
            do {
                try await cameraService.start()
            } catch {
                await MainActor.run { self.onError?(.cameraSetupFailed(error)) }
                return
            }
        } else {
            do { 
                try await self.screenRecorder.start() 
            } catch {
                await MainActor.run { 
                    self.onError?(.screenCaptureUnavailable)
                }
                return
            }
        }

        await MainActor.run { self.audioService.start() }
        
        // Start Real-time Sound Analysis
        let format = AVAudioFormat(standardFormatWithSampleRate: 44100, channels: 1)!
        soundAnalysisService.startRealTimeAnalysis(format: format)
        await MainActor.run {
            self.setupSoundAnalysisMonitoring()
        }

        if initialSource == .screen {
            let cursorService = await ServiceContainer.shared.cursorTrackingService
            await cursorService.startTracking()
        }

        AppLogger.recording.info("Started recording (Source: \(initialSource == .camera ? "camera" : "screen"))")
    }
    @RecordingActor
    @discardableResult
    func stopRecording() async -> URL? {
        AppLogger.recording.info("🛑 Engine: stopRecording called. State: isRecording=\(self.isRecording), isStopping=\(self.isStopping)")
        
        guard isRecording, !isStopping else { 
            AppLogger.recording.warning("🛑 Engine: stopRecording ignored (guard failed). isRecording=\(isRecording), isStopping=\(isStopping)")
            return nil 
        }

        isRecording = false
        isStopping = true
        isPaused = false
        
        await MainActor.run { 
            diskSpaceMonitor.stop() 
        }

        if TestEnvironment.isUITesting {
            AppLogger.recording.info("🛠️ [UI TEST] Generating programmatic mock file")
            
            // Use Temporary Directory to avoid Sandbox/TCC issues
            let tempDir = FileManager.default.temporaryDirectory
            let mockURL = tempDir.appendingPathComponent("MockRecording_\(Date().timeIntervalSince1970).mp4")
            
            await generateMockVideo(to: mockURL)
            
            isStopping = false
            
            // Clean up state
            self.videoWriter = nil
            self.outputURL = nil
            timeCoordinator.reset()
            
            return mockURL
        }

        activeSwitchTask?.cancel()
        activeSwitchTask = nil

        // Finalize components
        await screenRecorder.stop()
        soundAnalysisService.stopRealTimeAnalysis()

        let finalURL = await videoWriter?.finish()
        
        if let url = finalURL {
            let cursorService = await ServiceContainer.shared.cursorTrackingService
            _ = try? await cursorService.stopTrackingAndSave(to: url)
        }

        // Cleanup
        videoWriter = nil
        outputURL = nil
        timeCoordinator.reset()
        sourceSwitchTimeoutTask?.cancel()
        sourceSwitchTimeoutTask = nil
        isStopping = false

        AppLogger.recording.info("Recording stopped. File: \(finalURL?.lastPathComponent ?? "nil")")
        return finalURL
    }

    @RecordingActor
    func pauseRecording() {
        guard isRecording, !isPaused else { return }
        isPaused = true
        timeCoordinator.pause()
        AppLogger.recording.info("Paused recording")
    }

    @RecordingActor
    func resumeRecording() {
        guard isRecording, isPaused else { return }
        isPaused = false
        timeCoordinator.resume()
        AppLogger.recording.info("Resumed recording")
    }

    func pause() { Task { @RecordingActor in pauseRecording() } }
    func resume() { Task { @RecordingActor in resumeRecording() } }

    // MARK: - Monitoring

    deinit {
        // Cancel any active tasks
        activeRecordingTask?.cancel()
        activeSwitchTask?.cancel()
        sourceSwitchTimeoutTask?.cancel()
        
        NotificationCenter.default.removeObserver(self)
        NSWorkspace.shared.notificationCenter.removeObserver(self)
    }
    
    // MARK: - UI Test Helpers
    
    private func generateMockVideo(to url: URL) async {
        print("🎥 [UI TEST] Generating mock video at: \(url.path)")
        
        // Delete existing if any
        try? FileManager.default.removeItem(at: url)
        
        guard let writer = try? AVAssetWriter(outputURL: url, fileType: .mp4) else {
            print("❌ [UI TEST] Failed to create asset writer (Result: nil)")
            return
        }
        
        let settings: [String: Any] = [
            AVVideoCodecKey: AVVideoCodecType.h264,
            AVVideoWidthKey: 1280,
            AVVideoHeightKey: 720
        ]
        
        let input = AVAssetWriterInput(mediaType: .video, outputSettings: settings)
        input.expectsMediaDataInRealTime = false
        
        guard writer.canAdd(input) else {
            print("❌ [UI TEST] Cannot add input to writer")
            return
        }
        writer.add(input)
        
        guard writer.startWriting() else {
            print("❌ [UI TEST] Writer failed to start: \(writer.error?.localizedDescription ?? "unknown")")
            return
        }
        
        writer.startSession(atSourceTime: .zero)
        
        let adaptor = AVAssetWriterInputPixelBufferAdaptor(assetWriterInput: input, sourcePixelBufferAttributes: nil)
        
        // Wait for input
        while !input.isReadyForMoreMediaData {
            try? await Task.sleep(nanoseconds: 10 * 1_000_000)
        }
        
        if let buffer = createMockPixelBuffer() {
            adaptor.append(buffer, withPresentationTime: .zero)
            let frameTime = CMTime(value: 1, timescale: 30) // 1 frame
            
            // Wait for ready
            while !input.isReadyForMoreMediaData { try? await Task.sleep(nanoseconds: 1_000_000) }
            adaptor.append(buffer, withPresentationTime: frameTime)
            
            let endTime = CMTime(value: 30, timescale: 30) // 1 second
            while !input.isReadyForMoreMediaData { try? await Task.sleep(nanoseconds: 1_000_000) }
            adaptor.append(buffer, withPresentationTime: endTime)
            
            print("✅ [UI TEST] Appended frames")
        } else {
             print("❌ [UI TEST] Failed to create pixel buffer")
        }
        
        input.markAsFinished()
        await writer.finishWriting()
        
        if writer.status == .completed {
             print("✅ [UI TEST] AssetWriter COMPLETED successfully")
        } else {
             print("❌ [UI TEST] AssetWriter FAILED status: \(writer.status.rawValue) error: \(writer.error?.localizedDescription ?? "nil")")
        }
    }
    
    private func createMockPixelBuffer() -> CVPixelBuffer? {
        var pixelBuffer: CVPixelBuffer?
        let attrs = [kCVPixelBufferCGImageCompatibilityKey: kCFBooleanTrue,
                     kCVPixelBufferCGBitmapContextCompatibilityKey: kCFBooleanTrue] as CFDictionary
        
        let status = CVPixelBufferCreate(kCFAllocatorDefault, 1280, 720, kCVPixelFormatType_32ARGB, attrs, &pixelBuffer)
        guard status == kCVReturnSuccess else { return nil }
        return pixelBuffer
    }
}
