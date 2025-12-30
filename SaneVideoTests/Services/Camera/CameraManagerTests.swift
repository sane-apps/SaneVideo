//
//  CameraManagerTests.swift
//  SaneVideoTests
//
//  Tests for CameraManager via CameraServiceProtocolMock
//

import Testing
import AVFoundation
import Combine
@testable import SaneVideo

@Suite("Camera Manager Tests")
@MainActor
struct CameraManagerTests {

    // MARK: - Mock Tests

    @Test("Mock initial isActive is false")
    func mockInitialIsActiveFalse() {
        // Arrange & Act
        let mock = CameraServiceProtocolMock()

        // Assert
        #expect(mock.isActive == false)
    }

    @Test("Mock initial hasVideoSignal is false")
    func mockInitialHasVideoSignalFalse() {
        // Arrange & Act
        let mock = CameraServiceProtocolMock()

        // Assert
        #expect(mock.hasVideoSignal == false)
    }

    @Test("Mock initial permissionGranted is false")
    func mockInitialPermissionGrantedFalse() {
        // Arrange & Act
        let mock = CameraServiceProtocolMock()

        // Assert
        #expect(mock.permissionGranted == false)
    }

    @Test("Mock initial lastError is nil")
    func mockInitialLastErrorNil() {
        // Arrange & Act
        let mock = CameraServiceProtocolMock()

        // Assert
        #expect(mock.lastError == nil)
    }

    @Test("Mock initial session is nil")
    func mockInitialSessionNil() {
        // Arrange & Act
        let mock = CameraServiceProtocolMock()

        // Assert
        #expect(mock.session == nil)
    }

    // MARK: - Start Method Tests

    @Test("Start calls handler")
    func startCallsHandler() async throws {
        // Arrange
        let mock = CameraServiceProtocolMock()
        var startCalled = false

        mock.startHandler = {
            startCalled = true
        }

        // Act
        try await mock.start()

        // Assert
        #expect(startCalled == true)
        #expect(mock.startCallCount == 1)
    }

    @Test("Start can throw error")
    func startCanThrowError() async {
        // Arrange
        let mock = CameraServiceProtocolMock()
        mock.startHandler = {
            throw AppError.cameraPermissionDenied
        }

        // Act & Assert
        do {
            try await mock.start()
            #expect(Bool(false), "Should have thrown")
        } catch {
            #expect(error is AppError)
        }
    }

    // MARK: - Stop Method Tests

    @Test("Stop calls handler")
    func stopCallsHandler() {
        // Arrange
        let mock = CameraServiceProtocolMock()
        var stopCalled = false

        mock.stopHandler = {
            stopCalled = true
        }

        // Act
        mock.stop()

        // Assert
        #expect(stopCalled == true)
        #expect(mock.stopCallCount == 1)
    }

    // MARK: - Toggle Method Tests

    @Test("Toggle calls handler")
    func toggleCallsHandler() {
        // Arrange
        let mock = CameraServiceProtocolMock()
        var toggleCalled = false

        mock.toggleHandler = {
            toggleCalled = true
        }

        // Act
        mock.toggle()

        // Assert
        #expect(toggleCalled == true)
        #expect(mock.toggleCallCount == 1)
    }

    // MARK: - Publisher Tests

    @Test("isActivePublisher can receive values")
    func isActivePublisherCanReceiveValues() async {
        // Arrange
        let mock = CameraServiceProtocolMock()
        var receivedValues: [Bool] = []
        var cancellables = Set<AnyCancellable>()

        mock.isActivePublisher
            .sink { value in
                receivedValues.append(value)
            }
            .store(in: &cancellables)

        // Act - manually send a value through the subject
        mock.isActivePublisherSubject.send(true)

        // Assert - value should be received
        #expect(receivedValues.contains(true))
    }

    @Test("sessionPublisher can receive values")
    func sessionPublisherCanReceiveValues() async {
        // Arrange
        let mock = CameraServiceProtocolMock()
        var receivedValues: [AVCaptureSession?] = []
        var cancellables = Set<AnyCancellable>()

        mock.sessionPublisher
            .sink { value in
                receivedValues.append(value)
            }
            .store(in: &cancellables)

        // Act - manually send a value through the subject
        mock.sessionPublisherSubject.send(nil)

        // Assert - value should be received
        #expect(receivedValues.count >= 1)
    }

    // MARK: - Restart Session Tests

    @Test("restartSession calls handler")
    func restartSessionCallsHandler() {
        // Arrange
        let mock = CameraServiceProtocolMock()
        var restartCalled = false

        mock.restartSessionHandler = {
            restartCalled = true
        }

        // Act
        mock.restartSession()

        // Assert
        #expect(restartCalled == true)
        #expect(mock.restartSessionCallCount == 1)
    }

    // MARK: - Permission Tests

    @Test("requestPermissionAgain calls handler")
    func requestPermissionAgainCallsHandler() {
        // Arrange
        let mock = CameraServiceProtocolMock()
        var permissionCalled = false

        mock.requestPermissionAgainHandler = {
            permissionCalled = true
        }

        // Act
        mock.requestPermissionAgain()

        // Assert
        #expect(permissionCalled == true)
        #expect(mock.requestPermissionAgainCallCount == 1)
    }

    // MARK: - State Modification Tests

    @Test("isActive can be set")
    func isActiveCanBeSet() {
        // Arrange
        let mock = CameraServiceProtocolMock()
        #expect(mock.isActive == false)

        // Act
        mock.isActive = true

        // Assert
        #expect(mock.isActive == true)
    }

    @Test("hasVideoSignal can be set")
    func hasVideoSignalCanBeSet() {
        // Arrange
        let mock = CameraServiceProtocolMock()
        #expect(mock.hasVideoSignal == false)

        // Act
        mock.hasVideoSignal = true

        // Assert
        #expect(mock.hasVideoSignal == true)
    }

    @Test("permissionGranted can be set")
    func permissionGrantedCanBeSet() {
        // Arrange
        let mock = CameraServiceProtocolMock()
        #expect(mock.permissionGranted == false)

        // Act
        mock.permissionGranted = true

        // Assert
        #expect(mock.permissionGranted == true)
    }
}
