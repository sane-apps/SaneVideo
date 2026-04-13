import AppKit
import CoreMedia
import XCTest

@testable import SaneVideo

@MainActor
final class DemoPackExportServiceTests: XCTestCase {

    func testExportDemoPackWritesExpectedArtifacts() async throws {
        let outputDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: outputDirectory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: outputDirectory) }

        let exportService = StubExportService()
        let thumbnailService = StubThumbnailService()
        let pdfService = StubPDFService()
        let service = DemoPackExportService(
            exportService: exportService,
            thumbnailService: thumbnailService,
            pdfService: pdfService
        )

        var clip = VideoClip(
            url: URL(fileURLWithPath: "/tmp/demo-pack-test.mp4"),
            duration: CMTime(seconds: 8, preferredTimescale: 600)
        )
        clip.captions = [
            Caption(
                text: "Hello world",
                startTime: .zero,
                endTime: CMTime(seconds: 2, preferredTimescale: 600)
            )
        ]

        var project = VideoProject(name: "Demo Pack Test")
        project.timeline.tracks = [
            Track(name: "Video", type: .video, clips: [clip], zIndex: 0)
        ]
        project.speakerNotes = SpeakerNotes(text: "Lead with the main value proposition.")
        project.chapterMarkers = [
            ChapterMarker(title: "Intro", timestamp: 0),
            ChapterMarker(title: "Walkthrough", timestamp: 3)
        ]
        project.publishMetadata = PublishMetadata(
            title: "Demo Pack Test",
            subtitle: "Offline demo",
            description: "A privacy-first walkthrough.",
            callToAction: "Try it locally"
        )
        project.demoPackSettings = DemoPackSettings(
            includeLandscapeVideo: true,
            includeVerticalVariant: true,
            includeSquareVariant: false,
            includeThumbnail: true,
            includeTranscriptText: true,
            includeTranscriptPDF: true,
            includeSpeakerNotes: true,
            includeChapters: true,
            includePublishMetadata: true
        )

        let bundleURL = try await service.exportDemoPack(
            project: project,
            settings: SaneExportSettings(codec: .h264, resolution: .hd1080, bitrate: 8_000_000, frameRate: 30),
            outputDirectory: outputDirectory
        ) { _, _ in }

        XCTAssertTrue(FileManager.default.fileExists(atPath: bundleURL.appendingPathComponent("README.md").path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: bundleURL.appendingPathComponent("landscape-demo.mp4").path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: bundleURL.appendingPathComponent("vertical-demo.mp4").path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: bundleURL.appendingPathComponent("thumbnail.png").path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: bundleURL.appendingPathComponent("transcript.txt").path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: bundleURL.appendingPathComponent("transcript.pdf").path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: bundleURL.appendingPathComponent("speaker-notes.md").path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: bundleURL.appendingPathComponent("chapters.json").path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: bundleURL.appendingPathComponent("publish-metadata.json").path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: bundleURL.appendingPathComponent("title.txt").path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: bundleURL.appendingPathComponent("description.txt").path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: bundleURL.appendingPathComponent("cta.txt").path))
    }
}

@MainActor
private final class StubExportService: ExportServiceProtocol {
    var progress: Double = 0
    var isExporting = false

    func export(
        project _: VideoProject,
        settings _: SaneExportSettings,
        outputURL: URL,
        progressHandler: @escaping @Sendable (Double) -> Void
    ) async throws -> URL {
        isExporting = true
        progressHandler(0.5)
        try Data("demo".utf8).write(to: outputURL)
        progress = 1
        isExporting = false
        progressHandler(1)
        return outputURL
    }

    func cancelExport() {
        isExporting = false
    }
}

private actor StubThumbnailService: ThumbnailServiceProtocol {
    func thumbnail(for _: VideoClip, time _: CMTime, size _: CGSize) async -> UncheckedBox<NSImage>? {
        UncheckedBox(testImage())
    }

    func clearCache() {}

    func generateBestThumbnail(for _: URL, strategy _: ThumbnailScoringStrategy) async throws -> UncheckedBox<NSImage> {
        UncheckedBox(testImage())
    }

    func generateSmartThumbnail(for _: URL, strategy _: ThumbnailScoringStrategy) async throws -> URL {
        URL(fileURLWithPath: "/tmp/mock-thumbnail.png")
    }

    private func testImage() -> NSImage {
        let rep = NSBitmapImageRep(
            bitmapDataPlanes: nil,
            pixelsWide: 4,
            pixelsHigh: 4,
            bitsPerSample: 8,
            samplesPerPixel: 4,
            hasAlpha: true,
            isPlanar: false,
            colorSpaceName: .deviceRGB,
            bytesPerRow: 0,
            bitsPerPixel: 0
        )!
        let image = NSImage(size: NSSize(width: 4, height: 4))
        image.addRepresentation(rep)
        return image
    }
}

private actor StubPDFService: PDFGeneratorServiceProtocol {
    func generateStudyGuide(for _: VideoProject, outputURL: URL) async throws {
        try Data("pdf".utf8).write(to: outputURL)
    }

    func generateStudyGuideData(for _: VideoProject) throws -> Data {
        Data("pdf".utf8)
    }
}
