//
//  CameraState.swift
//  SaneVideo
//
//  Created by SaneVideo Refactor
//

import AVFoundation
import Combine
import SwiftUI

@MainActor
@Observable
class CameraState {
    // MARK: - Published Properties

    var isActive = false
    var currentCameraID: String?
    var availableCameras: [AVCaptureDevice] = []

    // MARK: - Computed Properties

    var session: AVCaptureSession? { cameraService.session }
    var hasVideoSignal: Bool { cameraService.hasVideoSignal }
    var audioLevelPublisher: AnyPublisher<Float, Never> { audioService.audioLevelSubject.eraseToAnyPublisher() }

    // MARK: - Internal Properties

    private let cameraService: CameraServiceProtocol
    private let audioService: AudioService
    private var cancellables = Set<AnyCancellable>()
    private var hasDiscoveredCameras = false

    // MARK: - Initialization

    init(cameraService: CameraServiceProtocol? = nil, audioService: AudioService? = nil) {
        self.cameraService = cameraService ?? ServiceContainer.shared.cameraService
        self.audioService = audioService ?? ServiceContainer.shared.audioService
        setupObserver()
        // NOTE: Camera discovery is deferred until refreshCameras() is called
        // This prevents CMIO daemon activation on app launch
    }

    /// Refresh the list of available cameras (call when user interacts with camera picker)
    func refreshCameras() {
        let isTesting = ProcessInfo.processInfo.arguments.contains("-uitesting")
        if isTesting {
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

        // Crash fix: Ensure session updates are received on main queue for @MainActor isolation
        cameraService.sessionPublisher
            .receive(on: DispatchQueue.main)
            .sink { _ in
                // With @Observable, nested property changes in cameraService.session 
                // aren't automatically tracked unless session itself is @Observable.
                // However, assigning to session property (if it were a var) would trigger it.
                // Here we just trigger a refresh of views that depend on 'session'
                // by essentially doing nothing but verifying the property accessed in the view.
            }
            .store(in: &cancellables)
    }

    // MARK: - Actions

    func toggleCamera() {
        let isTesting = ProcessInfo.processInfo.arguments.contains("-uitesting")
        if isTesting {
            isActive.toggle()
            return
        }
        cameraService.toggle()
        AppLogger.camera.info("Toggled camera (Active: \(cameraService.isActive))")
    }

    func startCamera(completion: @escaping @Sendable () -> Void = {}) {
        let isTesting = ProcessInfo.processInfo.arguments.contains("-uitesting")
        if isTesting {
            isActive = true
            completion()
            return
        }

        // Ensure cameras are discovered when starting (in case user never opened picker)
        ensureCamerasDiscovered()
        
        if !cameraService.isActive {
            Task {
                do {
                    try await cameraService.start()
                    AppLogger.camera.info("Started camera")
                } catch {
                    AppLogger.camera.error("Failed to start camera: \(error.localizedDescription)")
                }
                completion()
            }
        } else {
            completion()
        }
    }

    func stopCamera() {
        if cameraService.isActive {
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
}
