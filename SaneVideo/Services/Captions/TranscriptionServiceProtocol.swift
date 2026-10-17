import AVFoundation
import Foundation

/// @mockable
protocol TranscriptionServiceProtocol: Actor {
    func checkAvailability() async -> Bool
    
    /// - Parameters:
    ///   - progressHandler: Optional progress callback (current, total, etaSeconds)
    func generateCaptions(
        for videoURL: URL,
        progressHandler: (@Sendable (Int, Int, Int) -> Void)?
    ) async throws -> [Caption]
    
    func cancel() async
}

enum TranscriptionEngine: String, CaseIterable, Identifiable, Codable {
    case parakeet = "Parakeet"
    case apple = "Apple"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .apple: "Apple (built in)"
        case .parakeet: "Parakeet"
        }
    }

    var description: String {
        switch self {
        case .apple: "Uses the speech model built into macOS, so nothing downloads. It leaves out \"um\" and \"uh\", so Remove Fillers needs Parakeet."
        case .parakeet: "Recommended. Most accurate in our tests and hears \"um\" and \"uh\", so Remove Fillers works. Downloads about 600 MB once; 25 European languages."
        }
    }

    static let `default` = TranscriptionEngine.parakeet
}
