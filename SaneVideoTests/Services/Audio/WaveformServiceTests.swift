//
//  WaveformServiceTests.swift
//  SaneVideoTests
//
//  Unit tests for WaveformService waveform generation.
//

import AVFoundation
import XCTest

@testable import SaneVideo

final class WaveformServiceTests: XCTestCase {

    // MARK: - Waveform Generation Tests

    func testWaveform_CallsHandler() async {
        // Arrange
        let sut = WaveformServiceProtocolMock()
        var waveformCalled = false
        let expectedSamples: [Float] = [0.1, 0.5, 0.8, 0.3, 0.6]

        await sut.setWaveformHandler { clip in
            waveformCalled = true
            return expectedSamples
        }

        let testClip = VideoClip(
            url: URL(fileURLWithPath: "/tmp/test.mp4"),
            duration: CMTime(seconds: 10, preferredTimescale: 600)
        )

        // Act
        let result = await sut.waveform(for: testClip)

        // Assert
        XCTAssertTrue(waveformCalled)
        XCTAssertEqual(result, expectedSamples)
        let callCount = await sut.waveformCallCount
        XCTAssertEqual(callCount, 1)
    }

    func testWaveform_ReturnsNilWhenCancelled() async {
        // Arrange
        let sut = WaveformServiceProtocolMock()
        await sut.setWaveformHandler { _ in
            return nil
        }

        let testClip = VideoClip(
            url: URL(fileURLWithPath: "/tmp/test.mp4"),
            duration: CMTime(seconds: 10, preferredTimescale: 600)
        )

        // Act
        let result = await sut.waveform(for: testClip)

        // Assert
        XCTAssertNil(result)
    }

    func testWaveform_RecordsClipArgument() async {
        // Arrange
        let sut = WaveformServiceProtocolMock()
        let testClip = VideoClip(
            url: URL(fileURLWithPath: "/tmp/specific_test.mp4"),
            duration: CMTime(seconds: 30, preferredTimescale: 600)
        )

        await sut.setWaveformHandler { clip in
            return [0.5]
        }

        // Act
        _ = await sut.waveform(for: testClip)

        // Assert
        let callCount = await sut.waveformCallCount
        XCTAssertEqual(callCount, 1)
        let argValues = await sut.waveformArgValues
        XCTAssertEqual(argValues.first?.id, testClip.id)
    }

    // MARK: - Cancel Load Tests

    func testCancelLoad_CallsHandler() async {
        // Arrange
        let sut = WaveformServiceProtocolMock()
        var cancelCalled = false

        await sut.setCancelLoadHandler { clip in
            cancelCalled = true
        }

        let testClip = VideoClip(
            url: URL(fileURLWithPath: "/tmp/test.mp4"),
            duration: CMTime(seconds: 10, preferredTimescale: 600)
        )

        // Act
        await sut.cancelLoad(for: testClip)

        // Assert
        XCTAssertTrue(cancelCalled)
        let callCount = await sut.cancelLoadCallCount
        XCTAssertEqual(callCount, 1)
    }

    func testCancelLoad_RecordsClipArgument() async {
        // Arrange
        let sut = WaveformServiceProtocolMock()
        let testClip = VideoClip(
            url: URL(fileURLWithPath: "/tmp/cancel_test.mp4"),
            duration: CMTime(seconds: 15, preferredTimescale: 600)
        )

        await sut.setCancelLoadHandler { _ in }

        // Act
        await sut.cancelLoad(for: testClip)

        // Assert
        let argValues = await sut.cancelLoadArgValues
        XCTAssertEqual(argValues.first?.id, testClip.id)
    }

    // MARK: - Clear Cache Tests

    func testClearCache_CallsHandler() async {
        // Arrange
        let sut = WaveformServiceProtocolMock()
        var clearCalled = false

        await sut.setClearCacheHandler {
            clearCalled = true
        }

        // Act
        await sut.clearCache()

        // Assert
        XCTAssertTrue(clearCalled)
        let callCount = await sut.clearCacheCallCount
        XCTAssertEqual(callCount, 1)
    }

    func testClearCache_CanBeCalledMultipleTimes() async {
        // Arrange
        let sut = WaveformServiceProtocolMock()
        await sut.setClearCacheHandler {}

        // Act
        await sut.clearCache()
        await sut.clearCache()
        await sut.clearCache()

        // Assert
        let callCount = await sut.clearCacheCallCount
        XCTAssertEqual(callCount, 3)
    }

    // MARK: - Multiple Clips Tests

    func testWaveform_MultipleClips_TracksCallCount() async {
        // Arrange
        let sut = WaveformServiceProtocolMock()
        await sut.setWaveformHandler { _ in [0.5] }

        let clips = (1...5).map { i in
            VideoClip(
                url: URL(fileURLWithPath: "/tmp/clip\(i).mp4"),
                duration: CMTime(seconds: Double(i * 10), preferredTimescale: 600)
            )
        }

        // Act
        for clip in clips {
            _ = await sut.waveform(for: clip)
        }

        // Assert
        let callCount = await sut.waveformCallCount
        XCTAssertEqual(callCount, 5)
    }
}

// MARK: - Mock Extensions for Handler Setting

extension WaveformServiceProtocolMock {
    func setWaveformHandler(_ handler: @escaping (VideoClip) async -> [Float]?) async {
        self.waveformHandler = handler
    }

    func setCancelLoadHandler(_ handler: @escaping (VideoClip) -> Void) async {
        self.cancelLoadHandler = handler
    }

    func setClearCacheHandler(_ handler: @escaping () -> Void) async {
        self.clearCacheHandler = handler
    }
}
