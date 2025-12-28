//
//  VideoWriterTests.swift
//  SaneVideoTests
//
//  Unit tests for VideoWriter frame writing functionality.
//

import AVFoundation
import CoreMedia
import XCTest

@testable import SaneVideo

final class VideoWriterTests: XCTestCase {

    // MARK: - Property Tests (using async to access actor-isolated mock)

    func testIsWriting_DefaultsFalse() async {
        let sut = await VideoWriterProtocolMock()
        let isWriting = await sut.isWriting
        XCTAssertFalse(isWriting, "isWriting should default to false")
    }

    func testIsWriting_CanBeSet() async {
        let sut = await VideoWriterProtocolMock()
        await MainActor.run {
            Task { @RecordingActor in
                sut.isWriting = true
            }
        }
        // Give actor time to process
        try? await Task.sleep(nanoseconds: 10_000_000)
        let isWriting = await sut.isWriting
        XCTAssertTrue(isWriting)
    }

    func testError_DefaultsNil() async {
        let sut = await VideoWriterProtocolMock()
        let error = await sut.error
        XCTAssertNil(error, "error should default to nil")
    }

    func testIsReadyForData_DefaultsFalse() async {
        let sut = await VideoWriterProtocolMock()
        let isReady = await sut.isReadyForData
        XCTAssertFalse(isReady, "isReadyForData should default to false")
    }

    // MARK: - Start/Finish Tests

    func testStart_CallsStartHandler() async throws {
        let sut = await VideoWriterProtocolMock()
        var startCalled = false
        var receivedURL: URL?

        await Task { @RecordingActor in
            sut.startHandler = { url in
                startCalled = true
                receivedURL = url
            }
        }.value

        let outputURL = URL(fileURLWithPath: "/tmp/test_video.mp4")

        // Act
        try await sut.start(outputURL: outputURL)

        // Assert
        XCTAssertTrue(startCalled)
        XCTAssertEqual(receivedURL, outputURL)
        let callCount = await sut.startCallCount
        XCTAssertEqual(callCount, 1)
    }

    func testStartSession_CallsHandler() async {
        let sut = await VideoWriterProtocolMock()
        var sessionStarted = false
        var receivedTime: CMTime?

        await Task { @RecordingActor in
            sut.startSessionHandler = { time in
                sessionStarted = true
                receivedTime = time
            }
        }.value

        let startTime = CMTime(seconds: 1.5, preferredTimescale: 600)

        // Act
        await sut.startSession(at: startTime)

        // Assert
        XCTAssertTrue(sessionStarted)
        XCTAssertEqual(receivedTime, startTime)
        let callCount = await sut.startSessionCallCount
        XCTAssertEqual(callCount, 1)
    }

    func testFinish_CallsHandlerAndReturnsURL() async {
        let sut = await VideoWriterProtocolMock()
        let expectedURL = URL(fileURLWithPath: "/tmp/finished_video.mp4")

        await Task { @RecordingActor in
            sut.finishHandler = { return expectedURL }
        }.value

        // Act
        let result = await sut.finish()

        // Assert
        XCTAssertEqual(result, expectedURL)
        let callCount = await sut.finishCallCount
        XCTAssertEqual(callCount, 1)
    }

    func testFinish_CanReturnNil() async {
        let sut = await VideoWriterProtocolMock()

        await Task { @RecordingActor in
            sut.finishHandler = { return nil }
        }.value

        // Act
        let result = await sut.finish()

        // Assert
        XCTAssertNil(result)
    }

    // MARK: - Camera Frame Tests

    func testUpdateCameraFrame_CallsHandler() async {
        let sut = await VideoWriterProtocolMock()
        var updateCalled = false
        var receivedBuffer: CVPixelBuffer?

        await Task { @RecordingActor in
            sut.updateCameraFrameHandler = { buffer in
                updateCalled = true
                receivedBuffer = buffer
            }
        }.value

        // Act
        await sut.updateCameraFrame(nil)

        // Assert
        XCTAssertTrue(updateCalled)
        XCTAssertNil(receivedBuffer)
        let callCount = await sut.updateCameraFrameCallCount
        XCTAssertEqual(callCount, 1)
    }

    // MARK: - PiP Frame Tests

    func testUpdatePiPFrame_CallsHandler() async {
        let sut = await VideoWriterProtocolMock()
        var updateCalled = false
        var receivedFrame: CGRect?
        var receivedScreenFrame: CGRect?

        await Task { @RecordingActor in
            sut.updatePiPFrameHandler = { frame, screenFrame in
                updateCalled = true
                receivedFrame = frame
                receivedScreenFrame = screenFrame
            }
        }.value

        let pipFrame = CGRect(x: 100, y: 100, width: 320, height: 240)
        let screenFrame = CGRect(x: 0, y: 0, width: 1920, height: 1080)

        // Act
        await sut.updatePiPFrame(pipFrame, screenFrame: screenFrame)

        // Assert
        XCTAssertTrue(updateCalled)
        XCTAssertEqual(receivedFrame, pipFrame)
        XCTAssertEqual(receivedScreenFrame, screenFrame)
        let callCount = await sut.updatePiPFrameCallCount
        XCTAssertEqual(callCount, 1)
    }

    func testUpdatePiPFrame_WithNilValues() async {
        let sut = await VideoWriterProtocolMock()
        var updateCalled = false

        await Task { @RecordingActor in
            sut.updatePiPFrameHandler = { frame, screenFrame in
                updateCalled = true
                XCTAssertNil(frame)
                XCTAssertNil(screenFrame)
            }
        }.value

        // Act
        await sut.updatePiPFrame(nil, screenFrame: nil)

        // Assert
        XCTAssertTrue(updateCalled)
    }

    // MARK: - Lifecycle Tests

    func testFullWritingLifecycle() async throws {
        let sut = await VideoWriterProtocolMock()
        var states: [String] = []
        let outputURL = URL(fileURLWithPath: "/tmp/lifecycle.mp4")
        let finishedURL = URL(fileURLWithPath: "/tmp/finished.mp4")

        await Task { @RecordingActor in
            sut.startHandler = { _ in states.append("started") }
            sut.startSessionHandler = { _ in states.append("session") }
            sut.finishHandler = {
                states.append("finished")
                return finishedURL
            }
        }.value

        // Act
        try await sut.start(outputURL: outputURL)
        await sut.startSession(at: .zero)
        let result = await sut.finish()

        // Assert
        XCTAssertEqual(states, ["started", "session", "finished"])
        XCTAssertEqual(result, finishedURL)
    }
}
