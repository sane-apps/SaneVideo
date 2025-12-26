//
//  ExportProgressTracker.swift
//  SaneVideo
//
//  Created by SaneVideo Refactor
//

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
            // Use modern async states API (macOS 15+)
            // If running on older OS, we might need fallback, but project seems to target new macOS.
            // Assuming macOS 15+ availability based on deprecation warning.
            if #available(macOS 15.0, *) {
                for await state in session.states(updateInterval: 0.1) {
                    progressSubject.send(Double(session.progress))

                    // Check if state is NOT exporting
                    if case .exporting = state {
                        continue
                    } else {
                        break
                    }
                }
            } else {
                // Fallback for older macOS if needed (using loop with sleep)
                // Since we are fixing deprecations, we assume we want the new way.
                // But to be safe, we can use a loop.
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
