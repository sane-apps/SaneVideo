//
//  CaptionPipelineTests.swift
//  SaneVideoTests
//
//  The engine-independent parts of captioning: grouping timed words into lines (CaptionBuilder),
//  reading word times out of SpeechAnalyzer results (AppleSpeechService.words), and pulling the
//  audio out of a clip (AudioExtractor). No speech model runs here.
//

import AVFoundation
import CoreMedia
import Foundation
@testable import SaneVideo
import Speech
import Testing

@Suite("Caption Builder")
struct CaptionBuilderTests {
    /// Words of `length` letters, 0.3 s each, back to back from `start`.
    private func words(_ texts: [String], start: Double = 0, step: Double = 0.3) -> [TimedWord] {
        texts.enumerated().map { index, text in
            TimedWord(text: text, start: start + Double(index) * step, end: start + Double(index + 1) * step)
        }
    }

    private func lines(_ captions: [Caption]) -> [String] {
        captions.map(\.text)
    }

    @Test("A short phrase becomes one caption spanning its first and last word")
    func shortPhraseIsOneCaption() throws {
        let captions = CaptionBuilder.captions(from: words(["Hello", "there", "friend"], start: 1.0))

        try #require(captions.count == 1)
        #expect(captions[0].text == "Hello there friend")
        #expect(abs(captions[0].startTime.seconds - 1.0) < 0.002)
        #expect(abs(captions[0].endTime.seconds - 1.9) < 0.002)
    }

    @Test("Words keep their own times and confidence inside the caption")
    func wordsKeepTheirTimes() throws {
        let input = [
            TimedWord(text: "one", start: 0.10, end: 0.42, confidence: 0.9),
            TimedWord(text: "two", start: 0.50, end: 0.81, confidence: 0.4)
        ]

        let captionWords = try #require(CaptionBuilder.captions(from: input).first?.words)

        #expect(captionWords.map(\.text) == ["one", "two"])
        #expect(captionWords.map(\.start) == [0.10, 0.50])
        #expect(captionWords.map(\.end) == [0.42, 0.81])
        #expect(captionWords.map(\.probability) == [0.9, 0.4])
    }

    @Test("A line is split before it would pass 42 characters")
    func splitsOnLength() {
        // Nine 4-letter words: "abcd abcd ..." reaches 44 characters at the ninth word.
        let captions = CaptionBuilder.captions(from: words(Array(repeating: "abcd", count: 9), step: 0.1))

        #expect(captions.count == 2)
        #expect(captions[0].text.count == 39)
        #expect(captions.allSatisfy { $0.text.count <= CaptionBuilder.maxCharacters })
    }

    @Test("A line is split before it would last more than 4 s")
    func splitsOnDuration() {
        // Ten short words of 0.5 s each: the ninth word ends at 4.5 s.
        let captions = CaptionBuilder.captions(from: words(Array(repeating: "go", count: 10), step: 0.5))

        #expect(captions.count == 2)
        #expect(abs(captions[0].endTime.seconds - 4.0) < 0.002)
        #expect(abs(captions[1].startTime.seconds - 4.0) < 0.002)
    }

    @Test("A pause longer than 0.6 s starts a new caption; a shorter one does not")
    func splitsOnPause() {
        let input = [
            TimedWord(text: "before", start: 0.0, end: 0.4),
            TimedWord(text: "short", start: 0.9, end: 1.2), // 0.5 s gap: same line
            TimedWord(text: "after", start: 1.9, end: 2.2) // 0.7 s gap: new line
        ]

        #expect(lines(CaptionBuilder.captions(from: input)) == ["before short", "after"])
    }

    @Test("A word ending in . ? or ! closes the caption")
    func splitsOnSentenceEnd() {
        let captions = CaptionBuilder.captions(from: words(["Done.", "Really?", "Yes!", "ok", "then"]))

        #expect(lines(captions) == ["Done.", "Really?", "Yes!", "ok then"])
    }

    @Test("Empty words are skipped and no words give no captions")
    func emptyInput() {
        #expect(CaptionBuilder.captions(from: []).isEmpty)
        #expect(lines(CaptionBuilder.captions(from: words(["", "hi", ""]))) == ["hi"])
    }
}

@Suite("Apple Speech word timing")
struct AppleSpeechWordTimingTests {
    private func run(_ text: String, from start: Double, to end: Double) -> AttributedString {
        var piece = AttributedString(text)
        piece.audioTimeRange = CMTimeRange(
            start: CMTime(seconds: start, preferredTimescale: 600),
            end: CMTime(seconds: end, preferredTimescale: 600)
        )
        return piece
    }

    @Test("Each timed run becomes words; a multi-word run splits its time evenly")
    func wordsFromTimedRuns() throws {
        var text = run("Hello", from: 0.0, to: 0.5)
        text.append(run(" big world", from: 0.6, to: 1.6))

        let words = AppleSpeechService.words(in: text)

        #expect(words.map(\.text) == ["Hello", "big", "world"])
        try #require(words.count == 3)
        #expect(abs(words[0].start - 0.0) < 0.001 && abs(words[0].end - 0.5) < 0.001)
        #expect(abs(words[1].start - 0.6) < 0.001 && abs(words[1].end - 1.1) < 0.001)
        #expect(abs(words[2].start - 1.1) < 0.001 && abs(words[2].end - 1.6) < 0.001)
    }

    @Test("Runs without a time range and whitespace-only runs are skipped")
    func untimedRunsAreSkipped() {
        var text = AttributedString("[noise] ")
        text.append(run("kept", from: 2.0, to: 2.4))
        text.append(run("   ", from: 2.4, to: 2.5))

        let words = AppleSpeechService.words(in: text)

        #expect(words.map(\.text) == ["kept"])
    }

    @Test("Run confidence carries over to its words, defaulting to 1")
    func confidenceCarriesOver() {
        var confident = run("sure", from: 0, to: 0.3)
        confident.transcriptionConfidence = 0.25
        var text = confident
        text.append(run(" plain", from: 0.3, to: 0.6))

        let words = AppleSpeechService.words(in: text)

        #expect(words.map(\.confidence) == [0.25, 1])
    }
}

@Suite("Audio extractor")
struct AudioExtractorTests {
    @Test("Extracts the sound of a clip into a readable audio file of the same length")
    func extractsAudio() async throws {
        let source = TestEnvironment.mockAssetURL

        let audioURL = try await AudioExtractor.extract(from: source)
        defer { try? FileManager.default.removeItem(at: audioURL) }

        let file = try AVAudioFile(forReading: audioURL)
        let seconds = Double(file.length) / file.processingFormat.sampleRate
        #expect(abs(seconds - 5.0) < 0.1)
    }

    @Test("A missing file and a clip without sound fail before any speech model loads")
    func rejectsMissingFileAndSilentVideo() async {
        await #expect(throws: TranscriptionError.self) {
            _ = try await AudioExtractor.extract(from: URL(fileURLWithPath: "/nonexistent/clip.mp4"))
        }
        await #expect(throws: TranscriptionError.self) {
            _ = try await AudioExtractor.extract(from: TestEnvironment.testAsset(named: "website-demo-video-call.mp4"))
        }
    }
}
