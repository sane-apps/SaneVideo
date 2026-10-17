import CoreMedia
import Foundation
@testable import SaneVideo
import SwiftUI
import Testing

@Suite("Caption Tests")
@MainActor
struct CaptionTests {
    // MARK: - Draggable Captions Tests

    @Test("Caption offset undo and redo behavior")
    func captionOffsetUndo() {
        let projectState = ProjectState()
        projectState.currentProject = VideoProject(name: "Test Project")
        let undoManager = UndoManager()
        projectState.undoManager = undoManager

        let initialOffset = CGSize.zero
        let newOffset = CGSize(width: 100, height: 200)

        #expect(projectState.currentProject?.captionOffset == initialOffset)

        projectState.updateCaptionOffset(newOffset)
        #expect(projectState.currentProject?.captionOffset == newOffset)

        undoManager.undo()
        #expect(projectState.currentProject?.captionOffset == initialOffset)

        undoManager.redo()
        #expect(projectState.currentProject?.captionOffset == newOffset)
    }

    // MARK: - Font Picker Tests

    @Test("Caption font updates and defaults")
    func captionFontUpdates() {
        let projectState = ProjectState()
        projectState.currentProject = VideoProject(name: "Test Project")
        #expect(projectState.currentProject?.captionFontName == nil)

        let fontName = "Helvetica Neue"
        projectState.updateCaptionFont(fontName)
        #expect(projectState.currentProject?.captionFontName == fontName)

        projectState.updateCaptionFont(nil)
        #expect(projectState.currentProject?.captionFontName == nil)
    }

    @Test("Caption font undo behavior")
    func captionFontUndo() {
        let projectState = ProjectState()
        projectState.currentProject = VideoProject(name: "Test Project")
        let undoManager = UndoManager()
        projectState.undoManager = undoManager

        let fontName = "Impact"

        #expect(projectState.currentProject?.captionFontName == nil)

        projectState.updateCaptionFont(fontName)
        #expect(projectState.currentProject?.captionFontName == fontName)

        undoManager.undo()
        #expect(projectState.currentProject?.captionFontName == nil)
    }

    // MARK: - Caption Style Logic Tests

    @Test("Caption style font override logic")
    func captionStyleFontOverride() {
        var project = VideoProject(name: "Test Project")
        project.captionStyleName = "Classic"
        project.captionFontName = "Papyrus"

        let style = project.captionStyle
        #expect(style.fontName == "Papyrus")
    }

    @Test("Caption style reset behavior on preset change")
    func captionStyleResetOnPresetChange() throws {
        let projectState = ProjectState()
        projectState.currentProject = VideoProject(name: "Test Project")

        projectState.updateCaptionFont("Arial")
        #expect(projectState.currentProject?.captionFontName == "Arial")

        var project = try #require(projectState.currentProject)
        project.captionStyleName = "Classic"
        project.captionFontName = "Arial"

        // Change style via the computed property SETTER
        project.captionStyle = .bold

        #expect(project.captionFontName == nil)
        #expect(project.captionStyleName == "Bold")
    }

    // MARK: - Transcript Token Cleanup Tests

    @Test(
        "Caption cleanText strips model tokens, blank-audio markers and timestamps",
        arguments: [
            ("<|startoftranscript|><|en|>Hello world<|endoftranscript|>", "Hello world"),
            ("[BLANK_AUDIO] Some text here", "Some text here"),
            ("[00:01:23] Hello [00:01:25] world", "Hello world"),
            ("<|startoftranscript|><|en|>[BLANK_AUDIO][00:00:05] Hello <|0.50|> world<|endoftranscript|>", "Hello world"),
            (
                "This is a normal caption with punctuation, numbers 123, and special chars!",
                "This is a normal caption with punctuation, numbers 123, and special chars!"
            )
        ]
    )
    func captionCleanText(_ input: String, _ expected: String) {
        #expect(Caption.cleanText(input) == expected)
    }

    @Test("Caption displayText returns cleaned text")
    func captionDisplayTextReturnsCleaned() {
        let caption = Caption(
            text: "<|startoftranscript|>Hello world<|endoftranscript|>",
            startTime: .zero,
            endTime: CMTime(seconds: 1, preferredTimescale: 600)
        )
        #expect(caption.displayText == "Hello world")
    }

    @Test("SRT file numbers captions and writes hour, minute, second and millisecond times")
    func srtFile() {
        let captions = [
            Caption(text: "Hello", startTime: CMTime(seconds: 1.5, preferredTimescale: 600), endTime: CMTime(seconds: 2.25, preferredTimescale: 600)),
            Caption(text: "Again", startTime: CMTime(seconds: 3725.004, preferredTimescale: 1000), endTime: CMTime(seconds: 3726, preferredTimescale: 600))
        ]
        #expect(Caption.srt(captions) == "1\n00:00:01,500 --> 00:00:02,250\nHello\n\n2\n01:02:05,004 --> 01:02:06,000\nAgain\n")
    }

    @Test("An export with captions gets a matching .srt beside it; one without captions gets none")
    func captionFileBesideExport() throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("srt-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        var clip = VideoClip(url: URL(fileURLWithPath: "/tmp/take.mov"), duration: CMTime(seconds: 10, preferredTimescale: 600))
        clip.captions = [Caption(text: "Hello", startTime: CMTime(seconds: 1, preferredTimescale: 600), endTime: CMTime(seconds: 2, preferredTimescale: 600))]
        var project = VideoProject(name: "Talk")
        project.timeline.tracks = [Track(name: "Video", type: .video, clips: [clip], zIndex: 0)]

        let srtURL = try project.writeCaptionFile(beside: folder.appendingPathComponent("Talk.mp4"))

        #expect(srtURL?.lastPathComponent == "Talk.srt")
        let written = try String(contentsOf: try #require(srtURL), encoding: .utf8)
        #expect(written == Caption.srt(project.timelineCaptions))
        #expect(written.hasPrefix("1\n00:00:01,000 --> "))
        #expect(written.hasSuffix("\nHello\n"))
        let silent = VideoProject(name: "Quiet")
        #expect(try silent.writeCaptionFile(beside: folder.appendingPathComponent("Quiet.mp4")) == nil)
        #expect(!FileManager.default.fileExists(atPath: folder.appendingPathComponent("Quiet.srt").path))
    }
}
