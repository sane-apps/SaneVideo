//
//  CameraState.swift
//  SaneVideo
//
//  Created by SaneVideo Refactor
//

import AVFoundation
import Combine
import Foundation
import SwiftUI

private final class CameraStartAttempt: @unchecked Sendable {
    private let lock = NSLock()
    private var completed = false
    private var timedOut = false

    func completeStart() -> Bool {
        lock.lock()
        defer { lock.unlock() }
        guard !completed else { return false }
        completed = true
        return true
    }

    func completeTimeout() -> Bool {
        lock.lock()
        defer { lock.unlock() }
        guard !completed else { return false }
        completed = true
        timedOut = true
        return true
    }

    var didTimeOut: Bool {
        lock.lock()
        defer { lock.unlock() }
        return timedOut
    }
}

@MainActor
@Observable
class CameraState {
    // MARK: - Published Properties

    var isActive = false
    var currentCameraID: String?
    var availableCameras: [AVCaptureDevice] = []
    private var currentSession: AVCaptureSession?
    private var currentHasVideoSignal = false
    private var currentLastError: AppError?

    // MARK: - Computed Properties

    var session: AVCaptureSession? { currentSession }
    var hasVideoSignal: Bool { currentHasVideoSignal }
    var lastError: AppError? { currentLastError }
    var shouldShowCameraSurface: Bool { isActive || session != nil }
    var shouldShowLivePreview: Bool { session != nil && (isActive || hasVideoSignal) }
    var audioLevelPublisher: AnyPublisher<Float, Never> { audioService.audioLevelSubject.eraseToAnyPublisher() }

    // MARK: - Internal Properties

    private let cameraService: CameraServiceProtocol
    private let audioService: AudioService
    private let startTimeoutNanoseconds: UInt64
    private let usePermissionlessTestFastPath: Bool
    private let cameraAuthorizationStatus: @Sendable () -> AVAuthorizationStatus
    private var cancellables = Set<AnyCancellable>()
    private var hasDiscoveredCameras = false

    // MARK: - Initialization

    init(
        cameraService: CameraServiceProtocol? = nil,
        audioService: AudioService? = nil,
        startTimeoutNanoseconds: UInt64 = 5_000_000_000,
        usePermissionlessTestFastPath: Bool = true,
        cameraAuthorizationStatus: @escaping @Sendable () -> AVAuthorizationStatus = {
            AVCaptureDevice.authorizationStatus(for: .video)
        }
    ) {
        self.cameraService = cameraService ?? ServiceContainer.shared.cameraService
        self.audioService = audioService ?? ServiceContainer.shared.audioService
        self.startTimeoutNanoseconds = startTimeoutNanoseconds
        self.usePermissionlessTestFastPath = usePermissionlessTestFastPath
        self.cameraAuthorizationStatus = cameraAuthorizationStatus
        self.isActive = self.cameraService.isActive
        self.currentSession = self.cameraService.session
        self.currentHasVideoSignal = self.cameraService.hasVideoSignal
        self.currentLastError = self.cameraService.lastError
        setupObserver()
        // NOTE: Camera discovery is deferred until refreshCameras() is called
        // This prevents CMIO daemon activation on app launch
    }

    /// Refresh the list of available cameras (call when user interacts with camera picker)
    func refreshCameras() {
        if TestEnvironment.suppressPermissionPrompts && !TestEnvironment.allowsHardwareIntegration {
            availableCameras = [] // Mock empty cameras during test to avoid CMIO activation
            hasDiscoveredCameras = true
            return
        }

        // Only query DiscoverySession when explicitly requested
        let discoverySession = AVCaptureDevice.DiscoverySession(
            deviceTypes: [.builtInWideAngleCamera, .external],
            mediaType: .video,
            position: .unspecified
        )
        availableCameras = discoverySession.devices
        hasDiscoveredCameras = true
        AppLogger.camera.debug("Refreshed camera list: \(self.availableCameras.count) devices found")
    }

    /// Ensure cameras are discovered (lazy initialization)
    func ensureCamerasDiscovered() {
        if !hasDiscoveredCameras {
            refreshCameras()
        }
    }

    private func setupObserver() {
        // Crash fix: Ensure all subscriptions receive on main queue for @MainActor isolation
        cameraService.isActivePublisher
            .receive(on: DispatchQueue.main)
            .sink { [weak self] active in
                self?.isActive = active
            }
            .store(in: &cancellables)

        cameraService.hasVideoSignalPublisher
            .receive(on: DispatchQueue.main)
            .sink { [weak self] hasSignal in
                self?.currentHasVideoSignal = hasSignal
            }
            .store(in: &cancellables)

        cameraService.lastErrorPublisher
            .receive(on: DispatchQueue.main)
            .sink { [weak self] error in
                self?.currentLastError = error
            }
            .store(in: &cancellables)

        // Crash fix: Ensure session updates are received on main queue for @MainActor isolation
        cameraService.sessionPublisher
            .receive(on: DispatchQueue.main)
            .sink { [weak self] session in
                self?.currentSession = session
                self?.currentHasVideoSignal = self?.cameraService.hasVideoSignal ?? false
            }
            .store(in: &cancellables)
    }

    // MARK: - Actions

    func toggleCamera() {
        if usePermissionlessTestFastPath && TestEnvironment.suppressPermissionPrompts && !TestEnvironment.allowsHardwareIntegration {
            isActive.toggle()
            return
        }
        cameraService.toggle()
        AppLogger.camera.info("Toggled camera (Active: \(cameraService.isActive))")
    }

    func startCamera(completion: @escaping @Sendable (Bool) -> Void = { _ in }) {
        if usePermissionlessTestFastPath && TestEnvironment.suppressPermissionPrompts && !TestEnvironment.allowsHardwareIntegration {
            isActive = true
            completion(true)
            return
        }

        // Ensure cameras are discovered when starting (in case user never opened picker)
        ensureCamerasDiscovered()
        
        if !cameraService.isActive {
            let attempt = CameraStartAttempt()
            let shouldApplyStartTimeout = cameraAuthorizationStatus() == .authorized
            let timeoutNanoseconds = startTimeoutNanoseconds

            let startTask = Task { @MainActor [weak self, attempt] in
                guard let self else { return }
                do {
                    try await cameraService.start()

                    if attempt.completeStart() {
                        let didStart = cameraService.isActive
                        if didStart {
                            currentLastError = nil
                            AppLogger.camera.info("Started camera")
                        } else if currentLastError == nil {
                            currentLastError = cameraService.lastError ?? .cameraUnavailable
                            AppLogger.camera.error("Camera start returned without an active session")
                        }
                        completion(didStart)
                    } else if attempt.didTimeOut {
                        cameraService.stop()
                    }
                } catch {
                    if attempt.completeStart() {
                        let appError = Self.normalizedCameraStartError(error)
                        currentLastError = appError
                        cameraService.stop()
                        AppLogger.camera.error("Failed to start camera: \(appError.localizedDescription)")
                        completion(false)
                    }
                }
            }

            if shouldApplyStartTimeout {
                Task { @MainActor [weak self, attempt, startTask, timeoutNanoseconds] in
                    guard let self else { return }
                    try? await Task.sleep(nanoseconds: timeoutNanoseconds)
                    guard attempt.completeTimeout() else { return }

                    startTask.cancel()
                    let timeoutError = Self.cameraStartTimeoutError()
                    currentLastError = timeoutError
                    cameraService.stop()
                    AppLogger.camera.error("Camera start timed out")
                    completion(false)
                }
            }
        } else {
            completion(true)
        }
    }

    func stopCamera() {
        if cameraService.isActive || cameraService.session != nil {
            cameraService.stop()
            AppLogger.camera.info("Stopped camera")
        }
    }

    // MARK: - Camera Switching

    func switchCamera(to device: AVCaptureDevice) {
        // Access the concrete CameraManager to switch cameras
        if let cameraManager = cameraService as? CameraManager {
            cameraManager.switchCamera(to: device)
            currentCameraID = device.uniqueID
        }
    }

    private static func normalizedCameraStartError(_ error: Error) -> AppError {
        if let appError = error as? AppError {
            return appError
        }
        return .cameraSetupFailed(error)
    }

    private static func cameraStartTimeoutError() -> AppError {
        .cameraSetupFailed(NSError(
            domain: "SaneVideo.CameraState",
            code: -1001,
            userInfo: [
                NSLocalizedDescriptionKey: "Camera startup timed out. Check Camera permission and close other apps using the camera."
            ]
        ))
    }
}
