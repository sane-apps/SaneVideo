import Foundation
import OSLog

/// Service to export application logs from the system store to a text file.
final class LogExportService: Sendable {
    
    private let subsystem = "com.sanevideo.SaneVideo"
    
    public init() {}
    
    /// Exports the last 15 minutes of logs to a temporary file.
    /// - Returns: The URL of the generated log file.
    func exportRecentLogs() throws -> URL {
        let store = try OSLogStore(scope: .currentProcessIdentifier)
        let position = store.position(timeIntervalSinceLatestBoot: -900) // Last 15 minutes
        
        let entries = try store.getEntries(at: position)
            .compactMap { $0 as? OSLogEntryLog }
            .filter { $0.subsystem == subsystem }
        
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm:ss.SSS"
        
        var logText = "--- SaneVideo Debug Logs (Last 15m) ---\n"
        logText += "Exported: \(Date())\n\n"
        
        for entry in entries {
            let timestamp = formatter.string(from: entry.date)
            let level = levelString(entry.level)
            logText += "[\(timestamp)] [\(entry.category)] [\(level)] \(entry.composedMessage)\n"
        }
        
        let fileName = "SaneVideo_Export.log"

        // Save to ~/Library/Logs/SaneVideo/ (standard log location, no entitlement needed)
        // External tools like Claude Code can read from this location easily.
        guard let libraryDir = FileManager.default.urls(for: .libraryDirectory, in: .userDomainMask).first else {
            throw NSError(domain: "LogExportService", code: -1, userInfo: [NSLocalizedDescriptionKey: "Library directory not found"])
        }
        let logDir = libraryDir.appendingPathComponent("Logs/SaneVideo")
        try FileManager.default.createDirectory(at: logDir, withIntermediateDirectories: true)
        let fileURL = logDir.appendingPathComponent(fileName)
        
        try logText.write(to: fileURL, atomically: true, encoding: .utf8)
        return fileURL
    }
    
    private func levelString(_ level: OSLogEntryLog.Level) -> String {
        switch level {
        case .debug: return "DEBUG"
        case .info: return "INFO"
        case .notice: return "NOTICE"
        case .error: return "ERROR"
        case .fault: return "FAULT"
        case .undefined: return "UNKNOWN"
        @unknown default: return "UNKNOWN"
        }
    }
}
