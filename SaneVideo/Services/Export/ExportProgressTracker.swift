import AVFoundation
import Combine

@MainActor
class ExportProgressTracker {
    let progressSubject = PassthroughSubject<Double, Never>()
    /// nonisolated(unsafe) allows safe cancellation from deinit on any thread
    /// (Task.cancel() is thread-safe)
    nonisolated(unsafe) private var monitoringTask: Task<Void, Never>?

    func startMonitoring(session: AVAssetExportSession) {
        stopMonitoring()

        monitoringTask = Task { @MainActor in
            // The async states API needs macOS 15+.
            if #available(macOS 15.0, *) {
                for await state in session.states(updateInterval: 0.1) {
                    progressSubject.send(Double(session.progress))

                    if case .exporting = state {
                        continue
                    } else {
                        break
                    }
                }
            } else {
                // Polling fallback for older macOS.
                while session.status == .exporting {
                    progressSubject.send(Double(session.progress))
                    try? await Task.sleep(nanoseconds: 100_000_000) // 0.1s
                }
                progressSubject.send(Double(session.progress))
            }
        }
    }

    func stopMonitoring() {
        monitoringTask?.cancel()
        monitoringTask = nil
    }

    deinit {
        // Task.cancel() is thread-safe, so we can call it from any thread in deinit
        monitoringTask?.cancel()
    }
}
