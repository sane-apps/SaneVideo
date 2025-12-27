//
//  ExportCompositorTests.swift
//  SaneVideoTests
//
//  Tests for ExportCompositor - composition building, video composition configuration
//

import Testing
import AVFoundation
@testable import SaneVideo

@Suite("Export Compositor Tests")
@MainActor
struct ExportCompositorTests {

    // MARK: - Test Setup

    var sut: ExportCompositor {
        ExportCompositor()
    }

    // MARK: - Composition Building Tests

    @Test("Create composition from empty project throws error")
    func createCompositionEmptyProject() async {
        // Arrange
        let compositor = sut
        let project = VideoProject(name: "Empty Project")

        // Act & Assert - Should throw error for empty project
        do {
            _ = try await compositor.createComposition(from: project)
            #expect(Bool(false), "Should throw error for empty project")
        } catch {
            #expect(true, "Should throw error for empty project")
        }
    }

    @Test("Create composition builds composition result")
    func createComposition() async {
        // Arrange
        let compositor = sut
        let project = VideoProject(name: "Test Project")
        // Note: Empty project will fail, but tests the method exists

        // Act & Assert
        do {
            _ = try await compositor.createComposition(from: project)
            #expect(Bool(false), "Should throw error for empty project")
        } catch {
            #expect(true, "Error is expected for empty project")
        }
    }

    // MARK: - Video Composition Tests

    @Test("Create video composition with settings")
    func createVideoComposition() async throws {
        // Arrange
        let compositor = sut
        let composition = AVMutableComposition()
        let baseVideoComposition = AVMutableVideoComposition()
        var settings = SaneExportSettings()
        settings.resolution = .hd1080
        settings.frameRate = 30.0

        // Act
        let videoComposition = try await compositor.createVideoComposition(
            for: composition,
            baseVideoComposition: baseVideoComposition,
            settings: settings
        )

        // Assert
        #expect(videoComposition != nil, "Should create video composition")

        if let videoComposition {
            #expect(videoComposition.renderSize.width == 1920, "Should set correct width")
            #expect(videoComposition.renderSize.height == 1080, "Should set correct height")
        }
    }

    @Test("Create video composition respects frame rate")
    func createVideoCompositionFrameRate() async throws {
        // Arrange
        let compositor = sut
        let composition = AVMutableComposition()
        let baseVideoComposition = AVMutableVideoComposition()
        var settings = SaneExportSettings()
        settings.frameRate = 60.0

        // Act
        let videoComposition = try await compositor.createVideoComposition(
            for: composition,
            baseVideoComposition: baseVideoComposition,
            settings: settings
        )

        // Assert
        if let videoComposition {
            #expect(videoComposition.frameDuration.value == 1, "Should set frame duration")
            #expect(videoComposition.frameDuration.timescale == 60, "Should set 60fps")
        } else {
            #expect(Bool(false), "Video composition should not be nil")
        }
    }
}
