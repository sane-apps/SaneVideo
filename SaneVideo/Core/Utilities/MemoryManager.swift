//
//  MemoryManager.swift
//  SaneVideo
//
//  Centralized memory pressure handling for Apple Silicon optimization
//

import Combine
import Foundation

/// Manages memory pressure and cache clearing across the app
@MainActor
@Observable
final class MemoryManager {

    private var cancellables = Set<AnyCancellable>()
    private var memorySource: DispatchSourceMemoryPressure?

    init() {
        setupMemoryPressureObserver()
    }

    // MARK: - Memory Pressure Handling

    private func setupMemoryPressureObserver() {
        // Observe memory pressure warnings
        let source = DispatchSource.makeMemoryPressureSource(eventMask: .all, queue: .main)

        source.setEventHandler { [weak self] in
            guard let self = self else { return }
            let event = source.data // Use .data instead of .mask for current event

            // Handle ONLY ONE level - prioritize critical
            if event.contains(.critical) {
                self.handleMemoryCritical()
            } else if event.contains(.warning) {
                self.handleMemoryWarning()
            }
            // .normal means pressure relieved - no action needed
        }

        source.resume()

        // Store the source to keep it alive
        memorySource = source

        AppLogger.general.info("MemoryManager: Memory pressure observer activated")
    }

    private func handleMemoryWarning() {
        AppLogger.general.warning("MemoryManager: Memory warning received - clearing caches")
        clearCaches(aggressive: false)
    }

    private func handleMemoryCritical() {
        AppLogger.general.error("MemoryManager: CRITICAL memory pressure - aggressive cache clearing")
        clearCaches(aggressive: true)

        // Show user notification
        ServiceContainer.shared.toastManager.show("⚠️ Low memory - cleared caches", type: .error)
    }

    // MARK: - Cache Clearing

    /// Clear all caches in the app
    /// - Parameter aggressive: If true, clears more aggressively
    func clearCaches(aggressive: Bool = false) {
        Task {
            // Clear thumbnail cache (always)
            await ServiceContainer.shared.thumbnailService.clearCache()

            // OPTIMIZATION: Clear waveform cache on ANY memory pressure
            // Waveforms are easily regeneratable and can consume significant memory on long timelines
            await ServiceContainer.shared.waveformService.clearCache()

            // Clear AI/Vision caches
            await ServiceContainer.shared.personSegmentationService.clearCache()

            // OPTIMIZATION: Reset FaceTrackingService sequence handler to prevent memory bloat
            // VNSequenceRequestHandler can accumulate state over many frames
            await ServiceContainer.shared.faceTrackingService.resetSequenceHandler()

            // Clear Rendering caches (Core Image/Metal)
            RenderingService.shared.ciContext.clearCaches()

            // Clear Network caches
            URLCache.shared.removeAllCachedResponses()

            if aggressive {
                // Additional aggressive cleanup if needed in the future
            }

            AppLogger.general.info("MemoryManager: Caches cleared (aggressive: \(aggressive))")
        }
    }
}
