//
//  ExportTypes.swift
//  SaneVideo
//
//  Created by SaneVideo Refactor
//

import Foundation

enum ExportError: LocalizedError {
    case alreadyExporting
    case failedToCreateSession
    case cancelled
    case invalidProject(String)
    case unknown

    var errorDescription: String? {
        switch self {
        case .alreadyExporting:
            "Export already in progress"
        case .failedToCreateSession:
            "Failed to create export session"
        case .cancelled:
            "Export was cancelled"
        case .invalidProject(let message):
            message
        case .unknown:
            "An unknown error occurred"
        }
    }
}
