import Combine
import Foundation

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
        let source = DispatchSource.makeMemoryPressureSource(eventMask: .all, queue: .main)

        source.setEventHandler { [weak self] in
            guard let self = self else { return }
            let event = source.data // Use .data instead of .mask for current event

            // Handle only the most severe level.
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

        ServiceContainer.shared.toastManager.show("⚠️ Low memory - cleared caches", type: .error)
    }

    // MARK: - Cache Clearing

    func clearCaches(aggressive: Bool = false) {
        Task {
            await ServiceContainer.shared.thumbnailService.clearCache()

            // Waveforms are easily regeneratable and can consume significant memory on long timelines
            await ServiceContainer.shared.waveformService.clearCache()

            await ServiceContainer.shared.personSegmentationService.clearCache()

            // VNSequenceRequestHandler can accumulate state over many frames
            await ServiceContainer.shared.faceTrackingService.resetSequenceHandler()

            RenderingService.shared.ciContext.clearCaches()

            URLCache.shared.removeAllCachedResponses()

            if aggressive {
            }

            AppLogger.general.info("MemoryManager: Caches cleared (aggressive: \(aggressive))")
        }
    }
}
