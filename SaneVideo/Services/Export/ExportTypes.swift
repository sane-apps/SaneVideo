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
    case timeout
    case insufficientDiskSpace(required: Int64, available: Int64)
    case unknown

    var errorDescription: String? {
        switch self {
        case .alreadyExporting:
            return "Export already in progress"
        case .failedToCreateSession:
            return "Failed to create export session"
        case .cancelled:
            return "Export was cancelled"
        case .invalidProject(let message):
            return message
        case .timeout:
            return "Export timed out - the operation took too long to complete"
        case .insufficientDiskSpace(let required, let available):
            let requiredStr = ByteCountFormatter.string(fromByteCount: required, countStyle: .file)
            let availableStr = ByteCountFormatter.string(fromByteCount: available, countStyle: .file)
            return "Insufficient disk space. Required: \(requiredStr), Available: \(availableStr)"
        case .unknown:
            return "An unknown error occurred"
        }
    }
}
