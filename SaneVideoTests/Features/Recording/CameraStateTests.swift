//
//  CameraStateTests.swift
//  SaneVideoTests
//
//  Tests for CameraState - camera activation, device management, signal detection
//

import AVFoundation
@testable import SaneVideo
import Testing

/// Publisher updates arrive asynchronously; wait for the state instead of a fixed delay.
@MainActor
private func waitUntil(timeout: Duration = .seconds(3), _ condition: () -> Bool) async -> Bool {
    let clock = ContinuousClock()
    let deadline = clock.now.advanced(by: timeout)
    while !condition() {
        if clock.now >= deadline {
            return false
        }
        try? await Task.sleep(for: .milliseconds(5))
    }
    return true
}

@Suite("Camera State Tests")
@MainActor
struct CameraStateTests {
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

        let warmedUp = await waitUntil { cameraState.session === session && !cameraState.isPreviewWarmingUp }
        #expect(warmedUp)
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
            previewWarmupNanoseconds: 500_000_000
        )
        let session = AVCaptureSession()

        mock.session = session
        mock.sessionPublisherSubject.send(session)

        let started = await waitUntil(timeout: .milliseconds(400)) { cameraState.isPreviewWarmingUp }
        #expect(started, "Warmup should begin when the session appears")

        let ended = await waitUntil { !cameraState.isPreviewWarmingUp }
        #expect(ended, "Warmup should end on its own")
    }

    @Test("Signal and error publishers update camera preview state")
    func signalAndErrorPublishersUpdateCameraPreviewState() async throws {
        let mock = CameraServiceProtocolMock(session: AVCaptureSession())
        let cameraState = CameraState(cameraService: mock)

        mock.hasVideoSignal = true
        mock.lastError = .cameraUnavailable

        let updated = await waitUntil { cameraState.hasVideoSignal && cameraState.lastError != nil }
        #expect(updated)

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
}
