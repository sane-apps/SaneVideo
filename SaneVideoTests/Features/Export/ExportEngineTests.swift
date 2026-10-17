// ExportEngine guards: no empty exports, no concurrent exports.

import AVFoundation
import Foundation
@testable import SaneVideo
import Testing

@Suite("Export Engine Tests")
@MainActor
struct ExportEngineTests {
    private func tempOutputURL() -> URL {
        FileManager.default.temporaryDirectory.appendingPathComponent("ExportEngineTests-\(UUID().uuidString).mp4")
    }

    @Test("Exporting a project with no clips throws")
    func exportEmptyProject() async {
        let engine = ExportEngine()
        let outputURL = tempOutputURL()
        defer { try? FileManager.default.removeItem(at: outputURL) }

        await #expect(throws: (any Error).self) {
            _ = try await engine.export(
                project: VideoProject(name: "Empty Project"),
                settings: SaneExportSettings(),
                outputURL: outputURL,
                progressHandler: { _ in }
            )
        }
        #expect(!engine.isExporting, "A failed export must release the engine")
    }

    @Test("A second export while one is running throws alreadyExporting")
    func exportPreventsConcurrent() async throws {
        let assetURL = TestEnvironment.testAsset(named: "test_video.mp4")
        try #require(FileManager.default.fileExists(atPath: assetURL.path))
        let duration = try await AVURLAsset(url: assetURL).load(.duration)

        var project = VideoProject(name: "Concurrent Export")
        let clip = VideoClip(url: assetURL, duration: duration)
        project.updateTimeline(Timeline(tracks: [Track(name: "Video 1", type: .video, clips: [clip], zIndex: 0)]))

        let engine = ExportEngine()
        let firstURL = tempOutputURL()
        let secondURL = tempOutputURL()
        defer {
            try? FileManager.default.removeItem(at: firstURL)
            try? FileManager.default.removeItem(at: secondURL)
        }

        let firstExport = Task {
            try await engine.export(
                project: project, settings: SaneExportSettings(), outputURL: firstURL, progressHandler: { _ in }
            )
        }

        // export() sets isExporting before its first suspension, so yielding is enough.
        for _ in 0 ..< 1000 where !engine.isExporting {
            await Task.yield()
        }
        try #require(engine.isExporting, "First export never started")

        let error = await #expect(throws: ExportError.self) {
            _ = try await engine.export(
                project: project, settings: SaneExportSettings(), outputURL: secondURL, progressHandler: { _ in }
            )
        }
        if case .alreadyExporting? = error {
            // expected
        } else {
            Issue.record("Expected ExportError.alreadyExporting, got \(String(describing: error))")
        }

        engine.cancelExport()
        _ = await firstExport.result
    }
}
