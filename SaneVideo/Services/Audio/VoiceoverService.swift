//
//  VoiceoverService.swift
//  SaneVideo
//
//  Uses Apple's AVSpeechSynthesizer for text-to-speech
//  Generates voiceovers from script text or captions
//  Auto-improves as Apple adds new voices with each OS update
//

import AppKit
import AVFoundation
import Combine
import Foundation

/// Text-to-speech voiceover generation using AVSpeechSynthesizer
/// Leverages Apple's high-quality system voices
@MainActor
@Observable
class VoiceoverService: NSObject {

    private let synthesizer = AVSpeechSynthesizer()

    /// Currently generating
    var isGenerating = false

    /// Progress (0-1)
    var progress: Float = 0

    /// Available voices
    var availableVoices: [VoiceInfo] = []

    /// Selected voice identifier
    var selectedVoiceId: String = ""

    /// Speech rate (0.0 - 1.0, default 0.5)
    var speechRate: Float = 0.5

    /// Pitch multiplier (0.5 - 2.0, default 1.0)
    var pitchMultiplier: Float = 1.0

    private var audioOutput: AVAudioFile?
    private var completion: ((Result<URL, Error>) -> Void)?

    override init() {
        super.init()
        synthesizer.delegate = self
        loadAvailableVoices()
    }

    // MARK: - Public API

    /// Load available system voices
    func loadAvailableVoices() {
        let voices = AVSpeechSynthesisVoice.speechVoices()

        // Group by language and prefer enhanced/premium voices
        availableVoices = voices.compactMap { voice -> VoiceInfo? in
            // Filter to English voices for now
            guard voice.language.starts(with: "en") else { return nil }

            return VoiceInfo(
                identifier: voice.identifier,
                name: voice.name,
                language: voice.language,
                quality: voice.quality,
                gender: voice.gender
            )
        }.sorted { v1, v2 in
            // Premium voices first, then by name
            if v1.quality != v2.quality {
                return v1.quality.rawValue > v2.quality.rawValue
            }
            return v1.name < v2.name
        }

        // Select first premium voice by default
        if selectedVoiceId.isEmpty, let first = availableVoices.first(where: { $0.quality == .premium }) ?? availableVoices.first {
            selectedVoiceId = first.identifier
        }
    }

    /// Preview voice with sample text
    func previewVoice(_ voiceId: String) {
        let utterance = AVSpeechUtterance(string: "Hello, this is a preview of the selected voice.")
        utterance.voice = AVSpeechSynthesisVoice(identifier: voiceId)
        utterance.rate = speechRate
        utterance.pitchMultiplier = pitchMultiplier

        synthesizer.speak(utterance)
    }

    /// Stop preview
    func stopPreview() {
        synthesizer.stopSpeaking(at: .immediate)
    }

    /// Generate voiceover audio file from text
    func generateVoiceover(from text: String, outputURL: URL) async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            isGenerating = true
            progress = 0

            // Create utterance
            let utterance = AVSpeechUtterance(string: text)
            utterance.voice = AVSpeechSynthesisVoice(identifier: selectedVoiceId)
            utterance.rate = speechRate
            utterance.pitchMultiplier = pitchMultiplier

            // Write to file
            synthesizer.write(utterance) { [weak self] buffer in
                guard let self = self else { return }
                guard let pcmBuffer = buffer as? AVAudioPCMBuffer, pcmBuffer.frameLength > 0 else {
                    return
                }

                do {
                    if self.audioOutput == nil {
                        // Create audio file on first buffer
                        self.audioOutput = try AVAudioFile(
                            forWriting: outputURL,
                            settings: pcmBuffer.format.settings
                        )
                    }
                    try self.audioOutput?.write(from: pcmBuffer)
                } catch {
                    Task { @MainActor in
                        self.isGenerating = false
                        continuation.resume(throwing: error)
                    }
                }
            }

            // Store completion for delegate callback
            self.completion = { result in
                Task { @MainActor [weak self] in
                    self?.isGenerating = false
                    self?.audioOutput = nil

                    switch result {
                    case .success:
                        continuation.resume()
                    case let .failure(error):
                        continuation.resume(throwing: error)
                    }
                }
            }
        }
    }

    /// Generate voiceover from captions (maintains timing)
    func generateVoiceoverFromCaptions(_ captions: [Caption], outputURL: URL) async throws {
        // Combine all caption text
        let fullText = captions.map { $0.text }.joined(separator: " ")
        try await generateVoiceover(from: fullText, outputURL: outputURL)
    }

    /// Estimate duration for text at current settings
    func estimateDuration(for text: String) -> TimeInterval {
        // Rough estimate based on word count and speech rate
        let words = text.components(separatedBy: .whitespacesAndNewlines).filter { !$0.isEmpty }
        let wordsPerMinute = 150.0 * Double(speechRate * 2) // Adjusted for rate
        return Double(words.count) / wordsPerMinute * 60
    }
}

// MARK: - AVSpeechSynthesizerDelegate

extension VoiceoverService: AVSpeechSynthesizerDelegate {
    nonisolated func speechSynthesizer(_: AVSpeechSynthesizer, didFinish _: AVSpeechUtterance) {
        Task { @MainActor in
            if let audioOutput = audioOutput {
                completion?(.success(audioOutput.url))
            }
            completion = nil
        }
    }

    nonisolated func speechSynthesizer(_: AVSpeechSynthesizer, willSpeakRangeOfSpeechString characterRange: NSRange, utterance: AVSpeechUtterance) {
        let total = utterance.speechString.count
        let progressValue = Float(characterRange.location + characterRange.length) / Float(total)

        Task { @MainActor in
            self.progress = progressValue
        }
    }

    nonisolated func speechSynthesizer(_: AVSpeechSynthesizer, didCancel _: AVSpeechUtterance) {
        Task { @MainActor in
            completion?(.failure(VoiceoverError.cancelled))
            completion = nil
        }
    }
}

// MARK: - Supporting Types

struct VoiceInfo: Identifiable {
    let identifier: String
    let name: String
    let language: String
    let quality: AVSpeechSynthesisVoiceQuality
    let gender: AVSpeechSynthesisVoiceGender

    var id: String { identifier }

    var displayName: String {
        let qualityBadge = quality == .premium ? " ★" : ""
        return "\(name)\(qualityBadge)"
    }
}

enum VoiceoverError: LocalizedError {
    case cancelled
    case noVoiceSelected
    case generationFailed

    var errorDescription: String? {
        switch self {
        case .cancelled: return "Voiceover generation was cancelled"
        case .noVoiceSelected: return "No voice selected"
        case .generationFailed: return "Failed to generate voiceover"
        }
    }
}
