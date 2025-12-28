//
//  TranscriptionCoordinator.swift
//  SaneVideo
//
//  Smart transcription coordinator that manages engine selection,
//  tracks failures, and suggests alternatives
//

import AVFoundation
import Foundation

/// Smart coordinator for transcription services
/// Tracks failures and intelligently suggests alternative engines
@MainActor
@Observable
class TranscriptionCoordinator: TranscriptionCoordinatorProtocol {
    
    // MARK: - Properties
    
    private let appleService: AppleSpeechService
    private let whisperKitService: WhisperKitService
    
    /// Current selected engine (synced with UserPreferences)
    var selectedEngine: TranscriptionEngine {
        get {
            ServiceContainer.shared.userPreferences.transcriptionEngine
        }
        set {
            ServiceContainer.shared.userPreferences.transcriptionEngine = newValue
        }
    }
    
    /// Track failures per engine for smart suggestions
    private var appleFailureCount: Int = 0
    private var whisperKitFailureCount: Int = 0
    
    /// Last failure timestamp (for resetting counts)
    private var lastFailureTime: Date?
    
    /// Should suggest WhisperKit? (based on failure patterns)
    var shouldSuggestWhisperKit: Bool {
        // Suggest if Apple Speech failed 2+ times recently
        appleFailureCount >= 2
    }
    
    // MARK: - Initialization
    
    init() {
        self.appleService = AppleSpeechService()
        self.whisperKitService = WhisperKitService()
    }
    
    // MARK: - Smart Transcription
    
    /// Generate captions with smart fallback logic
    /// - Automatically tries alternative engine if primary fails
    /// - Tracks failures to suggest better engine
    func generateCaptions(
        for videoURL: URL,
        progressHandler: (@Sendable (Int, Int, Int) -> Void)? = nil
    ) async throws -> [Caption] {
        
        // Reset failure counts if it's been a while (1 hour)
        if let lastFailure = lastFailureTime,
           Date().timeIntervalSince(lastFailure) > 3600 {
            resetFailureCounts()
        }
        
        let engine = selectedEngine
        
        do {
            // Try selected engine
            let captions = try await generateWithEngine(engine, videoURL: videoURL, progressHandler: progressHandler)
            
            // Success! Reset failure count for this engine
            if engine == .apple {
                appleFailureCount = 0
            } else {
                whisperKitFailureCount = 0
            }
            
            return captions
            
        } catch {
            // Track failure
            if engine == .apple {
                appleFailureCount += 1
                lastFailureTime = Date()
                AppLogger.project.warning("⚠️ Apple Speech failed (count: \(appleFailureCount)). Error: \(error.localizedDescription)")
                
                // Auto-fallback to WhisperKit if Apple fails
                if appleFailureCount >= 1 {
                    AppLogger.project.info("🔄 Auto-switching to WhisperKit for better accuracy...")
                    return try await generateWithEngine(.whisperKit, videoURL: videoURL, progressHandler: progressHandler)
                }
            } else {
                whisperKitFailureCount += 1
                lastFailureTime = Date()
                AppLogger.project.warning("⚠️ WhisperKit failed (count: \(whisperKitFailureCount)). Error: \(error.localizedDescription)")
            }
            
            throw error
        }
    }
    
    /// Generate captions with a specific engine
    private func generateWithEngine(
        _ engine: TranscriptionEngine,
        videoURL: URL,
        progressHandler: (@Sendable (Int, Int, Int) -> Void)?
    ) async throws -> [Caption] {
        
        let service: any TranscriptionServiceProtocol
        
        switch engine {
        case .apple:
            service = appleService
        case .whisperKit:
            service = whisperKitService
        }
        
        // Check availability
        let available = await service.checkAvailability()
        guard available else {
            throw TranscriptionError.serviceUnavailable(engine.displayName)
        }
        
        // Generate captions
        return try await service.generateCaptions(for: videoURL, progressHandler: progressHandler)
    }
    
    /// Reset failure tracking (called after successful transcription)
    func resetFailureCounts() {
        appleFailureCount = 0
        whisperKitFailureCount = 0
        lastFailureTime = nil
    }
    
    /// Manually set engine (from user selection)
    func setEngine(_ engine: TranscriptionEngine) {
        selectedEngine = engine
        resetFailureCounts()  // Reset when user manually changes
        AppLogger.project.info("🎤 Transcription engine set to: \(engine.displayName)")
    }
}

// Errors defined in TranscriptionError.swift
