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
    case parakeet = "Parakeet"
    case apple = "Apple"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .apple: "Apple (built in)"
        case .parakeet: "Parakeet"
        }
    }

    var description: String {
        switch self {
        case .apple: "Uses the speech model built into macOS, so nothing downloads. It leaves out \"um\" and \"uh\", so Remove Fillers needs Parakeet."
        case .parakeet: "Recommended. Most accurate in our tests and hears \"um\" and \"uh\", so Remove Fillers works. Downloads about 600 MB once; 25 European languages."
        }
    }

    static let `default` = TranscriptionEngine.parakeet
}
