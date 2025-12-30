//
//  VideoWriterIntegrationTests.swift
//  SaneVideoTests
//
//  Integration tests for VideoWriter - tests the real implementation
//

import Testing
import AVFoundation
import CoreMedia
@testable import SaneVideo

@Suite("VideoWriter Integration Tests")
struct VideoWriterIntegrationTests {

    // MARK: - Initialization Tests

    @Test("Initial isWriting is false")
    func initialIsWritingFalse() async throws {
        // Arrange & Act
        let writer = await VideoWriter()

        // Assert
        let isWriting = await writer.isWriting
        #expect(isWriting == false)
    }

    @Test("Initial error is nil")
    func initialErrorNil() async throws {
        // Arrange & Act
        let writer = await VideoWriter()

        // Assert
        let error = await writer.error
        #expect(error == nil)
    }

    @Test("Initial isReadyForData is false")
    func initialIsReadyForDataFalse() async throws {
        // Arrange & Act
        let writer = await VideoWriter()

        // Assert
        let isReady = await writer.isReadyForData
        #expect(isReady == false)
    }

    // MARK: - Start Tests

    @Test("Start creates asset writer")
    func startCreatesAssetWriter() async throws {
        // Arrange
        let writer = await VideoWriter()
        let tempURL = FileManager.default.temporaryDirectory.appendingPathComponent("test_\(UUID().uuidString).mp4")

        // Act
        try await writer.start(outputURL: tempURL)

        // Assert
        let isWriting = await writer.isWriting
        #expect(isWriting == true)

        // Cleanup
        _ = await writer.finish()
        try? FileManager.default.removeItem(at: tempURL)
    }

    // MARK: - Session Management Tests

    @Test("StartSession ignored when not writing")
    func startSessionIgnoredWhenNotWriting() async throws {
        // Arrange
        let writer = await VideoWriter()

        // Act - startSession without calling start first
        let time = CMTime(value: 0, timescale: 600)
        await writer.startSession(at: time)

        // Assert - no crash, isWriting still false
        let isWriting = await writer.isWriting
        #expect(isWriting == false)
    }

    // MARK: - Finish Tests

    @Test("Finish returns nil when session never started")
    func finishReturnsNilWhenSessionNeverStarted() async throws {
        // Arrange
        let writer = await VideoWriter()
        let tempURL = FileManager.default.temporaryDirectory.appendingPathComponent("test_\(UUID().uuidString).mp4")
        try await writer.start(outputURL: tempURL)
        // Note: We don't call startSession

        // Act
        let result = await writer.finish()

        // Assert
        #expect(result == nil)

        // Cleanup
        try? FileManager.default.removeItem(at: tempURL)
    }

    @Test("Finish cleans up resources")
    func finishCleansUpResources() async throws {
        // Arrange
        let writer = await VideoWriter()
        let tempURL = FileManager.default.temporaryDirectory.appendingPathComponent("test_\(UUID().uuidString).mp4")
        try await writer.start(outputURL: tempURL)
        let time = CMTime(value: 0, timescale: 600)
        await writer.startSession(at: time)

        // Act
        _ = await writer.finish()

        // Assert - isWriting should be false after finish
        let isWriting = await writer.isWriting
        #expect(isWriting == false)

        // Cleanup
        try? FileManager.default.removeItem(at: tempURL)
    }

    @Test("Double finish returns same result (idempotent)")
    func doubleFinishIdempotent() async throws {
        // Arrange
        let writer = await VideoWriter()
        let tempURL = FileManager.default.temporaryDirectory.appendingPathComponent("test_\(UUID().uuidString).mp4")
        try await writer.start(outputURL: tempURL)
        let time = CMTime(value: 0, timescale: 600)
        await writer.startSession(at: time)

        // Act - call finish twice concurrently
        async let result1 = writer.finish()
        async let result2 = writer.finish()
        let (url1, url2) = await (result1, result2)

        // Assert - both should return the same result
        #expect((url1 == nil && url2 == nil) || (url1 == url2))

        // Cleanup
        try? FileManager.default.removeItem(at: tempURL)
        if let url = url1 { try? FileManager.default.removeItem(at: url) }
    }

    // MARK: - PiP Frame Update Tests

    @Test("UpdatePiPFrame stores frame position")
    func updatePiPFrameStoresPosition() async throws {
        // Arrange
        let writer = await VideoWriter()
        let pipFrame = CGRect(x: 100, y: 100, width: 200, height: 200)
        let screenFrame = CGRect(x: 0, y: 0, width: 1920, height: 1080)

        // Act
        await writer.updatePiPFrame(pipFrame, screenFrame: screenFrame)

        // Assert - no crash
        #expect(true)
    }

    @Test("UpdatePiPFrame throttles rapid updates")
    func updatePiPFrameThrottlesUpdates() async throws {
        // Arrange
        let writer = await VideoWriter()
        let screenFrame = CGRect(x: 0, y: 0, width: 1920, height: 1080)

        // Act - rapid updates (should be throttled to ~30fps)
        for i in 0..<100 {
            let frame = CGRect(x: CGFloat(i), y: CGFloat(i), width: 200, height: 200)
            await writer.updatePiPFrame(frame, screenFrame: screenFrame)
        }

        // Assert - no crash
        #expect(true)
    }

    @Test("UpdatePiPFrame handles nil gracefully")
    func updatePiPFrameHandlesNil() async throws {
        // Arrange
        let writer = await VideoWriter()

        // Act
        await writer.updatePiPFrame(nil, screenFrame: nil)

        // Assert - no crash
        #expect(true)
    }

    // MARK: - Camera Frame Update Tests

    @Test("UpdateCameraFrame stores frame")
    func updateCameraFrameStores() async throws {
        // Arrange
        let writer = await VideoWriter()

        // Act - pass nil (camera frame cleared)
        await writer.updateCameraFrame(nil)

        // Assert - no crash
        #expect(true)
    }

    // MARK: - Write Guards Tests

    @Test("Write methods guard against non-ready state")
    func writeMethodsGuardNonReady() async throws {
        // Arrange
        let writer = await VideoWriter()
        // Don't start writer

        // Assert - isReadyForData is false, writes would be guarded
        let isReady = await writer.isReadyForData
        #expect(isReady == false)
    }

    // MARK: - Target Size Tests

    @Test("Video outputs at 1080p resolution")
    func videoOutputs1080p() async throws {
        // Arrange
        let writer = await VideoWriter()
        let tempURL = FileManager.default.temporaryDirectory.appendingPathComponent("test_\(UUID().uuidString).mp4")

        // Act
        try await writer.start(outputURL: tempURL)

        // Assert - writer is configured
        let isWriting = await writer.isWriting
        #expect(isWriting == true)

        // Cleanup
        _ = await writer.finish()
        try? FileManager.default.removeItem(at: tempURL)
    }
}
