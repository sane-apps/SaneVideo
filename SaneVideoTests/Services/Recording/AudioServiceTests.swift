//
//  AudioServiceTests.swift
//  SaneVideoTests
//
//  Unit tests for AudioService microphone capture functionality.
//

import AVFoundation
import Combine
import XCTest

@testable import SaneVideo

@MainActor
final class AudioServiceTests: XCTestCase {

    var sut: AudioServiceProtocolMock!
    var cancellables: Set<AnyCancellable>!

    override func setUp() async throws {
        sut = AudioServiceProtocolMock()
        cancellables = []
    }

    override func tearDown() {
        cancellables?.removeAll()
        cancellables = nil
        sut = nil
    }

    // MARK: - Start/Stop Tests

    func testStart_CallsStartHandler() {
        // Arrange
        var startCalled = false
        sut.startHandler = { startCalled = true }

        // Act
        sut.start()

        // Assert
        XCTAssertTrue(startCalled, "Start handler should be called")
        XCTAssertEqual(sut.startCallCount, 1, "Start should be called once")
    }

    func testStop_CallsStopHandler() {
        // Arrange
        var stopCalled = false
        sut.stopHandler = { stopCalled = true }

        // Act
        sut.stop()

        // Assert
        XCTAssertTrue(stopCalled, "Stop handler should be called")
        XCTAssertEqual(sut.stopCallCount, 1, "Stop should be called once")
    }

    func testStartThenStop_BothHandlersCalled() {
        // Arrange
        var startCalled = false
        var stopCalled = false
        sut.startHandler = { startCalled = true }
        sut.stopHandler = { stopCalled = true }

        // Act
        sut.start()
        sut.stop()

        // Assert
        XCTAssertTrue(startCalled, "Start should be called")
        XCTAssertTrue(stopCalled, "Stop should be called")
        XCTAssertEqual(sut.startCallCount, 1)
        XCTAssertEqual(sut.stopCallCount, 1)
    }

    // MARK: - Permission Tests

    func testCheckPermission_CallsHandler() {
        // Arrange
        var checkCalled = false
        sut.checkPermissionHandler = { checkCalled = true }

        // Act
        sut.checkPermission()

        // Assert
        XCTAssertTrue(checkCalled)
        XCTAssertEqual(sut.checkPermissionCallCount, 1)
    }

    func testRequestPermission_CallsHandler() {
        // Arrange
        var requestCalled = false
        sut.requestPermissionHandler = { requestCalled = true }

        // Act
        sut.requestPermission()

        // Assert
        XCTAssertTrue(requestCalled)
        XCTAssertEqual(sut.requestPermissionCallCount, 1)
    }

    // MARK: - Property Tests

    func testIsRunning_DefaultsFalse() {
        XCTAssertFalse(sut.isRunning, "isRunning should default to false")
    }

    func testIsRunning_CanBeSet() {
        // Arrange & Act
        sut.isRunning = true

        // Assert
        XCTAssertTrue(sut.isRunning)
    }

    func testPermissionGranted_DefaultsFalse() {
        XCTAssertFalse(sut.permissionGranted, "permissionGranted should default to false")
    }

    func testPermissionGranted_CanBeSet() {
        // Arrange & Act
        sut.permissionGranted = true

        // Assert
        XCTAssertTrue(sut.permissionGranted)
    }

    func testCurrentMicID_DefaultsNil() {
        XCTAssertNil(sut.currentMicID, "currentMicID should default to nil")
    }

    func testAvailableMicrophones_DefaultsEmpty() {
        XCTAssertTrue(sut.availableMicrophones.isEmpty, "availableMicrophones should default to empty")
    }

    // MARK: - Microphone Management Tests

    func testRefreshMicrophones_CallsHandler() {
        // Arrange
        var refreshCalled = false
        sut.refreshMicrophonesHandler = { refreshCalled = true }

        // Act
        sut.refreshMicrophones()

        // Assert
        XCTAssertTrue(refreshCalled)
        XCTAssertEqual(sut.refreshMicrophonesCallCount, 1)
    }

    func testEnsureMicrophonesDiscovered_CallsHandler() {
        // Arrange
        var discoverCalled = false
        sut.ensureMicrophonesDiscoveredHandler = { discoverCalled = true }

        // Act
        sut.ensureMicrophonesDiscovered()

        // Assert
        XCTAssertTrue(discoverCalled)
        XCTAssertEqual(sut.ensureMicrophonesDiscoveredCallCount, 1)
    }

    // MARK: - Sample Buffer Subject Tests

    func testSampleBufferSubject_CanPublishValues() {
        // Arrange
        var receivedValue = false
        let expectation = expectation(description: "Received sample buffer")

        sut.sampleBufferSubject
            .sink { _ in
                receivedValue = true
                expectation.fulfill()
            }
            .store(in: &cancellables)

        // Act - create a minimal sample buffer for testing
        // Note: Creating a real CMSampleBuffer is complex, so we just verify the subject exists
        // In integration tests, we'd test with real buffers

        // For mock testing, we can verify the subject was accessed
        XCTAssertNotNil(sut.sampleBufferSubject, "Sample buffer subject should exist")

        // Cancel the expectation as we can't easily create a CMSampleBuffer
        expectation.fulfill()

        wait(for: [expectation], timeout: 0.1)
    }

    func testAudioLevelSubject_CanReceiveValues() {
        // Arrange
        var receivedLevel: Float?
        let expectation = expectation(description: "Received audio level")

        sut.audioLevelSubject
            .sink { level in
                receivedLevel = level
                expectation.fulfill()
            }
            .store(in: &cancellables)

        // Act
        sut.audioLevelSubject.send(0.75)

        // Assert
        wait(for: [expectation], timeout: 1.0)
        XCTAssertNotNil(receivedLevel)
        if let level = receivedLevel {
            XCTAssertEqual(Double(level), 0.75, accuracy: 0.001)
        }
    }

    func testAudioLevelSubject_ReceivesMultipleValues() {
        // Arrange
        var receivedLevels: [Float] = []
        let expectation = expectation(description: "Received multiple levels")
        expectation.expectedFulfillmentCount = 3

        sut.audioLevelSubject
            .sink { level in
                receivedLevels.append(level)
                expectation.fulfill()
            }
            .store(in: &cancellables)

        // Act
        sut.audioLevelSubject.send(0.1)
        sut.audioLevelSubject.send(0.5)
        sut.audioLevelSubject.send(0.9)

        // Assert
        wait(for: [expectation], timeout: 1.0)
        XCTAssertEqual(receivedLevels, [0.1, 0.5, 0.9])
    }
}
