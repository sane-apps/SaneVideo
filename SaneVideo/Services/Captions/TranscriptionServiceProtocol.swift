//
//  TranscriptionServiceProtocol.swift
//  SaneVideo
//
//  Protocol for transcription services (Apple Speech, WhisperKit, etc.)
//

import AVFoundation
import Foundation

/// @mockable
/// Protocol for transcription services
/// Allows switching between different engines (Apple Speech, WhisperKit, etc.)
protocol TranscriptionServiceProtocol: Actor {
    /// Check if the service is available
    func checkAvailability() async -> Bool
    
    /// Generate captions for a video file
    /// - Parameters:
    ///   - videoURL: URL of the video file
    ///   - progressHandler: Optional progress callback (current, total, etaSeconds)
    /// - Returns: Array of captions with timing information
    func generateCaptions(
        for videoURL: URL,
        progressHandler: (@Sendable (Int, Int, Int) -> Void)?
    ) async throws -> [Caption]
    
    /// Cancel any ongoing transcription
    func cancel() async
}

/// Transcription engine selection
enum TranscriptionEngine: String, CaseIterable, Identifiable, Codable {
    case apple = "Apple Speech"
    case whisperKit = "WhisperKit"
    
    var id: String { rawValue }
    
    var displayName: String {
        switch self {
        case .apple: return "Apple Speech"
        case .whisperKit: return "WhisperKit"
        }
    }
    
    var description: String {
        switch self {
        case .apple:
            return "Fast, native transcription using macOS built-in speech recognition"
        case .whisperKit:
            return "Highest accuracy for accents, non-English, technical jargon, and noisy audio (~1.5GB download)"
        }
    }

    var icon: String {
        switch self {
        case .apple: return "waveform"
        case .whisperKit: return "brain.head.profile"
        }
    }

    /// Default engine - WhisperKit for best accuracy
    static let `default` = TranscriptionEngine.whisperKit
}
