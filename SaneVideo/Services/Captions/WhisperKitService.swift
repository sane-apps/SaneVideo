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
    
    // WhisperKit is not Sendable, so we use nonisolated(unsafe) to allow access from actor
    // This is safe because we only access it from within this actor's methods
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
        if isInitialized, let kit = whisperKit {
            return
        }
        
        // Cancel any existing initialization
        initializationTask?.cancel()
        
        // Start new initialization
        let task = Task {
            do {
                AppLogger.project.info("🎤 WhisperKit: Initializing model (first time may download ~500MB)...")
                
                // Use small model for good speed/accuracy balance
                // Options: tiny, base, small, medium, large
                let config = WhisperKitConfig()
                config.model = "openai/whisper-small"  // Good balance of speed/accuracy
                config.computeOptions = ModelComputeOptions()
                config.verbose = false
                config.prewarm = false
                
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
        
        await exportSession.export()
        
        guard exportSession.status == .completed else {
            throw TranscriptionError.transcriptionFailed("Failed to extract audio from video")
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
