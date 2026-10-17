import Foundation

/// Where exports go: Movies/SaneVideo/Exports, next to Recordings. The sandbox allows the Movies folder;
/// the Desktop needs a user prompt, so earlier exports silently fell back to a hidden app folder.
enum ExportDestination {
    static var folder: URL {
        let movies = FileManager.default.urls(for: .moviesDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        let folder = movies.appendingPathComponent("SaneVideo/Exports", isDirectory: true)
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        return folder
    }

    /// "Project Name 2026-10-16 at 21.43.mp4", with " 2", " 3"... if the name is taken.
    static func url(for name: String, suffix: String? = nil, ext: String) -> URL {
        let stamp = timestamp()
        let safeName = name.replacingOccurrences(of: "/", with: "-").replacingOccurrences(of: ":", with: "-")
        let base = [safeName, suffix, stamp].compactMap { $0 }.joined(separator: " ")
        var candidate = folder.appendingPathComponent("\(base).\(ext)")
        var counter = 2
        while FileManager.default.fileExists(atPath: candidate.path) {
            candidate = folder.appendingPathComponent("\(base) \(counter).\(ext)")
            counter += 1
        }
        return candidate
    }

    /// "2026-10-16 at 21.45.07": sorts by date and avoids characters Finder dislikes.
    static func timestamp(_ date: Date = Date()) -> String {
        date.formatted(.verbatim(
            "\(year: .defaultDigits)-\(month: .twoDigits)-\(day: .twoDigits) at \(hour: .twoDigits(clock: .twentyFourHour, hourCycle: .zeroBased)).\(minute: .twoDigits).\(second: .twoDigits)",
            timeZone: .current, calendar: .current))
    }
}
