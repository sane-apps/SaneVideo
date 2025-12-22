import Foundation

/// Throttles update callbacks to avoid excessive UI refreshes
/// Thread-safe via NSLock synchronization
final class ProgressTracker: @unchecked Sendable {
    private var lastUpdate: Date = .distantPast
    private let interval: TimeInterval
    private let lock = NSLock()

    init(interval: TimeInterval = 1.0) {
        self.interval = interval
    }

    func shouldUpdate() -> Bool {
        lock.lock()
        defer { lock.unlock() }
        let now = Date()
        if now.timeIntervalSince(lastUpdate) >= interval {
            lastUpdate = now
            return true
        }
        return false
    }
}
