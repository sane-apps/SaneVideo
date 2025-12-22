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
    /// - Parameter aggressive: If true, clears more aggressively (e.g., waveform cache)
    func clearCaches(aggressive: Bool = false) {
        Task {
            // Clear thumbnail and waveform caches
            await ServiceContainer.shared.timelineThumbnailService.clearCache()
            if aggressive {
                await ServiceContainer.shared.waveformService.clearCache()
            }

            // Clear AI/Vision caches
            await ServiceContainer.shared.personSegmentationService.clearCache()
            
            // Clear Rendering caches (Core Image/Metal)
            RenderingService.shared.ciContext.clearCaches()

            // Clear Cursor cache
            CursorRenderer.clearCursorCache()
            
            // Clear Network caches
            URLCache.shared.removeAllCachedResponses()

            AppLogger.general.info("MemoryManager: Caches cleared (aggressive: \(aggressive))")
        }
    }
}
