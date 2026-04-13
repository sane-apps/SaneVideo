//
//  DemoPackExportService.swift
//  SaneVideo
//
//  Builds a local-only export bundle for product demos.
//

import AppKit
import Foundation

enum DemoPackExportError: Error, LocalizedError {
    case missingVideoContent
    case missingOutputDirectory

    var errorDescription: String? {
        switch self {
        case .missingVideoContent:
            "The project has no video content to export."
        case .missingOutputDirectory:
            "Choose a valid output folder for the demo pack."
        }
    }
}

@MainActor
final class DemoPackExportService {
    private let exportService: ExportServiceProtocol
    private let thumbnailService: any ThumbnailServiceProtocol
    private let pdfService: any PDFGeneratorServiceProtocol

    init(
        exportService: ExportServiceProtocol,
        thumbnailService: any ThumbnailServiceProtocol,
        pdfService: any PDFGeneratorServiceProtocol
    ) {
        self.exportService = exportService
        self.thumbnailService = thumbnailService
        self.pdfService = pdfService
    }

    func exportDemoPack(
        project: VideoProject,
        settings: SaneExportSettings,
        outputDirectory: URL,
        progressHandler: @escaping @Sendable (String, Double) -> Void
    ) async throws -> URL {
        guard project.timeline.tracks.contains(where: { !$0.clips.isEmpty }) else {
            throw DemoPackExportError.missingVideoContent
        }

        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: outputDirectory.path, isDirectory: &isDirectory),
              isDirectory.boolValue
        else {
            throw DemoPackExportError.missingOutputDirectory
        }

        let bundleURL = makeBundleURL(projectName: project.name, in: outputDirectory)
        try FileManager.default.createDirectory(at: bundleURL, withIntermediateDirectories: true)

        let stepCount = totalStepCount(for: project.demoPackSettings)
        var completedSteps = 0.0

        func advance(_ label: String) {
            completedSteps += 1
            progressHandler(label, min(completedSteps / Double(stepCount), 1.0))
        }

        progressHandler("Preparing demo pack...", 0)

        let manifest = bundleURL.appendingPathComponent("README.md")
        try buildReadme(for: project).write(to: manifest, atomically: true, encoding: .utf8)
        advance("Wrote local-only bundle manifest")

        if project.demoPackSettings.includeLandscapeVideo {
            let landscapeVideoURL = bundleURL.appendingPathComponent(
                "landscape-demo\(settings.fileExtension == "mov" ? ".mov" : ".mp4")"
            )
            let baseProgress = completedSteps
            _ = try await exportService.export(
                project: project,
                settings: settings,
                outputURL: landscapeVideoURL
            ) { progress in
                progressHandler(
                    "Exporting landscape video...",
                    min((baseProgress + progress) / Double(stepCount), 0.99)
                )
            }
            advance("Exported landscape video")
        }

        if project.demoPackSettings.includeVerticalVariant {
            var vertical = settings
            vertical.aspectRatio = .vertical9x16
            vertical.resolution = .hd1080
            let verticalURL = bundleURL.appendingPathComponent("vertical-demo.mp4")
            let baseProgress = completedSteps
            _ = try await exportService.export(
                project: project,
                settings: vertical,
                outputURL: verticalURL
            ) { progress in
                progressHandler(
                    "Exporting vertical variant...",
                    min((baseProgress + progress) / Double(stepCount), 0.99)
                )
            }
            advance("Exported vertical variant")
        }

        if project.demoPackSettings.includeSquareVariant {
            var square = settings
            square.aspectRatio = .square1x1
            square.resolution = .hd1080
            let squareURL = bundleURL.appendingPathComponent("square-teaser.mp4")
            let baseProgress = completedSteps
            _ = try await exportService.export(
                project: project,
                settings: square,
                outputURL: squareURL
            ) { progress in
                progressHandler(
                    "Exporting square variant...",
                    min((baseProgress + progress) / Double(stepCount), 0.99)
                )
            }
            advance("Exported square variant")
        }

        if project.demoPackSettings.includeThumbnail,
           let firstClip = project.timeline.tracks.flatMap(\.clips).first {
            let image = try await thumbnailService.generateBestThumbnail(
                for: firstClip.url,
                strategy: .aesthetic
            )
            let thumbnailURL = bundleURL.appendingPathComponent("thumbnail.png")
            try savePNG(image: image.value, to: thumbnailURL)
            advance("Generated thumbnail")
        }

        if project.demoPackSettings.includeTranscriptText {
            let transcriptURL = bundleURL.appendingPathComponent("transcript.txt")
            try transcriptText(for: project).write(to: transcriptURL, atomically: true, encoding: .utf8)
            advance("Wrote transcript text")
        }

        if project.demoPackSettings.includeTranscriptPDF {
            let transcriptPDFURL = bundleURL.appendingPathComponent("transcript.pdf")
            try await pdfService.generateStudyGuide(for: project, outputURL: transcriptPDFURL)
            advance("Wrote transcript PDF")
        }

        if project.demoPackSettings.includeSpeakerNotes, project.speakerNotes.hasContent {
            let notesURL = bundleURL.appendingPathComponent("speaker-notes.md")
            try speakerNotesMarkdown(for: project).write(to: notesURL, atomically: true, encoding: .utf8)
            advance("Wrote speaker notes")
        }

        if project.demoPackSettings.includeChapters {
            let chapters = chapterMarkers(for: project)
            let chaptersMarkdownURL = bundleURL.appendingPathComponent("chapters.md")
            try chapterMarkdown(chapters).write(to: chaptersMarkdownURL, atomically: true, encoding: .utf8)

            let chaptersJSONURL = bundleURL.appendingPathComponent("chapters.json")
            let chapterData = try JSONEncoder.pretty.encode(chapters)
            try chapterData.write(to: chaptersJSONURL)
            advance("Wrote chapter markers")
        }

        if project.demoPackSettings.includePublishMetadata {
            let metadata = publishMetadata(for: project)
            let metadataMarkdownURL = bundleURL.appendingPathComponent("publish-metadata.md")
            try publishMetadataMarkdown(metadata).write(to: metadataMarkdownURL, atomically: true, encoding: .utf8)

            let metadataJSONURL = bundleURL.appendingPathComponent("publish-metadata.json")
            let metadataData = try JSONEncoder.pretty.encode(metadata)
            try metadataData.write(to: metadataJSONURL)

            try metadata.title.write(
                to: bundleURL.appendingPathComponent("title.txt"),
                atomically: true,
                encoding: .utf8
            )
            try metadata.subtitle.write(
                to: bundleURL.appendingPathComponent("subtitle.txt"),
                atomically: true,
                encoding: .utf8
            )
            try metadata.description.write(
                to: bundleURL.appendingPathComponent("description.txt"),
                atomically: true,
                encoding: .utf8
            )
            try metadata.callToAction.write(
                to: bundleURL.appendingPathComponent("cta.txt"),
                atomically: true,
                encoding: .utf8
            )
            advance("Wrote publish metadata")
        }

        progressHandler("Demo pack ready", 1.0)
        return bundleURL
    }

    private func totalStepCount(for settings: DemoPackSettings) -> Int {
        var count = 1 // README
        if settings.includeLandscapeVideo { count += 1 }
        if settings.includeVerticalVariant { count += 1 }
        if settings.includeSquareVariant { count += 1 }
        if settings.includeThumbnail { count += 1 }
        if settings.includeTranscriptText { count += 1 }
        if settings.includeTranscriptPDF { count += 1 }
        if settings.includeSpeakerNotes { count += 1 }
        if settings.includeChapters { count += 1 }
        if settings.includePublishMetadata { count += 1 }
        return count
    }

    private func makeBundleURL(projectName: String, in outputDirectory: URL) -> URL {
        let safeName = projectName
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { !$0.isEmpty }
            .joined(separator: "-")
        let baseName = safeName.isEmpty ? "SaneVideo-Demo-Pack" : "\(safeName)-Demo-Pack"
        var candidate = outputDirectory.appendingPathComponent(baseName, isDirectory: true)
        var suffix = 2

        while FileManager.default.fileExists(atPath: candidate.path) {
            candidate = outputDirectory.appendingPathComponent("\(baseName)-\(suffix)", isDirectory: true)
            suffix += 1
        }

        return candidate
    }

    private func transcriptText(for project: VideoProject) -> String {
        let captions = project.timeline.tracks
            .flatMap(\.clips)
            .sorted { $0.startTime < $1.startTime }
            .flatMap(\.captions)

        guard !captions.isEmpty else {
            return "No captions generated for this project yet."
        }

        return captions.map { caption in
            "[\(timestampString(caption.startTime.seconds))] \(caption.text)"
        }.joined(separator: "\n")
    }

    private func chapterMarkers(for project: VideoProject) -> [ChapterMarker] {
        if !project.chapterMarkers.isEmpty {
            return project.chapterMarkers.sorted { $0.timestamp < $1.timestamp }
        }

        let clips = project.timeline.tracks.flatMap(\.clips).sorted { $0.startTime < $1.startTime }
        return clips.enumerated().map { index, clip in
            ChapterMarker(
                title: clip.url.deletingPathExtension().lastPathComponent.isEmpty
                    ? "Chapter \(index + 1)"
                    : clip.url.deletingPathExtension().lastPathComponent,
                timestamp: clip.startTime.seconds
            )
        }
    }

    private func publishMetadata(for project: VideoProject) -> PublishMetadata {
        var metadata = project.publishMetadata
        if metadata.title.isEmpty {
            metadata.title = project.name
        }
        if metadata.callToAction.isEmpty {
            metadata.callToAction = "Learn more"
        }
        return metadata
    }

    private func buildReadme(for project: VideoProject) -> String {
        """
        # \(project.name) Demo Pack

        This bundle was generated locally by SaneVideo.

        - Local-only export
        - No hosted share page
        - No required account system
        - No SaneApps storage dependency

        Upload or share these files using any destination you already control.
        """
    }

    private func speakerNotesMarkdown(for project: VideoProject) -> String {
        """
        # Speaker Notes

        \(project.speakerNotes.text)
        """
    }

    private func chapterMarkdown(_ chapters: [ChapterMarker]) -> String {
        if chapters.isEmpty {
            return "No chapter markers were generated."
        }

        return chapters.map {
            "- \(timestampString($0.timestamp)) \( $0.title )"
        }.joined(separator: "\n")
    }

    private func publishMetadataMarkdown(_ metadata: PublishMetadata) -> String {
        """
        # Publish Metadata

        Title: \(metadata.title)
        Subtitle: \(metadata.subtitle)
        CTA: \(metadata.callToAction)

        ## Description

        \(metadata.description)
        """
    }

    private func timestampString(_ seconds: Double) -> String {
        let total = max(Int(seconds.rounded(.down)), 0)
        return String(format: "%02d:%02d", total / 60, total % 60)
    }

    private func savePNG(image: NSImage, to url: URL) throws {
        guard let tiff = image.tiffRepresentation,
              let rep = NSBitmapImageRep(data: tiff),
              let png = rep.representation(using: .png, properties: [:]) else {
            throw ThumbnailError.frameExtractionFailed
        }
        try png.write(to: url)
    }
}

private extension JSONEncoder {
    static var pretty: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return encoder
    }
}
