//
//  CameraManager.swift
//  SaneVideo
//
//  Created by SaneVideo Refactor
//

import AppKit
@preconcurrency import AVFoundation
import Combine
import OSLog

@MainActor
@Observable
final class CameraManager: NSObject, CameraServiceProtocol {

    // MARK: - State Properties

    private(set) var isActive = false {
        didSet { _isActiveSubject.send(isActive) }
    }
    var hasVideoSignal = false
    var permissionGranted = false
    var lastError: AppError?
    var session: AVCaptureSession? {
        didSet { _sessionSubject.send(session) }
    }
    var currentCameraID: String?

    private var _isSettingUpSession = false
    private var _isStoppingSession = false

    private let framePublisher = CameraFramePublisher()
    private var cancellables = Set<AnyCancellable>()

    // MARK: - Protocol Implementation

    private let _isActiveSubject = CurrentValueSubject<Bool, Never>(false)
    private let _sessionSubject = CurrentValueSubject<AVCaptureSession?, Never>(nil)

    var isActivePublisher: AnyPublisher<Bool, Never> { _isActiveSubject.eraseToAnyPublisher() }
    var sessionPublisher: AnyPublisher<AVCaptureSession?, Never> { _sessionSubject.eraseToAnyPublisher() }

    // MARK: - Camera Switching

    func switchCamera(to device: AVCaptureDevice) {
        let deviceID = device.uniqueID
        let deviceName = device.localizedName
        
        Task.detached(priority: .userInitiated) { [weak self] in
            guard let self, let session = await self.session else { return }

            session.beginConfiguration()

            // Remove current video input
            for input in session.inputs {
                if let deviceInput = input as? AVCaptureDeviceInput,
                   deviceInput.device.hasMediaType(.video) {
                    session.removeInput(deviceInput)
                }
            }

            // Add new input
            do {
                let newInput = try AVCaptureDeviceInput(device: device)
                if session.canAddInput(newInput) {
                    session.addInput(newInput)
                    await MainActor.run {
                        self.currentCameraID = deviceID
                        // Customer Service: Remember their choice
                        UserDefaults.standard.set(deviceID, forKey: "lastUsedCameraID")
                    }
                    AppLogger.camera.info("Switched to camera: \(deviceName)")
                }
            } catch {
                AppLogger.camera.error("Failed to switch camera: \(error)")
                await MainActor.run {
                    self.lastError = .cameraSetupFailed(error)
                }
            }

            session.commitConfiguration()
        }
    }

    // MARK: - Frame Publisher

    // CRITICAL: Must be nonisolated to allow access from RecordingEngine's processingQueue.
    // PassthroughSubject is thread-safe internally.
    nonisolated var sampleBufferSubject: PassthroughSubject<CMSampleBuffer, Never> {
        framePublisher.sampleBufferSubject
    }

    // MARK: - Initialization

    override init() {
        super.init()
        Task { @MainActor in
            setupBindings()
        }
    }

    @MainActor
    private func setupBindings() {
        // Bind permission status
        ServiceContainer.shared.permissionManager.cameraStatusPublisher
            .receive(on: DispatchQueue.main)
            .map { $0 == .granted }
            .sink { [weak self] granted in
                self?.permissionGranted = granted
            }
            .store(in: &cancellables)

        // Bind signal detection
        framePublisher.onSignalReceived = { [weak self] in
            Task { @MainActor [weak self] in
                self?.hasVideoSignal = true
                AppLogger.camera.debug("Signal received")
            }
        }
    }

    // MARK: - Public API

    func start() async throws {
        // 1. Skip in tests to prevent TCC crash
        if TestEnvironment.isUITesting {
            AppLogger.camera.info("🧪 CameraManager: Skipping start (Test Environment detected)")
            self.isActive = true
            return
        }

        // 2. Check permission
        let isAuthorized = ServiceContainer.shared.permissionManager.cameraStatus == .granted
        
        guard isAuthorized else {
            AppLogger.camera.warning("Camera permission not granted, requesting...")
            let granted = await ServiceContainer.shared.permissionManager.requestCameraPermission()
            if granted {
                AppLogger.camera.info("Permission granted, starting session...")
                try await self.start()
            } else {
                AppLogger.camera.error("Camera permission denied.")
                self.lastError = .cameraPermissionDenied
                throw AppError.cameraPermissionDenied
            }
            return
        }
        
        // 3. Proceed with session start
        try await self.internalStart()
    }

    private func internalStart() async throws {
        // Guard against starting while stopping
        guard !_isStoppingSession else {
            AppLogger.camera.warning("Camera is stopping, deferring start request")
            try await Task.sleep(nanoseconds: 300_000_000)
            try await self.internalStart()
            return
        }

        if let existingSession = session {
            try await startSessionInternal(existingSession)
            return
        }

        if _isSettingUpSession {
            AppLogger.camera.warning("Session setup already in progress. Ignoring start request.")
            return
        }

        _isSettingUpSession = true
        let newSession = await setupSession()
        _isSettingUpSession = false
        
        guard let session = newSession else {
            AppLogger.camera.error("Failed to start: Session is nil after setup attempt")
            self.lastError = .noCameraFound
            throw AppError.noCameraFound
        }
        
        try await self.startSessionInternal(session)
    }

    private func startSessionInternal(_ session: AVCaptureSession) async throws {
        if !session.isRunning {
            AppLogger.camera.info("Attempting to start capture session...")
            
            // Move startRunning to background to avoid blocking MainActor
            await Task.detached(priority: .userInitiated) {
                session.startRunning()
            }.value
            
            AppLogger.camera.info("Session .startRunning() returned. isRunning: \(session.isRunning)")

            // Verify it actually started with retry logic
            try await Task.sleep(nanoseconds: 300_000_000)
            
            if !session.isRunning {
                AppLogger.camera.warning("⚠️ Camera session not running, retrying...")
                await Task.detached(priority: .userInitiated) {
                    session.startRunning()
                }.value
                
                try await Task.sleep(nanoseconds: 300_000_000)
                
                if !session.isRunning {
                    AppLogger.camera.error("❌ Camera session FAILED after retry")
                    let error = NSError(domain: "SaneVideo", code: -1, userInfo: [NSLocalizedDescriptionKey: "Camera session failed to start"])
                    self.lastError = .cameraSetupFailed(error)
                    throw AppError.cameraSetupFailed(error)
                } else {
                    AppLogger.camera.info("✅ Camera session started on retry")
                }
            } else {
                AppLogger.camera.info("✅ Camera session IS running")
            }
        } else {
            AppLogger.camera.info("Session already running")
        }

        self.isActive = true
        AppLogger.camera.info("CameraManager set to active")
    }
    func stop() {
        isActive = false
        hasVideoSignal = false
        framePublisher.resetSignalStatus()

        guard let session = session else { return }

        Task {
            _isStoppingSession = true
            defer { _isStoppingSession = false }

            if session.isRunning {
                await Task.detached(priority: .userInitiated) {
                    session.stopRunning()
                }.value
                AppLogger.camera.info("Session stopped")
            }
        }
    }

    func toggle() {
        Task {
            if isActive {
                stop()
            } else {
                try? await start()
            }
        }
    }

    // NEW: Recovery API for Watchdog
    func restartSession() {
        AppLogger.camera.warning("Forcing session restart due to watchdog trigger")
        stop()

        // Wait longer to ensure full teardown completes before restart
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) { [weak self] in
            AppLogger.camera.info("Starting camera after restart delay")
            Task { try? await self?.start() }
        }
    }

    func requestPermissionAgain() {
        Task { @MainActor in
            ServiceContainer.shared.permissionManager.checkCameraPermission()
        }
    }

    // MARK: - Session Management

    nonisolated private func setupSession() async -> AVCaptureSession? {
        AppLogger.camera.info("Setting up capture session...")
        let session = AVCaptureSession()
        session.beginConfiguration()

        // 0. Stabilization Delay (Workaround for CMIO racing on Tahoe)
        // Helps avoid "Connection invalid" errors during rapid startup.
        try? await Task.sleep(nanoseconds: 200_000_000) // 0.2s

        // 1. Discovery - Include Continuity Camera (iPhone as webcam)
        // Modernized with macOS 15 device types
        var deviceTypes: [AVCaptureDevice.DeviceType] = [.builtInWideAngleCamera, .external, .continuityCamera]
        if #available(macOS 15.0, *) {
            deviceTypes.append(.deskViewCamera)
        }
        
        let discoverySession = AVCaptureDevice.DiscoverySession(
            deviceTypes: deviceTypes,
            mediaType: .video,
            position: .unspecified
        )
        
        // Log discovered cameras sparingly
        let devices = discoverySession.devices
        AppLogger.camera.info("Found \(devices.count) camera devices")

        for device in devices {
            let deviceTypeStr: String
            switch device.deviceType {
            case .continuityCamera:
                deviceTypeStr = "Continuity Camera (iPhone)"
            case .builtInWideAngleCamera:
                deviceTypeStr = "Built-in"
            case .external:
                deviceTypeStr = "External"
            default:
                deviceTypeStr = "Unknown"
            }
            AppLogger.camera.info("Discovered camera: \(device.localizedName) [\(deviceTypeStr)]")
        }
        
        guard let camera = discoverySession.devices.first else {
            AppLogger.camera.error("❌ NO CAMERA DEVICES FOUND! Discovery session was empty.")
            Task { @MainActor in
                self.lastError = .noCameraFound
            }
            return nil
        }

        // 2. Video Input (Add BEFORE format selection)
        AppLogger.camera.info("Selected camera: \(camera.localizedName)")
        do {
            let input = try AVCaptureDeviceInput(device: camera)
            if session.canAddInput(input) {
                session.addInput(input)
                Task { @MainActor [weak self] in
                    self?.currentCameraID = camera.uniqueID
                }
            } else {
                AppLogger.camera.error("Failed to add video input to session")
                Task { @MainActor [weak self] in
                    self?.lastError = .cameraSetupFailed(NSError(domain: "SaneVideo", code: -1, userInfo: [NSLocalizedDescriptionKey: "Failed to add video input to session"]))
                }
            }
        } catch {
            AppLogger.camera.error("Failed to setup video input: \(error)")
            Task { @MainActor [weak self] in
                self?.lastError = .cameraSetupFailed(error)
            }
        }

        // 3. Format Selection & Conflict Mitigation
        // Workaround for Portrait Effects crash on macOS 26.
        var bestSafeFormat: AVCaptureDevice.Format?
        
        let safeFormats = camera.formats.filter { format in
            if #available(macOS 12.0, *) {
                return !format.isPortraitEffectSupported
            }
            return true
        }
        
        let sortedSafeFormats = safeFormats.sorted { (f1, f2) -> Bool in
            let dim1 = CMVideoFormatDescriptionGetDimensions(f1.formatDescription)
            let dim2 = CMVideoFormatDescriptionGetDimensions(f2.formatDescription)
            let res1 = Int(dim1.width) * Int(dim1.height)
            let res2 = Int(dim2.width) * Int(dim2.height)
            
            if res1 != res2 { return res1 > res2 }
            
            let maxFps1 = f1.videoSupportedFrameRateRanges.map { $0.maxFrameRate }.max() ?? 0
            let maxFps2 = f2.videoSupportedFrameRateRanges.map { $0.maxFrameRate }.max() ?? 0
            return maxFps1 > maxFps2
        }
        
        bestSafeFormat = sortedSafeFormats.first
        
        do {
            try camera.lockForConfiguration()
            if let safeFormat = bestSafeFormat {
                camera.activeFormat = safeFormat
                let dims = CMVideoFormatDescriptionGetDimensions(safeFormat.formatDescription)
                AppLogger.camera.info("✅ Selected SAFE format: \(dims.width)x\(dims.height) (No Portrait Support)")
            } else {
                AppLogger.camera.warning("⚠️ No specific 'safe' format found. Falling back to standard presets.")
                if session.canSetSessionPreset(.hd1920x1080) {
                    session.sessionPreset = .hd1920x1080
                } else {
                    session.sessionPreset = .high
                }
            }
            
            // Note: macOS HDR camera support is handled automatically via format selection
            // (10-bit YUV formats when available). The activeFormat already provides 
            // the highest quality available from the selected camera.
            
            camera.unlockForConfiguration()
        } catch {
            AppLogger.camera.error("Failed to lock device for configuration: \(error)")
            Task { @MainActor in
                self.lastError = .cameraSetupFailed(error)
            }
        }

        // 4. Video Output
        let videoOutput = AVCaptureVideoDataOutput()
        videoOutput.videoSettings = [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA
        ]
        videoOutput.setSampleBufferDelegate(framePublisher, queue: .global(qos: .userInteractive))

        if session.canAddOutput(videoOutput) {
            session.addOutput(videoOutput)
            
            // Stabilization is handled by system or specific formats on macOS
        }

        session.commitConfiguration()

        // Crash fix: Ensure session is assigned on main actor for SwiftUI compatibility.
        // Also sync triggers the publisher
        Task { @MainActor in
            self.session = session
        }

        return session
    }
}
