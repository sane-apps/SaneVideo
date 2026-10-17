import Foundation

/// Sends caption requests to the engine chosen in Settings. Parakeet loads on request, or early via warmUp().
@MainActor
@Observable
final class TranscriptionCoordinator: TranscriptionCoordinatorProtocol {
    private let apple = AppleSpeechService()
    private let parakeet = ParakeetService()

    func generateCaptions(
        for videoURL: URL,
        progressHandler: (@Sendable (Int, Int, Int) -> Void)? = nil
    ) async throws -> [Caption] {
        let engine = ServiceContainer.shared.userPreferences.transcriptionEngine
        let appleAvailable = await apple.checkAvailability()
        let service: any TranscriptionServiceProtocol
        if engine == .parakeet || !appleAvailable {
            service = parakeet
        } else {
            service = apple
        }
        AppLogger.project.info("Captions: using \(String(describing: type(of: service)))")
        return try await service.generateCaptions(for: videoURL, progressHandler: progressHandler)
    }

    /// Loads Parakeet in the background so the first Clean Up does not wait ~45 s for it.
    /// Only when it is the chosen engine and already downloaded: never starts the 600 MB download.
    func warmUp() {
        guard ServiceContainer.shared.userPreferences.transcriptionEngine == .parakeet,
              ParakeetService.isDownloaded else { return }
        let parakeet = parakeet
        Task(priority: .utility) { await parakeet.warmUp() }
    }
}
