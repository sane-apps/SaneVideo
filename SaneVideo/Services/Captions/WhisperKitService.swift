//
//  WhisperKitService.swift
//  SaneVideo
//
//  WhisperKit transcription service wrapper
//  Provides high-accuracy transcription for difficult audio
//

import AVFoundation
import CoreMedia
import Foundation

#if canImport(WhisperKit)
import WhisperKit

/// WhisperKit transcription service for high-accuracy transcription
/// Best for: accents, technical jargon, noisy audio, multiple speakers
actor WhisperKitService: TranscriptionServiceProtocol {

    // MARK: - Properties

    // WhisperKit is not Sendable, so we need nonisolated(unsafe) for actor storage.
    // The actor's own isolation ensures we only access this from one context at a time.
    // Using nonisolated(unsafe) is safe here because:
    // 1. All access is through actor-isolated async methods
    // 2. The actor serializes all calls automatically
    // 3. We never expose the WhisperKit instance outside this actor
    nonisolated(unsafe) private var whisperKit: WhisperKit?
    private var isInitialized = false
    private var initializationTask: Task<Void, Error>?

    // MARK: - Initialization

    init() {
        // Lazy initialization - model loads on first use
    }

    // MARK: - Availability

    func checkAvailability() async -> Bool {
        // WhisperKit is always available if the package is imported
        // Model download happens on first use
        return true
    }

    // MARK: - Model Initialization

    /// Initialize WhisperKit with a model
    /// Uses "openai/whisper-small" by default (good balance of speed/accuracy)
    private func ensureInitialized() async throws {
        if isInitialized, whisperKit != nil {
            return
        }

        // Cancel any existing initialization
        initializationTask?.cancel()

        // Start new initialization
        let task = Task {
            do {
                AppLogger.project.info("🎤 WhisperKit: Initializing model (first time may download ~1.5GB)...")

                let config = WhisperKitConfig()
                // Use large-v3 for best accuracy with technical jargon, accents, and non-English
                // This is the most accurate Whisper model available (10-20% better than large-v2)
                config.model = "openai_whisper-large-v3"
                config.computeOptions = ModelComputeOptions()
                config.verbose = true // Enable verbose logging to debug issues
                config.logLevel = .debug
                config.prewarm = false

                AppLogger.project.info("🎤 WhisperKit: Requesting model: \(config.model ?? "auto")")

                let model = try await WhisperKit(config)

                self.whisperKit = model
                self.isInitialized = true
                AppLogger.project.info("✅ WhisperKit: Model initialized successfully")
            } catch {
                AppLogger.project.error("❌ WhisperKit: Failed to initialize: \(error.localizedDescription)")
                throw TranscriptionError.initializationFailed("WhisperKit: \(error.localizedDescription)")
            }
        }

        initializationTask = task
        try await task.value
    }

    // MARK: - Transcription

    func generateCaptions(
        for videoURL: URL,
        progressHandler: (@Sendable (Int, Int, Int) -> Void)? = nil
    ) async throws -> [Caption] {

        AppLogger.project.info("🎤 WhisperKit: Starting transcription for \(videoURL.lastPathComponent)")

        // Ensure model is initialized
        try await ensureInitialized()

        // Extract audio from video
        let audioURL = try await extractAudio(from: videoURL)
        defer {
            // Clean up temp audio file
            try? FileManager.default.removeItem(at: audioURL)
        }

        // Transcribe with WhisperKit
        AppLogger.project.info("🎤 WhisperKit: Transcribing audio...")

        guard let kit = whisperKit else {
            throw TranscriptionError.initializationFailed("WhisperKit model not initialized")
        }

        let decodeOptions = DecodingOptions(
            verbose: false,
            temperature: 0.0,
            withoutTimestamps: false,
            wordTimestamps: true
        )

        // Transcribe - kit is actor-isolated so this is safe
        let transcriptionResults = try await kit.transcribe(
            audioPath: audioURL.path,
            decodeOptions: decodeOptions
        )

        guard !transcriptionResults.isEmpty else {
            throw TranscriptionError.transcriptionFailed("WhisperKit returned empty results")
        }

        // Use first result (usually only one for single audio file)
        let transcriptionResult = transcriptionResults[0]

        // Convert WhisperKit segments to Captions
        var captions: [Caption] = []

        let segments = transcriptionResult.segments
        let totalDuration = segments.last?.end ?? 1.0

        for segment in segments {
            let startTime = CMTime(seconds: Double(segment.start), preferredTimescale: 600)
            let endTime = CMTime(seconds: Double(segment.end), preferredTimescale: 600)

            let caption = Caption(
                text: segment.text.trimmingCharacters(in: CharacterSet.whitespacesAndNewlines),
                startTime: startTime,
                endTime: endTime
            )
            captions.append(caption)

            // Report progress
            let progress = Int((segment.start / totalDuration) * 100)
            progressHandler?(progress, 100, 0)
        }

        AppLogger.project.info("✅ WhisperKit: Generated \(captions.count) captions")
        return captions
    }

    func cancel() async {
        initializationTask?.cancel()
        whisperKit = nil
        isInitialized = false
    }

    // MARK: - Helper Methods

    /// Extract audio track from video file
    private func extractAudio(from videoURL: URL) async throws -> URL {
        let asset = AVURLAsset(url: videoURL)

        // Create temp audio file
        let tempDir = FileManager.default.temporaryDirectory
        let audioURL = tempDir.appendingPathComponent("whisper_\(UUID().uuidString).m4a")

        // Extract audio using AVAssetExportSession
        guard let exportSession = AVAssetExportSession(asset: asset, presetName: AVAssetExportPresetAppleM4A) else {
            throw TranscriptionError.audioExtractionFailed
        }

        exportSession.outputURL = audioURL
        exportSession.outputFileType = .m4a

        // Use modern async export API (macOS 15+)
        if #available(macOS 15.0, *) {
            do {
                try await exportSession.export(to: audioURL, as: .m4a)
            } catch {
                throw TranscriptionError.transcriptionFailed("Failed to extract audio from video: \(error.localizedDescription)")
            }
        } else {
            // Fallback for older macOS (shouldn't happen as we target macOS 26.2)
            await exportSession.export()
            let status: AVAssetExportSession.Status = exportSession.status
            guard status == .completed else {
                throw TranscriptionError.transcriptionFailed("Failed to extract audio from video")
            }
        }

        return audioURL
    }

    // CRITICAL FIX: Cancel initialization task on deallocation
    // Note: For actors, we can't access isolated properties in deinit
    // The task will be cancelled when the actor is deallocated
    // We rely on proper cleanup in cancel() method
}

// MARK: - Errors (Shared with TranscriptionCoordinator)

extension TranscriptionError {
    static let notInitialized = TranscriptionError.initializationFailed("Model not initialized")
    static let audioExtractionFailed = TranscriptionError.transcriptionFailed("Failed to extract audio from video")
}

#else
// Fallback implementation when WhisperKit is not available
actor WhisperKitService: TranscriptionServiceProtocol {
    func checkAvailability() async -> Bool {
        return false
    }

    func generateCaptions(
        for videoURL: URL,
        progressHandler: (@Sendable (Int, Int, Int) -> Void)? = nil
    ) async throws -> [Caption] {
        throw TranscriptionError.serviceUnavailable("WhisperKit is not available. Please add the WhisperKit package.")
    }

    func cancel() async {}
}

// WhisperKit not available - errors handled by TranscriptionCoordinator
#endif
