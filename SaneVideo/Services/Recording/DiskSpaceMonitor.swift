import Foundation

@MainActor
final class DiskSpaceMonitor {
    private let minDiskSpace: Int64 = 500 * 1024 * 1024 // 500MB
    private var monitoringTask: Task<Void, Never>?

    /// Callback triggered when disk space is critically low or check fails.
    /// Called on a background queue.
    var onLowDiskSpace: (@Sendable (Error) -> Void)?

    deinit {
        monitoringTask?.cancel()
    }

    func start() {
        stop()
        monitoringTask = Task { [weak self] in
            while !Task.isCancelled {
                guard let self = self else { return }
                self.check()
                
                // Wait 10 seconds
                try? await Task.sleep(nanoseconds: 10_000_000_000)
            }
        }
    }

    func stop() {
        monitoringTask?.cancel()
        monitoringTask = nil
    }

    // Public verification for pre-flight checks
    // Thread-safe - no state access, can be called from any context
    nonisolated func verifyDiskSpace() throws {
        guard let moviesDir = FileManager.default.urls(for: .moviesDirectory, in: .userDomainMask).first else { return }

        do {
            let values = try moviesDir.resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey])
            if let available = values.volumeAvailableCapacityForImportantUsage, available < minDiskSpace {
                throw AppError.recordingEngineError("Insufficient disk space. Please free up at least \(ByteCountFormatter.string(fromByteCount: minDiskSpace, countStyle: .file)).")
            }
        } catch let error as AppError {
            throw error
        } catch {
            AppLogger.recording.error("Failed to check disk space: \(error.localizedDescription)")
            // If we can't check, we essentially treat it as a pass but log it,
            // OR strictly throw. Original code logged error.
            // Let's rethrow wrapped to be safe.
            throw AppError.recordingEngineError("Failed to check disk space: \(error.localizedDescription)")
        }
    }

    private func check() {
        // Dispatch to background for IO
        Task.detached(priority: .utility) { [weak self] in
            guard let self = self else { return }
            do {
                try self.verifyDiskSpace()
            } catch {
                await MainActor.run {
                    AppLogger.recording.error("DiskSpaceMonitor: Low disk space detected: \(error.localizedDescription)")
                    self.onLowDiskSpace?(error)
                }
            }
        }
    }
}
