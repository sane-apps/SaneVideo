import Foundation

/// Sends caption requests to the engine chosen in Settings. Models load only when captions are requested.
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
}
