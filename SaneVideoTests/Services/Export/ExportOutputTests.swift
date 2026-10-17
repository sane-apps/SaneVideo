//
//  ExportOutputTests.swift
//  SaneVideoTests
//
//  Export file naming (ExportDestination) and native GIF export (GIFExporter), in temp folders only.
//

import AVFoundation
import Foundation
import ImageIO
@testable import SaneVideo
import Testing

@Suite("Export Destination")
struct ExportDestinationTests {
    private func date(_ year: Int, _ month: Int, _ day: Int, _ hour: Int, _ minute: Int, _ second: Int) throws -> Date {
        let components = DateComponents(year: year, month: month, day: day, hour: hour, minute: minute, second: second)
        return try #require(Calendar.current.date(from: components))
    }

    @Test("Timestamp reads yyyy-MM-dd at HH.mm.ss on a 24-hour clock, zero-padded")
    func timestampFormat() throws {
        #expect(try ExportDestination.timestamp(date(2026, 10, 16, 21, 46, 57)) == "2026-10-16 at 21.46.57")
        #expect(try ExportDestination.timestamp(date(2026, 1, 5, 9, 3, 7)) == "2026-01-05 at 09.03.07")
        #expect(try ExportDestination.timestamp(date(2026, 1, 5, 0, 0, 0)) == "2026-01-05 at 00.00.00")
    }

    @Test("File name is project name, optional suffix, then timestamp")
    func fileNaming() throws {
        let folder = try TestMedia.makeTempDirectory("ExportDestination")
        defer { try? FileManager.default.removeItem(at: folder) }
        let when = try date(2026, 10, 16, 21, 46, 57)

        let movie = ExportDestination.url(for: "Project", ext: "mp4", in: folder, date: when)
        let transcript = ExportDestination.url(for: "Project", suffix: "Transcript", ext: "pdf", in: folder, date: when)
        let unsafe = ExportDestination.url(for: "A/B:C", ext: "gif", in: folder, date: when)

        #expect(movie.lastPathComponent == "Project 2026-10-16 at 21.46.57.mp4")
        #expect(movie.deletingLastPathComponent().standardizedFileURL == folder.standardizedFileURL)
        #expect(transcript.lastPathComponent == "Project Transcript 2026-10-16 at 21.46.57.pdf")
        #expect(unsafe.lastPathComponent == "A-B-C 2026-10-16 at 21.46.57.gif")
    }

    @Test("A taken name gets \" 2\", then \" 3\"")
    func uniqueNames() throws {
        let folder = try TestMedia.makeTempDirectory("ExportDestination")
        defer { try? FileManager.default.removeItem(at: folder) }
        let when = try date(2026, 10, 16, 21, 46, 57)

        let first = ExportDestination.url(for: "Project", ext: "mp4", in: folder, date: when)
        FileManager.default.createFile(atPath: first.path, contents: Data())
        let second = ExportDestination.url(for: "Project", ext: "mp4", in: folder, date: when)
        FileManager.default.createFile(atPath: second.path, contents: Data())
        let third = ExportDestination.url(for: "Project", ext: "mp4", in: folder, date: when)

        #expect(second.lastPathComponent == "Project 2026-10-16 at 21.46.57 2.mp4")
        #expect(third.lastPathComponent == "Project 2026-10-16 at 21.46.57 3.mp4")
    }
}

@Suite("GIF Exporter")
struct GIFExporterTests {
    private struct GIFInfo {
        let frameCount: Int
        let width: Int
        let height: Int
        let loopCount: Int?
        let firstDelay: Double?
    }

    private func readGIF(_ url: URL) throws -> GIFInfo {
        let source = try #require(CGImageSourceCreateWithURL(url as CFURL, nil))
        let fileProperties = CGImageSourceCopyProperties(source, nil) as? [CFString: Any]
        let fileGIF = fileProperties?[kCGImagePropertyGIFDictionary] as? [CFString: Any]
        let frame = try #require(CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any])
        let frameGIF = frame[kCGImagePropertyGIFDictionary] as? [CFString: Any]
        return try GIFInfo(
            frameCount: CGImageSourceGetCount(source),
            width: #require(frame[kCGImagePropertyPixelWidth] as? Int),
            height: #require(frame[kCGImagePropertyPixelHeight] as? Int),
            loopCount: fileGIF?[kCGImagePropertyGIFLoopCount] as? Int,
            firstDelay: frameGIF?[kCGImagePropertyGIFDelayTime] as? Double
        )
    }

    @Test("Exports fps x duration frames at the requested width, looping forever")
    func exportsExpectedFrames() async throws {
        let folder = try TestMedia.makeTempDirectory("GIFExporter")
        defer { try? FileManager.default.removeItem(at: folder) }
        let video = folder.appendingPathComponent("source.mp4")
        try await TestMedia.writeVideo(to: video, width: 320, height: 240, fps: 30, frameCount: 60)
        let gif = folder.appendingPathComponent("out.gif")

        try await GIFExporter.export(inputURL: video, outputURL: gif, fps: 10, width: 160, startTime: 0.5, duration: 1.0)

        let info = try readGIF(gif)
        #expect(info.frameCount == 10)
        #expect(info.width == 160)
        #expect(info.height == 120)
        #expect(info.loopCount == 0)
        #expect(abs((info.firstDelay ?? 0) - 0.1) < 0.011)
    }

    @Test("A duration longer than the clip is clamped to what is left of the clip")
    func clampsDurationToClip() async throws {
        let folder = try TestMedia.makeTempDirectory("GIFExporter")
        defer { try? FileManager.default.removeItem(at: folder) }
        let video = folder.appendingPathComponent("source.mp4")
        try await TestMedia.writeVideo(to: video, width: 320, height: 240, fps: 30, frameCount: 60)
        let gif = folder.appendingPathComponent("long.gif")

        try await GIFExporter.export(inputURL: video, outputURL: gif, fps: 5, width: 160, startTime: 0, duration: 10)

        let clipSeconds = try await AVURLAsset(url: video).load(.duration).seconds
        let frames = try readGIF(gif).frameCount
        #expect(frames == Int(clipSeconds * 5))
        #expect(frames < 50, "10 s at 5 fps would be 50 frames; the 2 s clip allows about 10")
    }
}
