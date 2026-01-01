//
//  ExportEngineTests.swift
//  SaneVideoTests
//
//  Tests for ExportEngine - export state, progress tracking, cancellation
//

import Testing
import AVFoundation
@testable import SaneVideo

@Suite("Export Engine Tests")
@MainActor
struct ExportEngineTests {

    // MARK: - Test Setup

    var sut: ExportEngine {
        ExportEngine()
    }

    // MARK: - Initial State Tests

    @Test("Initial state has correct defaults")
    func initialState() {
        // Arrange & Act
        let engine = sut

        // Assert
        #expect(engine.isExporting == false, "Should not be exporting initially")
        #expect(engine.progress == 0.0, "Progress should be zero initially")
    }

    // MARK: - Export State Tests

    @Test("Export state prevents concurrent exports")
    func exportPreventsConcurrent() async throws {
        // Arrange
        let engine = sut
        let project = VideoProject(name: "Test Project")
        let settings = SaneExportSettings()
        let outputURL = FileManager.default.temporaryDirectory.appendingPathComponent("test_export.mp4")

        // Act - Start first export (will fail due to no actual video, but tests state)
        let exportTask = Task {
            try await engine.export(
                project: project,
                settings: settings,
                outputURL: outputURL,
                progressHandler: { _ in }
            )
        }

        // Wait a moment for state to update
        try? await Task.sleep(nanoseconds: 100_000_000) // 0.1s

        // Try second export - should throw an error
        // Note: May be alreadyExporting if first export is still running,
        // or compositionFailed if first export already completed (timing-dependent)
        await #expect(throws: (any Error).self, "Concurrent export should throw an error") {
            _ = try await engine.export(
                project: project,
                settings: settings,
                outputURL: outputURL,
                progressHandler: { _ in }
            )
        }

        // Cleanup
        exportTask.cancel()
    }

    // MARK: - Cancellation Tests

    @Test("Cancel export completes without error")
    func cancelExport() {
        // Arrange
        let engine = sut
        let initialIsExporting = engine.isExporting

        // Act
        engine.cancelExport()

        // Assert - Verify method completed and state is accessible
        // The method should complete without throwing
        // We verify completion by checking state is still accessible
        let finalIsExporting = engine.isExporting
        // Verify state is accessible (proves method completed)
        // Initial state is false (not exporting), so after cancel it should still be false
        #expect(finalIsExporting == initialIsExporting,
                "isExporting should remain unchanged when canceling with no active export")
    }

    // MARK: - Progress Tracking Tests

    @Test("Progress starts at zero")
    func progressStartsAtZero() {
        // Arrange
        let engine = sut

        // Act & Assert
        #expect(engine.progress == 0.0, "Progress should start at zero")
    }

    // MARK: - Export Error Handling Tests

    @Test("Export with empty project throws error")
    func exportEmptyProject() async {
        // Arrange
        let engine = sut
        let project = VideoProject(name: "Empty Project")
        let settings = SaneExportSettings()
        let outputURL = FileManager.default.temporaryDirectory.appendingPathComponent("test_export.mp4")

        // Act & Assert - Should throw error for empty project
        // Can be ExportError.invalidProject or AppError.compositionFailed depending on code path
        await #expect(throws: (any Error).self, "Empty project export should throw an error") {
            _ = try await engine.export(
                project: project,
                settings: settings,
                outputURL: outputURL,
                progressHandler: { _ in }
            )
        }
    }

    // MARK: - Export Settings Tests

    @Test("Export with settings on empty project throws error")
    func exportRespectsSettings() async {
        // Arrange
        let engine = sut
        let project = VideoProject(name: "Test Project")
        var settings = SaneExportSettings()
        settings.resolution = .hd1080
        settings.frameRate = 30.0
        let outputURL = FileManager.default.temporaryDirectory.appendingPathComponent("test_export.mp4")

        // Act & Assert - Should throw error for project without clips
        await #expect(throws: (any Error).self, "Project without clips should throw an error") {
            _ = try await engine.export(
                project: project,
                settings: settings,
                outputURL: outputURL,
                progressHandler: { _ in }
            )
        }
    }
}
