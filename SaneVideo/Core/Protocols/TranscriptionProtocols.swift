//
//  TranscriptionProtocols.swift
//  SaneVideo
//
//  Additional protocols for transcription services to enable testability
//  Note: AppleSpeechService and WhisperKitService already conform to TranscriptionServiceProtocol
//

import AVFoundation
import Combine
import Foundation

// MARK: - TranscriptionCoordinator Protocol

/// @mockable
@MainActor
protocol TranscriptionCoordinatorProtocol: AnyObject, Sendable {
    var selectedEngine: TranscriptionEngine { get set }
    var shouldSuggestWhisperKit: Bool { get }

    func generateCaptions(
        for videoURL: URL,
        progressHandler: (@Sendable (Int, Int, Int) -> Void)?
    ) async throws -> [Caption]

    func resetFailureCounts()
    func setEngine(_ engine: TranscriptionEngine)
}

// MARK: - SoundAnalysisService Protocol

/// @mockable
protocol SoundAnalysisServiceProtocol: AnyObject, Sendable {
    var onSoundDetected: ((AudioClassification) -> Void)? { get set }

    func analyze(sampleBuffer: CMSampleBuffer)
    func startRealTimeAnalysis(format: AVAudioFormat)
    func stopRealTimeAnalysis()
}
