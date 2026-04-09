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

    // MARK: - Model State

    /// Observable state for UI feedback during model loading
    enum ModelState: Sendable, Equatable {
        case notLoaded
        case downloading
        case ready
        case failed(String)

        static func == (lhs: ModelState, rhs: ModelState) -> Bool {
            switch (lhs, rhs) {
            case (.notLoaded, .notLoaded), (.downloading, .downloading), (.ready, .ready):
                return true
            case (.failed(let a), .failed(let b)):
                return a == b
            default:
                return false
            }
        }
    }

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
    private var isTranscribing = false

    /// Current model loading state - observable for UI
    private(set) var modelState: ModelState = .notLoaded

    /// Callback for state changes (called on MainActor)
    private var stateChangeHandler: (@MainActor (ModelState) -> Void)?

    // MARK: - Initialization

    init() {
        // Lazy initialization - model loads on first use or via preload
    }

    /// Set a handler to be called when model state changes
    func setStateChangeHandler(_ handler: @escaping @MainActor (ModelState) -> Void) {
        stateChangeHandler = handler
    }

    /// Notify UI of state change
    private func updateState(_ newState: ModelState) {
        modelState = newState
        if let handler = stateChangeHandler {
            Task { @MainActor in
                handler(newState)
            }
        }
    }

    // MARK: - Background Preload

    /// Background preload - call from ServiceContainer on app launch
    /// Non-blocking, non-fatal, uses low priority
    func preloadModelInBackground() {
        guard !isInitialized, initializationTask == nil else {
            AppLogger.project.debug("🎤 WhisperKit: Skipping preload - already initialized or in progress")
            return
        }

        AppLogger.project.info("🎤 WhisperKit: Starting background model preload...")
        updateState(.downloading)

        initializationTask = Task.detached(priority: .utility) { [weak self] in
            guard let self else { return }
            do {
                try await self.initializeModel()
                await self.updateState(.ready)
                AppLogger.project.info("✅ WhisperKit: Model preloaded in background")
            } catch {
                await self.updateState(.failed(error.localizedDescription))
                AppLogger.project.debug("⚠️ WhisperKit: Background preload failed: \(error.localizedDescription)")
                // Non-fatal - will retry on first use
            }
        }
    }

    /// Shared model initialization logic
    private func initializeModel() async throws {
        AppLogger.project.info("🎤 WhisperKit: Initializing multilingual model (first time may download ~1GB)...")

        let config = WhisperKitConfig()
        // Use large-v3-turbo for multilingual support (100+ languages)
        // 6x faster than large-v3, comparable accuracy, ~954MB download
        config.model = "openai_whisper-large-v3_turbo_954MB"
        config.computeOptions = ModelComputeOptions()
        config.verbose = true
        config.logLevel = .debug
        config.prewarm = true  // Prewarm for faster first transcription

        AppLogger.project.info("🎤 WhisperKit: Requesting model: \(config.model ?? "auto")")

        let model = try await WhisperKit(config)

        self.whisperKit = model
        self.isInitialized = true
        AppLogger.project.info("✅ WhisperKit: Model initialized successfully")
    }

    // MARK: - Availability

    func checkAvailability() async -> Bool {
        // WhisperKit is always available if the package is imported
        // Model download happens on first use
        return true
    }

    // MARK: - Model Initialization

    /// Initialize WhisperKit with a model - waits for background preload if in progress
    private func ensureInitialized() async throws {
        if isInitialized, whisperKit != nil {
            return
        }

        // If background preload is in progress, wait for it
        if let existingTask = initializationTask {
            try await existingTask.value
            return
        }

        // No preload in progress - initialize synchronously
        updateState(.downloading)
        do {
            try await initializeModel()
            updateState(.ready)
        } catch {
            updateState(.failed(error.localizedDescription))
            AppLogger.project.error("❌ WhisperKit: Failed to initialize: \(error.localizedDescription)")
            throw TranscriptionError.initializationFailed("WhisperKit: \(error.localizedDescription)")
        }
    }

    // MARK: - Transcription

    func generateCaptions(
        for videoURL: URL,
        progressHandler: (@Sendable (Int, Int, Int) -> Void)? = nil
    ) async throws -> [Caption] {

        AppLogger.project.info("🎤 WhisperKit: Starting transcription for \(videoURL.lastPathComponent)")

        guard videoURL.isFileURL else {
            throw TranscriptionError.transcriptionFailed("WhisperKit requires a local file URL")
        }

        let normalizedVideoURL = videoURL.standardizedFileURL
        guard FileManager.default.fileExists(atPath: normalizedVideoURL.path) else {
            throw TranscriptionError.transcriptionFailed("WhisperKit source file does not exist: \(normalizedVideoURL.path)")
        }

        // Ensure model is initialized
        try await ensureInitialized()

        guard !isTranscribing else {
            throw TranscriptionError.transcriptionFailed("WhisperKit transcription already in progress")
        }
        isTranscribing = true
        defer { isTranscribing = false }

        // Extract audio from video
        let audioURL = try await extractAudio(from: normalizedVideoURL)
        defer {
            // Clean up temp audio file
            try? FileManager.default.removeItem(at: audioURL)
        }

        // Transcribe with WhisperKit
        AppLogger.project.info("🎤 WhisperKit: Transcribing audio...")

        guard let whisperKit else {
            throw TranscriptionError.initializationFailed("WhisperKit model not initialized")
        }
        // Explicitly opt this one reference out of sendability checking while the actor
        // guarantees only one transcription can run at a time for this service instance.
        nonisolated(unsafe) let currentWhisperKit = whisperKit

        let decodeOptions = DecodingOptions(
            verbose: false,
            temperature: 0.0,
            withoutTimestamps: false,
            wordTimestamps: true
        )

        let transcriptionResults = try await currentWhisperKit.transcribe(
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

            // CRITICAL FIX: Clean timestamps and special tokens from text
            var cleanedText = segment.text.trimmingCharacters(in: CharacterSet.whitespacesAndNewlines)

            // CRITICAL FIX: Remove Whisper special tokens first
            // These are control tokens like <|startoftranscript|>, <|en|>, <|endoftranscript|>, etc.
            let specialTokenPatterns = [
                #"<\|[^|>]+\|>"#,  // Matches <|anything|> - all special tokens
                #"\[BLANK_AUDIO\]"#,  // WhisperKit silence marker
                #"\[MUSIC\]"#,  // WhisperKit music marker
                #"\[APPLAUSE\]"#  // WhisperKit sound markers
            ]

            for pattern in specialTokenPatterns {
                cleanedText = cleanedText.replacingOccurrences(
                    of: pattern,
                    with: "",
                    options: [.regularExpression, .caseInsensitive]
                )
            }

            // Remove timestamp patterns: [00:01:23], (00:01:23), 00:01:23, etc.
            let timestampPatterns = [
                #"\[?\d{1,2}:\d{2}:\d{2}(?:\.\d+)?\]?\s*"#,  // [00:01:23] or 00:01:23
                #"\[?\d{1,2}:\d{2}\]?\s*"#,                  // [01:23] or 01:23
                #"\(\d{1,2}:\d{2}:\d{2}(?:\.\d+)?\)\s*"#    // (00:01:23)
            ]

            for pattern in timestampPatterns {
                cleanedText = cleanedText.replacingOccurrences(
                    of: pattern,
                    with: "",
                    options: [.regularExpression, .caseInsensitive]
                )
            }

            // Final trim - collapse multiple spaces
            cleanedText = cleanedText.replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
            cleanedText = cleanedText.trimmingCharacters(in: CharacterSet.whitespacesAndNewlines)

            let caption = Caption(
                text: cleanedText,
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
            // Fallback for older macOS (shouldn't happen as we target macOS 15.0+)
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
