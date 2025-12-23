//
//  AIService+DynamicProvider.swift
//  SaneVideo
//
//  Dynamic provider selection based on API key availability
//  Defaults to on-device Apple Intelligence, falls back to cloud if keys are present
//

import Foundation

extension AIService {
    
    /// The current effective provider based on API key availability
    var effectiveProvider: AIProvider {
        // Always prefer on-device first (privacy-first)
        // Only use cloud if explicitly configured by user
        return .appleFoundation
    }
    
    /// Check if a cloud provider is available (has API key)
    func isCloudProviderAvailable(_ provider: AIProvider) async -> Bool {
        let keychain = ServiceContainer.shared.keychainService
        
        switch provider {
        case .openAI:
            let key = await keychain.retrieve(for: .openAIKey)
            return key != nil && !key!.isEmpty
        case .gemini:
            let key = await keychain.retrieve(for: .geminiKey)
            return key != nil && !key!.isEmpty
        case .appleFoundation:
            return true // Always available (on-device)
        }
    }
    
    /// Get the best available provider for a given operation
    /// Priority: Apple Intelligence (on-device) > User's preferred cloud provider
    func getBestProvider(preferredCloudProvider: AIProvider? = nil) async -> AIProvider {
        // Always prefer on-device first (privacy-first strategy)
        if await isCloudProviderAvailable(.appleFoundation) {
            return .appleFoundation
        }
        
        // Fallback to cloud if on-device not available (shouldn't happen on macOS 26+)
        if let preferred = preferredCloudProvider,
           await isCloudProviderAvailable(preferred) {
            return preferred
        }
        
        // Check for any available cloud provider
        if await isCloudProviderAvailable(.openAI) {
            return .openAI
        }
        
        if await isCloudProviderAvailable(.gemini) {
            return .gemini
        }
        
        // Final fallback (should always be available)
        return .appleFoundation
    }
    
    /// Create a provider instance for a specific operation
    /// This allows dynamic switching without recreating the entire AIService
    private func createProvider(for provider: AIProvider) -> AIModelProvider {
        switch provider {
        case .openAI:
            return OpenAIProvider()
        case .gemini:
            return GeminiProvider()
        case .appleFoundation:
            return AppleFoundationProvider()
        }
    }
    
    /// Generate title and description using the best available provider
    func generateTitleAndDescriptionWithBestProvider(transcript: String, preferredProvider: AIProvider? = nil) async throws -> AIGeneratedContent {
        let bestProvider = await getBestProvider(preferredCloudProvider: preferredProvider)
        let provider = createProvider(for: bestProvider)
        
        AppLogger.general.info("🤖 Using AI provider: \(bestProvider) for title/description generation")
        return try await provider.generateTitleAndDescription(transcript: transcript)
    }
    
    /// Analyze transcript using the best available provider
    func analyzeTranscriptWithBestProvider(transcript: String, preferredProvider: AIProvider? = nil) async throws -> MagicFixAnalysis {
        let bestProvider = await getBestProvider(preferredCloudProvider: preferredProvider)
        let provider = createProvider(for: bestProvider)
        
        AppLogger.general.info("🤖 Using AI provider: \(bestProvider) for transcript analysis")
        return try await provider.analyzeTranscriptForEdits(prompt: transcript)
    }
    
    /// Refine captions using the best available provider
    func refineCaptionsWithBestProvider(_ captions: [Caption], prompt: String, preferredProvider: AIProvider? = nil) async throws -> [Caption] {
        let bestProvider = await getBestProvider(preferredCloudProvider: preferredProvider)
        let provider = createProvider(for: bestProvider)
        
        AppLogger.general.info("🤖 Using AI provider: \(bestProvider) for caption refinement")
        return try await provider.refineCaptions(captions: captions, prompt: prompt)
    }
}

