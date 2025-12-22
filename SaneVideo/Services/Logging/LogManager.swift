//
//  LogManager.swift
//  SaneVideo
//
//  Created by SaneVideo Refactor
//

import Combine
import Foundation
import OSLog

@MainActor
@Observable
class LogManager {

    enum LogLevel: String, Codable {
        case debug, info, warning, error, fault
    }

    struct LogEntry: Identifiable, Equatable {
        let id = UUID()
        let date: Date
        let level: LogLevel
        let category: String
        let message: String

        var levelEmoji: String {
            switch level {
            case .fault: "🔥"
            case .error: "❌"
            case .warning: "⚠️"
            case .info: "ℹ️"
            case .debug: "🐞"
            }
        }
    }

    var logs: [LogEntry] = []
    private let maxLogs = 1000

    init() {
        // Subscribe to AppLogger
        AppLogger.onLog = { [weak self] message, level, category in
            // Convert AppLogger.LogLevel to LogManager.LogLevel
            let mappedLevel: LogLevel
            switch level {
            case .debug: mappedLevel = .debug
            case .info: mappedLevel = .info
            case .warning: mappedLevel = .warning
            case .error: mappedLevel = .error
            case .fault: mappedLevel = .fault
            }
            self?.addLog(message, level: mappedLevel, category: category)
        }
    }

    func addLog(_ message: String, level: LogLevel, category: String) {
        let entry = LogEntry(date: Date(), level: level, category: category, message: message)
        logs.append(entry)

        if logs.count > maxLogs {
            logs.removeFirst(logs.count - maxLogs)
        }
    }

    func logUserAction(_ action: String, details: String? = nil) {
        let message: String
        if let details = details {
            message = "\(action) (\(details))"
        } else {
            message = action
        }
        addLog(message, level: .info, category: "UserAction")
        AppLogger.userAction.info("\(message)")
    }

    func clearLogs() {
        logs.removeAll()
    }

    func exportLogs() -> String {
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy-MM-dd HH:mm:ss.SSS"

        return logs.map { entry in
            "[\(dateFormatter.string(from: entry.date))] [\(entry.category)] \(entry.levelEmoji) \(entry.message)"
        }.joined(separator: "\n")
    }
}
