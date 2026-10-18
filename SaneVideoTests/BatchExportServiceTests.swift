// Shorts export, written to a temp folder (never ~/Movies/SaneVideo/Shorts).

import AVFoundation
import CoreMedia
import Foundation
@testable import SaneVideo
import Testing

@Suite("Batch Export Service")
struct BatchExportServiceTests {
    private final class ProgressRecorder: @unchecked Sendable {
        private let lock = NSLock()
        private var values: [Double] = []

        func append(_ value: Double) {
            lock.withLock { values.append(value) }
        }

        var snapshot: [Double] {
            lock.withLock { values }
        }
    }

    private func makeOutputDirectory() -> URL {
        FileManager.default.temporaryDirectory.appendingPathComponent("ShortsTests-\(UUID().uuidString)", isDirectory: true)
    }

    @Test("An empty candidate list exports nothing and creates no folder")
    func exportEmptyCandidatesReturnsEmpty() async throws {
        let outputDirectory = makeOutputDirectory()
        let service = BatchExportService(outputDirectory: outputDirectory)

        let results = try await service.exportShorts(
            [],
            from: TestEnvironment.mockAssetURL,
            settings: RepurposingSettings(),
            progressHandler: { _ in }
        )

        #expect(results.isEmpty)
        #expect(!FileManager.default.fileExists(atPath: outputDirectory.path))
    }

    @Test("A 1 s candidate exports as a vertical 1080x1920 clip of 1 s named after the project, with progress reaching 1")
    func exportsVerticalShort() async throws {
        let outputDirectory = makeOutputDirectory()
        defer { try? FileManager.default.removeItem(at: outputDirectory) }
        let service = BatchExportService(outputDirectory: outputDirectory)
        let progress = ProgressRecorder()
        let candidate = ShortCandidate(
            timeRange: CMTimeRange(
                start: CMTime(seconds: 1, preferredTimescale: 600),
                duration: CMTime(seconds: 1, preferredTimescale: 600)
            )
        )

        let results = try await service.exportShorts(
            [candidate],
            from: TestEnvironment.mockAssetURL,
            name: "My Talk",
            settings: RepurposingSettings(aspectRatio: .vertical9x16),
            progressHandler: { progress.append($0) }
        )

        let url = try #require(results.first)
        #expect(results.count == 1)
        #expect(url.deletingLastPathComponent().standardizedFileURL == outputDirectory.standardizedFileURL)
        #expect(url.lastPathComponent.hasPrefix("My Talk Short 1 "))

        let asset = AVURLAsset(url: url)
        let duration = try await asset.load(.duration).seconds
        #expect(abs(duration - 1.0) < 0.1)
        let track = try #require(try await asset.loadTracks(withMediaType: .video).first)
        let size = try await track.load(.naturalSize)
        #expect(size == CGSize(width: 1080, height: 1920))
        #expect(progress.snapshot.last == 1.0)
    }

    @Test("A short leaves out what Clean Up cut inside its range")
    func shortSkipsCleanUpCuts() async throws {
        let outputDirectory = makeOutputDirectory()
        defer { try? FileManager.default.removeItem(at: outputDirectory) }
        let service = BatchExportService(outputDirectory: outputDirectory)
        let candidate = ShortCandidate(
            timeRange: CMTimeRange(
                start: CMTime(seconds: 1, preferredTimescale: 600),
                duration: CMTime(seconds: 2, preferredTimescale: 600)
            )
        )
        let cut = CMTimeRange(
            start: CMTime(seconds: 1.5, preferredTimescale: 600),
            duration: CMTime(seconds: 0.5, preferredTimescale: 600)
        )

        let results = try await service.exportShorts(
            [candidate],
            from: TestEnvironment.mockAssetURL,
            removedRanges: [cut],
            settings: RepurposingSettings(aspectRatio: .vertical9x16),
            progressHandler: { _ in }
        )

        let url = try #require(results.first)
        let duration = try await AVURLAsset(url: url).load(.duration).seconds
        #expect(abs(duration - 1.5) < 0.1, "2 s range minus the 0.5 s cut")
    }

    @Test("Kept ranges split around cuts and drop fully cut ranges")
    func keptRangesSplitAroundCuts() {
        func range(_ start: Double, _ end: Double) -> CMTimeRange {
            CMTimeRange(
                start: CMTime(seconds: start, preferredTimescale: 600),
                end: CMTime(seconds: end, preferredTimescale: 600)
            )
        }
        let kept = BatchExportService.keptRanges(of: range(0, 10), removing: [range(6, 7), range(2, 3), range(9, 12)])
        #expect(kept.map { [$0.start.seconds, $0.end.seconds] } == [[0, 2], [3, 6], [7, 9]])
        #expect(BatchExportService.keptRanges(of: range(2, 3), removing: [range(0, 5)]).isEmpty)
    }
}
