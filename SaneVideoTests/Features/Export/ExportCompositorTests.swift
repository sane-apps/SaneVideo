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
        let settings = SaneExportSettings()

        // Act & Assert - Should throw error for empty project
        // Can be ExportError or AppError depending on code path
        await #expect(throws: (any Error).self, "Empty project should throw an error") {
            _ = try await compositor.createComposition(from: project, settings: settings)
        }
    }

    @Test("Create composition from project without clips throws error")
    func createCompositionNoClips() async {
        // Arrange
        let compositor = sut
        let project = VideoProject(name: "Test Project")
        let settings = SaneExportSettings()
        // Note: Project without clips should fail

        // Act & Assert
        await #expect(throws: (any Error).self, "Project without clips should throw an error") {
            _ = try await compositor.createComposition(from: project, settings: settings)
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
        // Assert video composition exists and has correct frame rate
        let unwrappedComposition = try #require(videoComposition, "Video composition should not be nil")
        #expect(unwrappedComposition.frameDuration.value == 1, "Should set frame duration")
        #expect(unwrappedComposition.frameDuration.timescale == 60, "Should set 60fps")
    }
}
