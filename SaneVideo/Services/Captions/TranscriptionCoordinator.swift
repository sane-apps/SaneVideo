//
//  TranscriptionCoordinator.swift
//  SaneVideo
//
//  Transcription coordinator using WhisperKit (on-device, high accuracy)
//  Simplified to WhisperKit-only for macOS 15+ compatibility
//

import AVFoundation
import Foundation

/// Transcription coordinator using WhisperKit
/// WhisperKit provides industry-leading accuracy with 100% on-device processing
@MainActor
@Observable
class TranscriptionCoordinator: TranscriptionCoordinatorProtocol {

    // MARK: - Properties

    private let whisperKitService: WhisperKitService

    /// Track failures for error reporting
    private var failureCount: Int = 0
    private var lastFailureTime: Date?

    // MARK: - Model State (for UI feedback)

    /// Current WhisperKit model state - for UI progress indication
    var modelState: WhisperKitService.ModelState {
        get async { await whisperKitService.modelState }
    }

    // MARK: - Initialization

    init() {
        self.whisperKitService = WhisperKitService()
    }

    // MARK: - Background Preload

    /// Preload WhisperKit model in background (call from ServiceContainer on app launch)
    /// Non-blocking, shows toast when ready
    func preloadWhisperKit(toastManager: ToastManager) {
        Task {
            // Set up state change handler for toast
            await whisperKitService.setStateChangeHandler { @MainActor [weak toastManager] state in
                if state == .ready {
                    toastManager?.show("AI captions ready", type: .success)
                }
            }

            // Trigger background preload
            await whisperKitService.preloadModelInBackground()
        }
    }

    // MARK: - Transcription

    /// Generate captions using WhisperKit (on-device, high accuracy)
    func generateCaptions(
        for videoURL: URL,
        progressHandler: (@Sendable (Int, Int, Int) -> Void)? = nil
    ) async throws -> [Caption] {

        // Reset failure count if it's been a while (1 hour)
        if let lastFailure = lastFailureTime,
           Date().timeIntervalSince(lastFailure) > 3600 {
            failureCount = 0
            lastFailureTime = nil
        }

        do {
            // Check availability
            let available = await whisperKitService.checkAvailability()
            guard available else {
                throw TranscriptionError.serviceUnavailable("WhisperKit")
            }

            // Generate captions
            let captions = try await whisperKitService.generateCaptions(
                for: videoURL,
                progressHandler: progressHandler
            )

            // Success - reset failure tracking
            failureCount = 0
            lastFailureTime = nil

            return captions

        } catch {
            failureCount += 1
            lastFailureTime = Date()
            AppLogger.project.warning("⚠️ WhisperKit transcription failed (attempt \(failureCount)): \(error.localizedDescription)")
            throw error
        }
    }
}
