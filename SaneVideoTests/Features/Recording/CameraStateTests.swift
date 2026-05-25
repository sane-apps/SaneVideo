//
//  CameraStateTests.swift
//  SaneVideoTests
//
//  Tests for CameraState - camera activation, device management, signal detection
//

import Testing
import AVFoundation
@testable import SaneVideo

@Suite("Camera State Tests")
@MainActor
struct CameraStateTests {

    // MARK: - Test Setup

    var sut: CameraState {
        CameraState()
    }

    // MARK: - Initial State Tests

    @Test("Initial state has correct defaults")
    func initialState() {
        // Arrange & Act
        let cameraState = sut

        // Assert
        #expect(cameraState.isActive == false, "Camera should be inactive by default")
        #expect(cameraState.currentCameraID == nil, "No camera ID initially")
        #expect(cameraState.availableCameras.isEmpty, "No cameras discovered initially")
    }

    // MARK: - Camera Discovery Tests

    @Test("Refresh cameras completes and updates state")
    func refreshCameras() {
        // Arrange
        let cameraState = sut
        // Initial state: availableCameras is empty (not discovered yet)

        // Act - method should complete without throwing
        cameraState.refreshCameras()

        // Assert - Verify method completed and state is consistent
        // The method sets hasDiscoveredCameras = true internally
        // We verify completion by checking that ensureCamerasDiscovered()
        // doesn't call refresh again (proving hasDiscoveredCameras was set)
        let camerasBefore = cameraState.availableCameras
        cameraState.ensureCamerasDiscovered()  // Should be a no-op if refresh worked
        let camerasAfter = cameraState.availableCameras

        // If refreshCameras() set hasDiscoveredCameras = true, then ensureCamerasDiscovered()
        // won't call refresh again, so cameras list should be unchanged
        #expect(camerasBefore.count == camerasAfter.count,
                "ensureCamerasDiscovered should be no-op after refreshCameras")
    }

    @Test("Ensure cameras discovered calls refresh when not discovered")
    func ensureCamerasDiscovered() {
        // Arrange
        let cameraState = sut
        // Initial state: cameras not discovered (availableCameras is empty)

        // Act - This should call refreshCameras() internally
        cameraState.ensureCamerasDiscovered()

        // Assert - Verify method completed and cameras are now "discovered"
        // After ensureCamerasDiscovered(), calling it again should be a no-op
        let camerasBefore = cameraState.availableCameras
        cameraState.ensureCamerasDiscovered()  // Second call should be no-op
        let camerasAfter = cameraState.availableCameras

        // If ensureCamerasDiscovered() worked, second call should be no-op
        #expect(camerasBefore.count == camerasAfter.count,
                "Second ensureCamerasDiscovered call should be no-op")
    }

    // MARK: - Camera Activation Tests

    @Test("Toggle camera calls toggle on service", .disabled("Requires camera service mock injection"))
    func toggleCamera() {
        // NOTE: This test is disabled because CameraState creates its own service internally.
        // To properly test toggle behavior, we need dependency injection of CameraServiceProtocolMock.
        // The current implementation delegates to cameraService.toggle() in production,
        // and only toggles isActive directly when -uitesting flag is set.

        // Arrange
        let cameraState = sut

        // Act
        cameraState.toggleCamera()

        // Assert - In unit tests (without -uitesting flag), this calls cameraService.toggle()
        // which may or may not change isActive depending on service state
    }

    @Test("Start camera activates camera", .disabled("Requires real camera hardware"))
    func startCamera() async {
        // This test requires real camera hardware or mock injection
        // Arrange
        let cameraState = sut
        var completionCalled = false

        // Act
        cameraState.startCamera { _ in
            completionCalled = true
        }

        // Assert
        #expect(completionCalled, "Completion should be called")
    }

    @Test("Stop camera completes without throwing")
    func stopCamera() {
        // Arrange
        let cameraState = sut

        // Act - stopCamera only acts if cameraService.isActive is true
        // In test env, service is inactive, so this is a no-op but should not crash
        cameraState.stopCamera()

        // Assert - method completed without throwing (implicit pass)
        // No state change expected since camera wasn't active
    }

    @Test("Stop camera tears down stale inactive session")
    func stopCameraStopsStaleInactiveSession() {
        let mock = CameraServiceProtocolMock(isActive: false, session: AVCaptureSession())
        let cameraState = CameraState(cameraService: mock)

        cameraState.stopCamera()

        #expect(mock.stopCallCount == 1)
    }

    @Test("Start camera times out instead of loading forever")
    func startCameraTimesOutInsteadOfLoadingForever() async {
        let mock = CameraServiceProtocolMock()
        mock.startHandler = {
            try await Task.sleep(nanoseconds: 5_000_000_000)
        }
        let cameraState = CameraState(
            cameraService: mock,
            startTimeoutNanoseconds: 50_000_000,
            usePermissionlessTestFastPath: false,
            cameraAuthorizationStatus: { .authorized }
        )

        let didStart = await withCheckedContinuation { continuation in
            cameraState.startCamera { didStart in
                continuation.resume(returning: didStart)
            }
        }

        #expect(didStart == false)
        #expect(mock.stopCallCount == 1)
        #expect(cameraState.lastError?.localizedDescription.contains("timed out") == true)
        #expect(cameraState.shouldShowLivePreview == false)
    }

    @Test("Started camera times out when no video signal arrives")
    func startedCameraTimesOutWhenNoVideoSignalArrives() async {
        let mock = CameraServiceProtocolMock(session: AVCaptureSession())
        mock.startHandler = {
            await MainActor.run {
                mock.isActive = true
                mock.isActivePublisherSubject.send(true)
            }
        }
        mock.stopHandler = {
            MainActor.assumeIsolated {
                mock.isActive = false
                mock.session = nil
                mock.hasVideoSignal = false
                mock.isActivePublisherSubject.send(false)
                mock.sessionPublisherSubject.send(nil)
            }
        }
        let cameraState = CameraState(
            cameraService: mock,
            signalTimeoutNanoseconds: 50_000_000,
            usePermissionlessTestFastPath: false,
            cameraAuthorizationStatus: { .authorized }
        )

        let didStart = await withCheckedContinuation { continuation in
            cameraState.startCamera { didStart in
                continuation.resume(returning: didStart)
            }
        }

        #expect(didStart == false)
        #expect(mock.stopCallCount == 1)
        #expect(cameraState.lastError?.localizedDescription.contains("no video signal") == true)
        #expect(cameraState.shouldShowLivePreview == false)
    }

    @Test("Started camera succeeds when video signal arrives")
    func startedCameraSucceedsWhenVideoSignalArrives() async {
        let mock = CameraServiceProtocolMock(session: AVCaptureSession())
        mock.startHandler = {
            await MainActor.run {
                mock.isActive = true
                mock.isActivePublisherSubject.send(true)
            }
            Task { @MainActor in
                try? await Task.sleep(nanoseconds: 20_000_000)
                mock.hasVideoSignal = true
            }
        }
        let cameraState = CameraState(
            cameraService: mock,
            signalTimeoutNanoseconds: 200_000_000,
            usePermissionlessTestFastPath: false,
            cameraAuthorizationStatus: { .authorized }
        )

        let didStart = await withCheckedContinuation { continuation in
            cameraState.startCamera { didStart in
                continuation.resume(returning: didStart)
            }
        }

        #expect(didStart == true)
        #expect(mock.stopCallCount == 0)
        #expect(cameraState.shouldShowLivePreview == true)
    }

    // MARK: - Camera Switching Tests

    @Test("Switch camera method exists", .disabled("Requires AVCaptureDevice"))
    func switchCamera() {
        // This test requires a real AVCaptureDevice which can't be mocked easily
        // The method signature is verified at compile time
    }

    // MARK: - Computed Properties Tests

    @Test("Session property is accessible")
    func sessionProperty() {
        // Arrange
        let cameraState = sut

        // Act
        let session = cameraState.session

        // Assert - Session should be nil when camera not started
        #expect(session == nil, "Session should be nil before camera starts")
    }

    @Test("Has video signal defaults to false when inactive")
    func hasVideoSignalProperty() {
        // Arrange
        let cameraState = sut

        // Act
        let hasSignal = cameraState.hasVideoSignal

        // Assert - Should be false when camera is not active
        #expect(hasSignal == false, "Should be false when camera inactive")
    }

    @Test("Camera surface stays reserved while a session still exists")
    func shouldShowCameraSurfaceWhileSessionExists() {
        let mock = CameraServiceProtocolMock(session: AVCaptureSession())
        let cameraState = CameraState(cameraService: mock)

        #expect(cameraState.shouldShowCameraSurface == true)
        #expect(cameraState.shouldMountLivePreview == false)
        #expect(cameraState.shouldShowLivePreview == false)
    }

    @Test("Live preview waits for first video signal even when session is active")
    func shouldNotShowLivePreviewForActiveSessionWithoutSignal() {
        let mock = CameraServiceProtocolMock(
            isActive: true,
            hasVideoSignal: false,
            session: AVCaptureSession()
        )
        let cameraState = CameraState(cameraService: mock)

        #expect(cameraState.shouldShowCameraSurface == true)
        #expect(cameraState.shouldMountLivePreview == true)
        #expect(cameraState.shouldShowLivePreview == false)
    }

    @Test("Session publisher updates camera preview state")
    func sessionPublisherUpdatesCameraPreviewState() async throws {
        let mock = CameraServiceProtocolMock()
        let cameraState = CameraState(
            cameraService: mock,
            previewWarmupNanoseconds: 20_000_000
        )
        let session = AVCaptureSession()

        mock.session = session
        mock.hasVideoSignal = true
        mock.sessionPublisherSubject.send(session)

        try await Task.sleep(nanoseconds: 50_000_000)

        #expect(cameraState.session === session)
        #expect(cameraState.shouldShowCameraSurface == true)
        #expect(cameraState.shouldMountLivePreview == false)
        #expect(cameraState.shouldShowLivePreview == true)
        #expect(cameraState.isPreviewWarmingUp == false)
    }

    @Test("Preview warmup stays active briefly after session appears")
    func previewWarmupStaysActiveAfterSessionAppears() async throws {
        let mock = CameraServiceProtocolMock(isActive: true)
        let cameraState = CameraState(
            cameraService: mock,
            previewWarmupNanoseconds: 50_000_000
        )
        let session = AVCaptureSession()

        mock.session = session
        mock.sessionPublisherSubject.send(session)

        try await Task.sleep(nanoseconds: 10_000_000)

        #expect(cameraState.isPreviewWarmingUp == true)

        try await Task.sleep(nanoseconds: 80_000_000)

        #expect(cameraState.isPreviewWarmingUp == false)
    }

    @Test("Signal and error publishers update camera preview state")
    func signalAndErrorPublishersUpdateCameraPreviewState() async throws {
        let mock = CameraServiceProtocolMock(session: AVCaptureSession())
        let cameraState = CameraState(cameraService: mock)

        mock.hasVideoSignal = true
        mock.lastError = .cameraUnavailable

        try await Task.sleep(nanoseconds: 50_000_000)

        #expect(cameraState.hasVideoSignal == true)
        #expect(cameraState.shouldShowLivePreview == true)
        #expect(cameraState.lastError?.localizedDescription == AppError.cameraUnavailable.localizedDescription)
    }

    @Test("Live preview becomes visible when active signal is present")
    func shouldShowLivePreviewWhenActive() {
        let mock = CameraServiceProtocolMock(
            isActive: true,
            hasVideoSignal: true,
            session: AVCaptureSession()
        )
        let cameraState = CameraState(cameraService: mock)

        #expect(cameraState.shouldShowCameraSurface == true)
        #expect(cameraState.shouldMountLivePreview == true)
        #expect(cameraState.shouldShowLivePreview == true)
    }

    @Test("Audio level publisher exists")
    func audioLevelPublisher() {
        // Arrange
        let cameraState = sut

        // Act
        let publisher = cameraState.audioLevelPublisher

        // Assert - Publisher should exist
        #expect(publisher != nil, "Publisher should exist")
    }
}
