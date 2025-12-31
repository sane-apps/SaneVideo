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

/// Transcription engine selection (WhisperKit-only for macOS 15+)
/// Legacy enum preserved for backwards compatibility with saved preferences
enum TranscriptionEngine: String, CaseIterable, Identifiable, Codable {
    case whisperKit = "WhisperKit"

    var id: String { rawValue }

    var displayName: String {
        "WhisperKit"
    }

    var description: String {
        "Industry-leading accuracy for accents, non-English, technical jargon, and noisy audio (~800MB download)"
    }

    var icon: String {
        "brain.head.profile"
    }

    /// Default engine - WhisperKit only
    static let `default` = TranscriptionEngine.whisperKit
}
