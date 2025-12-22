//
//  AppLogger.swift
//  SaneVideo
//
//  Centralized logging with os.Logger

import Foundation
import OSLog

/// Safe, Sendable logger struct
struct SaneLogger: Sendable {
    let internalLogger: Logger
    let category: String

    init(subsystem: String, category: String) {
        internalLogger = Logger(subsystem: subsystem, category: category)
        self.category = category
    }

    nonisolated func info(_ message: String) {
        internalLogger.info("\(message, privacy: .public)")
        Task { @MainActor in
            AppLogger.onLog?(message, .info, category)
        }
    }

    nonisolated func debug(_ message: String) {
        internalLogger.debug("\(message, privacy: .public)")
        Task { @MainActor in
            AppLogger.onLog?(message, .debug, category)
        }
    }

    nonisolated func warning(_ message: String) {
        internalLogger.warning("\(message, privacy: .public)")
        Task { @MainActor in
            AppLogger.onLog?(message, .warning, category)
        }
    }

    nonisolated func error(_ message: String) {
        internalLogger.error("\(message, privacy: .public)")
        Task { @MainActor in
            AppLogger.onLog?(message, .error, category)
        }
    }

    nonisolated func fault(_ message: String) {
        internalLogger.fault("\(message, privacy: .public)")
        Task { @MainActor in
            AppLogger.onLog?(message, .fault, category)
        }
    }
}

/// Centralized logging for the application
enum AppLogger {
    private static let subsystem = "com.sanevideo.SaneVideo"

    enum LogLevel: Sendable {
        case debug, info, warning, error, fault
    }

    // Handler for UI logging - isolated to main actor
    @MainActor
    static var onLog: ((String, LogLevel, String) -> Void)?

    // Category-specific loggers - created once, safe to access from any context
    // Using explicit subsystem string to avoid actor isolation issues
    nonisolated static let camera = SaneLogger(subsystem: "com.sanevideo.SaneVideo", category: "Camera")
    nonisolated static let audio = SaneLogger(subsystem: "com.sanevideo.SaneVideo", category: "Audio")
    nonisolated static let recording = SaneLogger(subsystem: "com.sanevideo.SaneVideo", category: "Recording")
    nonisolated static let playback = SaneLogger(subsystem: "com.sanevideo.SaneVideo", category: "Playback")
    nonisolated static let export = SaneLogger(subsystem: "com.sanevideo.SaneVideo", category: "Export")
    nonisolated static let timeline = SaneLogger(subsystem: "com.sanevideo.SaneVideo", category: "Timeline")
    nonisolated static let project = SaneLogger(subsystem: "com.sanevideo.SaneVideo", category: "Project")
    nonisolated static let window = SaneLogger(subsystem: "com.sanevideo.SaneVideo", category: "Window")
    nonisolated static let uiLog = SaneLogger(subsystem: "com.sanevideo.SaneVideo", category: "UI")
    nonisolated static let userAction = SaneLogger(subsystem: "com.sanevideo.SaneVideo", category: "UserAction")
    nonisolated static let general = SaneLogger(subsystem: "com.sanevideo.SaneVideo", category: "General")
    nonisolated static let composition = SaneLogger(subsystem: "com.sanevideo.SaneVideo", category: "Composition")
    nonisolated static let vision = SaneLogger(subsystem: "com.sanevideo.SaneVideo", category: "Vision")

    /// Log an error with automatic AppError handling
    static func logError(_ error: Error, category: SaneLogger = AppLogger.general) {
        if let appError = error as? AppError, appError.shouldLog {
            category.error(appError.errorDescription ?? "Unknown error")
        } else {
            category.error(error.localizedDescription)
        }
    }
}
