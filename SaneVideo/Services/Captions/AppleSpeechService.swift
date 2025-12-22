//
//  AppleSpeechService.swift
//  SaneVideo
//
//  Modern Apple Speech Recognition service using the modular Speech API (macOS 26+)
//

import AVFoundation
import CoreMedia
import Foundation
import Speech

/// Modern Apple Speech Recognition service using the SpeechAnalyzer API (macOS 26+)
/// This replaces the legacy SFSpeechRecognizer-based chunking logic with a native,
/// high-performance analysis engine.
actor AppleSpeechService {

    // MARK: - Core Components

    /// The modern analyzer for speech content
    private var analyzer: SpeechAnalyzer?

    init() {}

    func cancel() {
        analyzer = nil
    }

    /// Check if speech recognition is available
    func checkAvailability() async -> Bool {
        return SFSpeechRecognizer.authorizationStatus() == .authorized
    }

    /// Generate captions for a video file using the modern SpeechAnalyzer API
    func generateCaptions(
        for videoURL: URL,
        progressHandler: (@Sendable (Int, Int, Int) -> Void)? = nil
    ) async throws -> [Caption] {
        
        AppLogger.project.info("🎤 Starting Modern Speech Analysis for: \(videoURL.lastPathComponent)")

        // 1. Setup Audio File and Meta
        AppLogger.project.debug("🎤 AppleSpeechService: Reading file at \(videoURL.path)")
        let audioFile: AVAudioFile
        do {
            audioFile = try AVAudioFile(forReading: videoURL)
        } catch {
            AppLogger.project.error("❌ AppleSpeechService: Failed to read audio file: \(error.localizedDescription)")
            throw error
        }
        
        let duration = Double(audioFile.length) / audioFile.fileFormat.sampleRate
        AppLogger.project.info("🎤 AppleSpeechService: File length: \(audioFile.length) frames, Duration: \(String(format: "%.2f", duration))s, Sample Rate: \(audioFile.fileFormat.sampleRate)Hz")
        
        // 2. Setup Transcriber Module
        // We use the transcription preset as it's the most common
        let transcriber = SpeechTranscriber(locale: Locale(identifier: "en-US"), preset: .transcription)
        
        // 3. Create Analyzer and start session
        // Using the designated initializer for audio files
        let analyzer = try await SpeechAnalyzer(inputAudioFile: audioFile, modules: [transcriber])
        self.analyzer = analyzer
        
        AppLogger.project.info("🎙️ Transcribing \(String(format: "%.1f", duration))s audio natively (macOS 26+ API)...")

        // 4. Process Results via a task group with a watchdog
        return try await withThrowingTaskGroup(of: [Caption].self) { group in
            // Transcription Task
            group.addTask {
                var localCaptions: [Caption] = []
                var segmentCount = 0
                
                for try await result in transcriber.results {
                    segmentCount += 1
                    let preview = String(result.text.characters.prefix(30))
                    AppLogger.project.debug("🎤 AppleSpeechService: Result segment #\(segmentCount): \"\(preview)...\" [\(String(format: "%.2f", result.range.start.seconds))s - \(String(format: "%.2f", result.range.end.seconds))s]")
                    
                    let text = String(result.text.characters)
                    let startTime = result.range.start.seconds
                    let endTime = result.range.end.seconds
                    
                    let caption = Caption(
                        text: text,
                        startTime: CMTime(seconds: startTime, preferredTimescale: 600),
                        endTime: CMTime(seconds: endTime, preferredTimescale: 600)
                    )
                    localCaptions.append(caption)
                    
                    let progress = Int((startTime / duration) * 100)
                    progressHandler?(progress, 100, 0)
                }
                return localCaptions
            }
            
            // Watchdog Task: Max of 2x duration or 60s
            let timeout = max(60.0, duration * 2.0)
            group.addTask {
                try await Task.sleep(nanoseconds: UInt64(timeout * 1_000_000_000))
                throw SpeechError.analysisFailed("Transcription timed out after \(Int(timeout))s")
            }
            
            do {
                if let first = try await group.next() {
                    group.cancelAll()
                    AppLogger.project.info("✅ SpeechAnalyzer generated \(first.count) caption segments")
                    self.analyzer = nil
                    return first
                }
                throw SpeechError.analysisFailed("No results generated")
            } catch {
                self.analyzer = nil
                group.cancelAll()
                throw error
            }
        }
    }
}

// MARK: - Modern Speech Error Types

enum SpeechError: LocalizedError {
    case notAuthorized
    case recognizerUnavailable
    case analysisFailed(String)

    var errorDescription: String? {
        switch self {
        case .notAuthorized: return "Speech recognition not authorized."
        case .recognizerUnavailable: return "Speech analyzer is not available."
        case let .analysisFailed(msg): return "Analysis failed: \(msg)"
        }
    }
}
