// Unified Logging hides debug and info messages by default; use `log stream` or the DEBUG file log in ~/Library/Logs/SaneVideo/.

import Foundation
import OSLog

struct SaneLogger: Sendable {
    let internalLogger: Logger
    let category: String

    init(subsystem: String, category: String) {
        internalLogger = Logger(subsystem: subsystem, category: category)
        self.category = category
    }

    // Logging methods must not create Tasks: a Task can outlive its object and crash with use-after-free.
    // File logging is the primary mechanism; onLog callback is deprecated.

    nonisolated func info(_ message: String) {
        let safeMessage = AppLogger.sanitizeForLog(message)
        internalLogger.info("\(safeMessage, privacy: .public)")
        AppLogger.writeToFile("[\(category)] INFO: \(safeMessage)")
    }

    nonisolated func debug(_ message: String) {
        let safeMessage = AppLogger.sanitizeForLog(message)
        internalLogger.debug("\(safeMessage, privacy: .public)")
        #if DEBUG
            AppLogger.writeToFile("[\(category)] DEBUG: \(safeMessage)")
        #endif
    }

    nonisolated func warning(_ message: String) {
        let safeMessage = AppLogger.sanitizeForLog(message)
        internalLogger.warning("\(safeMessage, privacy: .public)")
        AppLogger.writeToFile("[\(category)] WARNING: \(safeMessage)")
    }

    nonisolated func error(_ message: String) {
        let safeMessage = AppLogger.sanitizeForLog(message)
        internalLogger.error("\(safeMessage, privacy: .public)")
        AppLogger.writeToFile("[\(category)] ERROR: \(safeMessage)")
    }

    nonisolated func fault(_ message: String) {
        let safeMessage = AppLogger.sanitizeForLog(message)
        internalLogger.fault("\(safeMessage, privacy: .public)")
        AppLogger.writeToFile("[\(category)] FAULT: \(safeMessage)")
    }
}

enum AppLogger {
    private static let subsystem = "com.sanevideo.SaneVideo"

    enum LogLevel: Sendable {
        case debug, info, warning, error, fault
    }

    @MainActor
    static var onLog: ((String, LogLevel, String) -> Void)?

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

    static func logError(_ error: Error, category: SaneLogger = AppLogger.general) {
        if let appError = error as? AppError, appError.shouldLog {
            category.error(appError.errorDescription ?? "Unknown error")
        } else {
            category.error(error.localizedDescription)
        }
    }

    // MARK: - File Logging (Workaround for macOS Unified Logging filtering)

    private static let logDirectory: URL? = {
        guard let libraryDir = FileManager.default.urls(for: .libraryDirectory, in: .userDomainMask).first else {
            return nil
        }
        return libraryDir.appendingPathComponent("Logs/SaneVideo")
    }()

    /// Overwritten on each launch.
    private static var currentLogFile: URL? {
        guard let logDir = logDirectory else { return nil }
        try? FileManager.default.createDirectory(at: logDir, withIntermediateDirectories: true)
        return logDir.appendingPathComponent("SaneVideo_Debug.log")
    }

    private static let fileLock = NSLock()

    private nonisolated(unsafe) static var hasInitializedLog = false

    /// Release builds use unified logging unless file logging is explicitly opted in.
    #if DEBUG
        nonisolated(unsafe) static var fileLoggingEnabled = true
    #else
        nonisolated(unsafe) static var fileLoggingEnabled = ProcessInfo.processInfo.environment["SANEVIDEO_ENABLE_FILE_LOGGING"] == "1"
    #endif

    nonisolated static func sanitizeForLog(_ message: String) -> String {
        var sanitized = message.replacingOccurrences(of: NSHomeDirectory(), with: "~")
        sanitized = sanitized.replacingOccurrences(
            of: #"/Users/[^/\s]+"#,
            with: "/Users/<user>",
            options: .regularExpression
        )
        return sanitized
    }

    /// Concurrent file access crashed XCTest runs, so file logging is skipped under tests.
    private static let isRunningTests: Bool = NSClassFromString("XCTestCase") != nil

    /// First write of each session clears the file for a fresh log
    nonisolated static func writeToFile(_ message: String) {
        guard !isRunningTests else { return }

        guard fileLoggingEnabled else {
            NSLog("📝 AppLogger: fileLoggingEnabled is false")
            return
        }

        fileLock.lock()
        defer { fileLock.unlock() }

        guard let logFile = currentLogFile else {
            NSLog("📝 AppLogger: currentLogFile is nil")
            return
        }

        if !hasInitializedLog {
            NSLog("📝 AppLogger: Will write to \(logFile.path)")
        }

        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
        let timestamp = dateFormatter.string(from: Date())
        let logLine = "[\(timestamp)] \(message)\n"

        guard let data = logLine.data(using: .utf8) else { return }

        if !hasInitializedLog {
            hasInitializedLog = true
            do {
                try data.write(to: logFile)
                NSLog("📝 AppLogger: Started fresh log at \(logFile.path)")
            } catch {
                NSLog("📝 AppLogger: Failed to create log file: \(error)")
            }
            return
        }

        if let handle = try? FileHandle(forWritingTo: logFile) {
            _ = try? handle.seekToEnd()
            try? handle.write(contentsOf: data)
            try? handle.close()
        }
    }

    /// Used by SaneMaster.rb.
    static func todaysLogPath() -> String? {
        currentLogFile?.path
    }

    static func cleanupOldLogs() {
        guard let logDir = logDirectory else { return }

        let fileManager = FileManager.default
        guard let files = try? fileManager.contentsOfDirectory(at: logDir, includingPropertiesForKeys: [.creationDateKey]) else {
            return
        }

        let cutoffDate = Calendar.current.date(byAdding: .day, value: -7, to: Date()) ?? Date()

        for file in files {
            if let attrs = try? fileManager.attributesOfItem(atPath: file.path),
               let creationDate = attrs[.creationDate] as? Date,
               creationDate < cutoffDate
            {
                try? fileManager.removeItem(at: file)
            }
        }
    }
}
