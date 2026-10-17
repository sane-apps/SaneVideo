import AVFoundation
import Foundation
import Speech

/// Captions with Apple's on-device SpeechAnalyzer. macOS manages the speech model; nothing ships with the app.
actor AppleSpeechService: TranscriptionServiceProtocol {
    private var analyzer: SpeechAnalyzer?

    func checkAvailability() async -> Bool {
        SpeechTranscriber.isAvailable
    }

    func generateCaptions(
        for videoURL: URL,
        progressHandler: (@Sendable (Int, Int, Int) -> Void)? = nil
    ) async throws -> [Caption] {
        let locale = await SpeechTranscriber.supportedLocale(equivalentTo: .current) ?? Locale(identifier: "en-US")
        let transcriber = SpeechTranscriber(
            locale: locale,
            transcriptionOptions: [],
            reportingOptions: [],
            attributeOptions: [.audioTimeRange, .transcriptionConfidence]
        )
        if let install = try await AssetInventory.assetInstallationRequest(supporting: [transcriber]) {
            AppLogger.project.info("Speech: installing the \(locale.identifier) speech model")
            try await install.downloadAndInstall()
        }

        let audioURL = try await AudioExtractor.extract(from: videoURL)
        defer { try? FileManager.default.removeItem(at: audioURL) }
        let file = try AVAudioFile(forReading: audioURL)
        let duration = Double(file.length) / file.processingFormat.sampleRate

        let analyzer = SpeechAnalyzer(modules: [transcriber])
        self.analyzer = analyzer
        defer { self.analyzer = nil }

        let collect = Task {
            var words: [TimedWord] = []
            for try await result in transcriber.results {
                words += Self.words(in: result.text)
                if duration > 0 {
                    let done = min(100, Int(result.range.end.seconds / duration * 100))
                    progressHandler?(done, 100, 0)
                }
            }
            return words
        }
        try await analyzer.start(inputAudioFile: file, finishAfterFile: true)
        let words = try await collect.value
        AppLogger.project.info("Speech: \(words.count) words from \(Int(duration)) s of audio")
        return CaptionBuilder.captions(from: words)
    }

    func cancel() async {
        await analyzer?.cancelAndFinishNow()
    }

    /// Splits a result into words, each carrying the time range of the run it came from.
    static func words(in text: AttributedString) -> [TimedWord] {
        var words: [TimedWord] = []
        for run in text.runs {
            guard let range = run.audioTimeRange else { continue }
            let piece = String(text[run.range].characters).trimmingCharacters(in: .whitespacesAndNewlines)
            let tokens = piece.split(whereSeparator: \.isWhitespace).map(String.init)
            guard !tokens.isEmpty else { continue }
            let start = range.start.seconds
            let step = (range.end.seconds - start) / Double(tokens.count)
            for (index, token) in tokens.enumerated() {
                words.append(TimedWord(
                    text: token,
                    start: start + step * Double(index),
                    end: start + step * Double(index + 1),
                    confidence: run.transcriptionConfidence ?? 1
                ))
            }
        }
        return words
    }
}
