//
//  RealTimeAudioProcessorTests.swift
//  SaneVideoTests
//
//  Unit tests for RealTimeAudioProcessor real-time effects.
//

import AVFoundation
import XCTest

@testable import SaneVideo

@MainActor
final class RealTimeAudioProcessorTests: XCTestCase {

    var sut: RealTimeAudioProcessorProtocolMock!

    override func setUp() async throws {
        sut = RealTimeAudioProcessorProtocolMock()
    }

    override func tearDown() {
        sut = nil
    }

    // MARK: - Setup Tests

    func testSetupForPlayerItem_CallsHandler() async throws {
        // Arrange
        var setupCalled = false
        sut.setupForPlayerItemHandler = { _, _, _ in
            setupCalled = true
        }

        let playerItem = AVPlayerItem(url: URL(fileURLWithPath: "/tmp/test.mp4"))
        let clip = VideoClip(
            url: URL(fileURLWithPath: "/tmp/test.mp4"),
            duration: CMTime(seconds: 10, preferredTimescale: 600)
        )
        let player = AVPlayer()

        // Act
        try await sut.setupForPlayerItem(playerItem, clip: clip, videoPlayer: player)

        // Assert
        XCTAssertTrue(setupCalled)
        XCTAssertEqual(sut.setupForPlayerItemCallCount, 1)
    }

    func testSetupForPlayerItem_CanThrowError() async {
        // Arrange
        let expectedError = NSError(domain: "AudioProcessor", code: 100, userInfo: nil)
        sut.setupForPlayerItemHandler = { _, _, _ in
            throw expectedError
        }

        let playerItem = AVPlayerItem(url: URL(fileURLWithPath: "/tmp/test.mp4"))
        let clip = VideoClip(
            url: URL(fileURLWithPath: "/tmp/test.mp4"),
            duration: CMTime(seconds: 10, preferredTimescale: 600)
        )
        let player = AVPlayer()

        // Act & Assert
        do {
            try await sut.setupForPlayerItem(playerItem, clip: clip, videoPlayer: player)
            XCTFail("Should have thrown an error")
        } catch {
            XCTAssertEqual((error as NSError).code, 100)
        }
    }

    // MARK: - Playback Control Tests

    func testPlay_CallsHandler() {
        // Arrange
        var playCalled = false
        sut.playHandler = {
            playCalled = true
        }

        // Act
        sut.play()

        // Assert
        XCTAssertTrue(playCalled)
        XCTAssertEqual(sut.playCallCount, 1)
    }

    func testPause_CallsHandler() {
        // Arrange
        var pauseCalled = false
        sut.pauseHandler = {
            pauseCalled = true
        }

        // Act
        sut.pause()

        // Assert
        XCTAssertTrue(pauseCalled)
        XCTAssertEqual(sut.pauseCallCount, 1)
    }

    func testSeek_CallsHandlerWithCorrectTime() {
        // Arrange
        var receivedTime: CMTime?
        sut.seekHandler = { time in
            receivedTime = time
        }

        let seekTime = CMTime(seconds: 5.5, preferredTimescale: 600)

        // Act
        sut.seek(to: seekTime)

        // Assert
        XCTAssertEqual(receivedTime, seekTime)
        XCTAssertEqual(sut.seekCallCount, 1)
    }

    func testSeek_RecordsArgValues() {
        // Arrange
        sut.seekHandler = { _ in }

        let times = [
            CMTime(seconds: 1.0, preferredTimescale: 600),
            CMTime(seconds: 5.0, preferredTimescale: 600),
            CMTime(seconds: 10.0, preferredTimescale: 600)
        ]

        // Act
        for time in times {
            sut.seek(to: time)
        }

        // Assert
        XCTAssertEqual(sut.seekCallCount, 3)
        XCTAssertEqual(sut.seekArgValues.count, 3)
    }

    // MARK: - Update Effects Tests

    func testUpdateEffects_CallsHandler() async throws {
        // Arrange
        var updateCalled = false
        sut.updateEffectsHandler = { clip in
            updateCalled = true
        }

        let clip = VideoClip(
            url: URL(fileURLWithPath: "/tmp/test.mp4"),
            duration: CMTime(seconds: 10, preferredTimescale: 600)
        )

        // Act
        try await sut.updateEffects(for: clip)

        // Assert
        XCTAssertTrue(updateCalled)
        XCTAssertEqual(sut.updateEffectsCallCount, 1)
    }

    func testUpdateEffects_RecordsClipArgument() async throws {
        // Arrange
        sut.updateEffectsHandler = { _ in }

        var clip = VideoClip(
            url: URL(fileURLWithPath: "/tmp/test.mp4"),
            duration: CMTime(seconds: 10, preferredTimescale: 600)
        )
        clip.isVoiceIsolationEnabled = true
        clip.volume = 0.5

        // Act
        try await sut.updateEffects(for: clip)

        // Assert
        XCTAssertEqual(sut.updateEffectsArgValues.first?.id, clip.id)
    }

    func testUpdateEffects_CanThrowError() async {
        // Arrange
        let expectedError = NSError(domain: "AudioProcessor", code: 200, userInfo: nil)
        sut.updateEffectsHandler = { _ in
            throw expectedError
        }

        let clip = VideoClip(
            url: URL(fileURLWithPath: "/tmp/test.mp4"),
            duration: CMTime(seconds: 10, preferredTimescale: 600)
        )

        // Act & Assert
        do {
            try await sut.updateEffects(for: clip)
            XCTFail("Should have thrown an error")
        } catch {
            XCTAssertEqual((error as NSError).code, 200)
        }
    }

    // MARK: - Cleanup Tests

    func testCleanup_CallsHandler() {
        // Arrange
        var cleanupCalled = false
        sut.cleanupHandler = {
            cleanupCalled = true
        }

        // Act
        sut.cleanup()

        // Assert
        XCTAssertTrue(cleanupCalled)
        XCTAssertEqual(sut.cleanupCallCount, 1)
    }

    func testCleanup_CanBeCalledMultipleTimes() {
        // Arrange
        sut.cleanupHandler = {}

        // Act
        sut.cleanup()
        sut.cleanup()

        // Assert
        XCTAssertEqual(sut.cleanupCallCount, 2)
    }

    // MARK: - Lifecycle Tests

    func testFullPlaybackLifecycle() async throws {
        // Arrange
        var states: [String] = []
        sut.setupForPlayerItemHandler = { _, _, _ in states.append("setup") }
        sut.playHandler = { states.append("play") }
        sut.seekHandler = { _ in states.append("seek") }
        sut.pauseHandler = { states.append("pause") }
        sut.cleanupHandler = { states.append("cleanup") }

        let playerItem = AVPlayerItem(url: URL(fileURLWithPath: "/tmp/test.mp4"))
        let clip = VideoClip(
            url: URL(fileURLWithPath: "/tmp/test.mp4"),
            duration: CMTime(seconds: 10, preferredTimescale: 600)
        )
        let player = AVPlayer()

        // Act
        try await sut.setupForPlayerItem(playerItem, clip: clip, videoPlayer: player)
        sut.play()
        sut.seek(to: CMTime(seconds: 5.0, preferredTimescale: 600))
        sut.pause()
        sut.cleanup()

        // Assert
        XCTAssertEqual(states, ["setup", "play", "seek", "pause", "cleanup"])
    }
}
