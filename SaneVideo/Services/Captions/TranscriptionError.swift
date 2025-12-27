//
//  TranscriptionError.swift
//  SaneVideo
//
//  Shared error types for transcription services
//

import Foundation

/// Errors that can occur during transcription
enum TranscriptionError: LocalizedError {
    case serviceUnavailable(String)
    case initializationFailed(String)
    case transcriptionFailed(String)
    case notAuthorized
    
    var errorDescription: String? {
        switch self {
        case let .serviceUnavailable(serviceName):
            return "\(serviceName) is not available"
        case let .initializationFailed(msg):
            return "Failed to initialize: \(msg)"
        case let .transcriptionFailed(msg):
            return "Transcription failed: \(msg)"
        case .notAuthorized:
            return "Speech recognition not authorized"
        }
    }
}
