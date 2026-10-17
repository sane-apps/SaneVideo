import AVFoundation
import Foundation

/// A transcribed word with its time in the source audio, from any speech engine.
struct TimedWord: Equatable, Sendable {
    let text: String
    let start: Double
    let end: Double
    var confidence = 1.0
}

/// Groups timed words into short, readable caption lines.
enum CaptionBuilder {
    static let maxCharacters = 42
    static let maxDuration = 4.0
    /// A pause this long starts a new caption.
    static let pauseGap = 0.6

    static func captions(from words: [TimedWord]) -> [Caption] {
        var captions: [Caption] = []
        var line: [TimedWord] = []

        func flush() {
            guard let first = line.first, let last = line.last else { return }
            let text = line.map(\.text).joined(separator: " ")
            captions.append(Caption(
                text: text,
                startTime: CMTime(seconds: first.start, preferredTimescale: 600),
                endTime: CMTime(seconds: last.end, preferredTimescale: 600),
                words: line.map { CaptionWord(text: $0.text, start: $0.start, end: $0.end, probability: $0.confidence) }
            ))
            line.removeAll()
        }

        for word in words where !word.text.isEmpty {
            if let first = line.first, let last = line.last {
                let length = line.map(\.text.count).reduce(line.count - 1, +) + 1 + word.text.count
                let endsSentence = last.text.last.map { ".?!".contains($0) } ?? false
                if length > maxCharacters || word.end - first.start > maxDuration
                    || word.start - last.end > pauseGap || endsSentence {
                    flush()
                }
            }
            line.append(word)
        }
        flush()
        return captions
    }
}

enum AudioExtractor {
    /// Writes the audio track of a video to a temporary M4A file. The caller deletes it.
    static func extract(from videoURL: URL) async throws -> URL {
        guard videoURL.isFileURL, FileManager.default.fileExists(atPath: videoURL.path) else {
            throw TranscriptionError.transcriptionFailed("The video file is missing: \(videoURL.lastPathComponent)")
        }
        let asset = AVURLAsset(url: videoURL)
        guard try await !asset.loadTracks(withMediaType: .audio).isEmpty else {
            throw TranscriptionError.transcriptionFailed("This clip has no sound to transcribe.")
        }
        guard let session = AVAssetExportSession(asset: asset, presetName: AVAssetExportPresetAppleM4A) else {
            throw TranscriptionError.transcriptionFailed("Could not read the clip's audio.")
        }
        let audioURL = FileManager.default.temporaryDirectory.appendingPathComponent("speech-\(UUID().uuidString).m4a")
        try await session.export(to: audioURL, as: .m4a)
        return audioURL
    }
}
