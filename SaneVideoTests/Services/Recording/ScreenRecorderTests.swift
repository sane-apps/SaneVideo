//
//  ScreenRecorderTests.swift
//  SaneVideoTests
//
//  Unit tests for ScreenRecorder screen capture functionality.
//

import AVFoundation
import Combine
import ScreenCaptureKit
import XCTest

@testable import SaneVideo

@MainActor
final class ScreenRecorderTests: XCTestCase {

    var sut: ScreenRecorderProtocolMock!
    var cancellables: Set<AnyCancellable>!

    override func setUp() async throws {
        sut = ScreenRecorderProtocolMock()
        cancellables = []
    }

    override func tearDown() {
        cancellables?.removeAll()
        cancellables = nil
        sut = nil
    }

    // MARK: - Start/Stop Tests

    func testStart_CallsStartHandler() async throws {
        // Arrange
        var startCalled = false
        var receivedURL: URL?
        sut.startHandler = { url in
            startCalled = true
            receivedURL = url
        }

        let outputURL = URL(fileURLWithPath: "/tmp/test_output.mp4")

        // Act
        try await sut.start(outputURL: outputURL)

        // Assert
        XCTAssertTrue(startCalled, "Start handler should be called")
        XCTAssertEqual(receivedURL, outputURL, "Output URL should be passed correctly")
        XCTAssertEqual(sut.startCallCount, 1)
    }

    func testStart_WithNilURL_CallsHandler() async throws {
        // Arrange
        var startCalled = false
        sut.startHandler = { url in
            startCalled = true
            XCTAssertNil(url, "URL should be nil when not provided")
        }

        // Act
        try await sut.start(outputURL: nil)

        // Assert
        XCTAssertTrue(startCalled)
    }

    func testStop_CallsStopHandler() async {
        // Arrange
        var stopCalled = false
        sut.stopHandler = { stopCalled = true }

        // Act
        await sut.stop()

        // Assert
        XCTAssertTrue(stopCalled, "Stop handler should be called")
        XCTAssertEqual(sut.stopCallCount, 1)
    }

    func testTeardown_CallsTeardownHandler() {
        // Arrange
        var teardownCalled = false
        sut.teardownHandler = { teardownCalled = true }

        // Act
        sut.teardown()

        // Assert
        XCTAssertTrue(teardownCalled)
        XCTAssertEqual(sut.teardownCallCount, 1)
    }

    // MARK: - State Property Tests

    func testActiveStream_DefaultsNil() {
        XCTAssertNil(sut.activeStream, "activeStream should default to nil")
    }

    func testIsStopping_DefaultsFalse() {
        XCTAssertFalse(sut.isStopping, "isStopping should default to false")
    }

    func testIsStopping_CanBeSet() {
        // Arrange & Act
        sut.isStopping = true

        // Assert
        XCTAssertTrue(sut.isStopping)
    }

    func testBaseFilter_DefaultsNil() {
        XCTAssertNil(sut.baseFilter, "baseFilter should default to nil")
    }

    func testRecordingFrame_DefaultsNil() {
        XCTAssertNil(sut.recordingFrame, "recordingFrame should default to nil")
    }

    func testRecordingFrame_CanBeSet() {
        // Arrange
        let testFrame = CGRect(x: 0, y: 0, width: 1920, height: 1080)

        // Act
        sut.recordingFrame = testFrame

        // Assert
        XCTAssertEqual(sut.recordingFrame, testFrame)
    }

    // MARK: - Callback Tests

    func testOnStop_CanBeSetAndCalled() {
        // Arrange
        var onStopCalled = false
        var receivedError: Error?
        sut.onStop = { error in
            onStopCalled = true
            receivedError = error
        }

        // Act
        sut.onStop?(nil)

        // Assert
        XCTAssertTrue(onStopCalled)
        XCTAssertNil(receivedError)
    }

    func testOnStop_ReceivesError() {
        // Arrange
        var receivedError: Error?
        sut.onStop = { error in
            receivedError = error
        }

        let testError = NSError(domain: "test", code: 1, userInfo: nil)

        // Act
        sut.onStop?(testError)

        // Assert
        XCTAssertNotNil(receivedError)
        XCTAssertEqual((receivedError as NSError?)?.code, 1)
    }

    func testOnPresenterOverlayChanged_CanBeSetAndCalled() {
        // Arrange
        var overlayState: Bool?
        sut.onPresenterOverlayChanged = { isActive in
            overlayState = isActive
        }

        // Act
        sut.onPresenterOverlayChanged?(true)

        // Assert
        XCTAssertEqual(overlayState, true)
    }

    func testOnContentSelected_CanBeSetAndCalled() {
        // Arrange
        var contentSelectedCalled = false
        sut.onContentSelected = {
            contentSelectedCalled = true
        }

        // Act
        sut.onContentSelected?()

        // Assert
        XCTAssertTrue(contentSelectedCalled)
    }

    // MARK: - Content Filter Tests

    func testUpdateContentFilter_CallsHandler() async {
        // Arrange
        var updateCalled = false
        sut.updateContentFilterHandler = { updateCalled = true }

        // Act
        await sut.updateContentFilter()

        // Assert
        XCTAssertTrue(updateCalled)
        XCTAssertEqual(sut.updateContentFilterCallCount, 1)
    }

    func testDynamicFilterSuppressionDetection_MatchesScreenCaptureKitTCCError() {
        let error = NSError(
            domain: "com.apple.ScreenCaptureKit.SCStreamErrorDomain",
            code: -3801,
            userInfo: [NSLocalizedDescriptionKey: "The user declined TCCs for application, window, display capture"]
        )

        XCTAssertTrue(
            ScreenRecorder.shouldSuppressDynamicFilterUpdates(for: error),
            "Dynamic filter retries should stop after the known ScreenCaptureKit TCC denial"
        )
    }

    func testDynamicFilterSuppressionDetection_IgnoresUnrelatedErrors() {
        let error = NSError(
            domain: "com.sanevideo.tests",
            code: 42,
            userInfo: [NSLocalizedDescriptionKey: "Something else failed"]
        )

        XCTAssertFalse(
            ScreenRecorder.shouldSuppressDynamicFilterUpdates(for: error),
            "Only the known ScreenCaptureKit access denial should disable future filter updates"
        )
    }

    // MARK: - Sample Buffer Subject Tests

    func testSampleBufferSubject_Exists() {
        XCTAssertNotNil(sut.sampleBufferSubject, "Video sample buffer subject should exist")
    }

    func testAudioSampleBufferSubject_Exists() {
        XCTAssertNotNil(sut.audioSampleBufferSubject, "Audio sample buffer subject should exist")
    }

    func testMicSampleBufferSubject_Exists() {
        XCTAssertNotNil(sut.micSampleBufferSubject, "Mic sample buffer subject should exist")
    }

    // MARK: - Lifecycle Tests

    func testFullRecordingLifecycle() async throws {
        // Arrange
        var states: [String] = []
        sut.startHandler = { _ in states.append("started") }
        sut.stopHandler = { states.append("stopped") }
        sut.teardownHandler = { states.append("teardown") }

        let outputURL = URL(fileURLWithPath: "/tmp/lifecycle_test.mp4")

        // Act
        try await sut.start(outputURL: outputURL)
        await sut.stop()
        sut.teardown()

        // Assert
        XCTAssertEqual(states, ["started", "stopped", "teardown"], "Lifecycle should proceed in correct order")
        XCTAssertEqual(sut.startCallCount, 1)
        XCTAssertEqual(sut.stopCallCount, 1)
        XCTAssertEqual(sut.teardownCallCount, 1)
    }

    func testMultipleStartStopCycles() async throws {
        // Arrange
        sut.startHandler = { _ in }
        sut.stopHandler = {}

        // Act
        for _ in 1...3 {
            try await sut.start(outputURL: nil)
            await sut.stop()
        }

        // Assert
        XCTAssertEqual(sut.startCallCount, 3, "Start should be called 3 times")
        XCTAssertEqual(sut.stopCallCount, 3, "Stop should be called 3 times")
    }
}
