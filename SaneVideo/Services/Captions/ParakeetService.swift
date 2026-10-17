import AVFoundation
import FluidAudio
import Foundation

/// Optional engine: NVIDIA Parakeet TDT 0.6B v3 on the Neural Engine via FluidAudio.
/// Downloads about 600 MB on first use; covers 25 European languages.
actor ParakeetService: TranscriptionServiceProtocol {
    private var manager: AsrManager?

    static var isDownloaded: Bool {
        AsrModels.modelsExist(at: AsrModels.defaultCacheDirectory(for: .v3))
    }

    func checkAvailability() async -> Bool {
        true
    }

    func generateCaptions(
        for videoURL: URL,
        progressHandler: (@Sendable (Int, Int, Int) -> Void)? = nil
    ) async throws -> [Caption] {
        let manager = try await loadedManager()
        let audioURL = try await AudioExtractor.extract(from: videoURL)
        defer { try? FileManager.default.removeItem(at: audioURL) }

        var state = await TdtDecoderState.make(decoderLayers: manager.decoderLayerCount)
        let result = try await manager.transcribe(audioURL, decoderState: &state)
        progressHandler?(100, 100, 0)

        let words = buildWordTimings(from: result.tokenTimings ?? []).map {
            TimedWord(text: $0.word, start: $0.startTime, end: $0.endTime)
        }
        AppLogger.project.info("Parakeet: \(words.count) words in \(String(format: "%.1f", result.processingTime)) s")
        return CaptionBuilder.captions(from: words)
    }

    func cancel() async {
        await manager?.cleanup()
        manager = nil
    }

    private func loadedManager() async throws -> AsrManager {
        if let manager {
            return manager
        }
        AppLogger.project.info("Parakeet: loading model (downloads on first use)")
        if !Self.isDownloaded {
            await MainActor.run {
                ServiceContainer.shared.toastManager.show(
                    "Downloading the speech model (about 600 MB, one time only)...", type: .info
                )
            }
        }
        let models = try await AsrModels.downloadAndLoad(version: .v3)
        let manager = AsrManager(config: .default)
        try await manager.loadModels(models)
        self.manager = manager
        return manager
    }
}
