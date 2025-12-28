//
//  MagicFixOptions.swift
//  SaneVideo
//
//  Created by SaneVideo Refactor
//

import Foundation

struct MagicFixOptions: Codable, Equatable {
    var removeSilence: Bool = true
    var removeFillers: Bool = true
    var generateCaptions: Bool = true
    var enhanceAudio: Bool = true // UX FIX: Voice isolation on by default - almost always beneficial
    var autoEnhance: Bool = false // Visual Auto-Color/Light adjustment - more subjective, keep off
    var findHighlights: Bool = false // Detect applause/laughter moments
    
    // New Super Magic Fix options
    var smartCrop: Bool = false // Auto 9:16 reframe
    var autoFraming: Bool = false // Face tracking
    var scanForText: Bool = false // OCR Analysis
    var analyzeMood: Bool = false // Sentiment-based grading
    var applyHighlightCursor: Bool = true // Cursor highlights for recordings
    var smoothJumpCuts: Bool = true // Use Morph-cut like smoothing for jump cuts
    
    // Generative AI options
    var magicRemovePeople: Bool = false // AI-based object removal
    var generativeStyle: Bool = false // Prompt-based style transfer
    
    // Silence removal settings
    var silenceThreshold: Double = -45.0 // dB (-60 sensitive, -30 aggressive)
    var minSilenceDuration: Double = 0.3 // seconds (0.1-2.0)
    
    // Presets
    static let proClean = MagicFixOptions(
        removeSilence: true,
        removeFillers: true,
        generateCaptions: true,
        enhanceAudio: true,
        autoEnhance: true,
        findHighlights: true,
        smartCrop: false,
        autoFraming: false,
        scanForText: true,
        analyzeMood: true,
        applyHighlightCursor: true,
        smoothJumpCuts: true
    )
    
    static let socialMedia = MagicFixOptions(
        removeSilence: true,
        removeFillers: true,
        generateCaptions: true,
        enhanceAudio: true,
        autoEnhance: true,
        findHighlights: true,
        smartCrop: true,
        autoFraming: true,
        scanForText: true,
        analyzeMood: true,
        applyHighlightCursor: true,
        smoothJumpCuts: true
    )

    static let minimal = MagicFixOptions(
        removeSilence: true,
        removeFillers: false,
        generateCaptions: false,
        enhanceAudio: false,
        autoEnhance: false,
        findHighlights: false,
        smartCrop: false,
        autoFraming: false,
        scanForText: false,
        analyzeMood: false,
        applyHighlightCursor: false,
        smoothJumpCuts: false
    )
    
    /// Display name for presets
    var presetName: String {
        if self == .minimal { return "Minimal Fix" }
        if self == .proClean { return "Pro Clean-up" }
        if self == .socialMedia { return "Social Media Ready" }
        return "Custom"
    }
    
    /// Description for presets
    var presetDescription: String {
        if self == .minimal {
            return "Just remove silence. Quick and simple."
        }
        if self == .proClean {
            return "Full cleanup: silence, fillers, audio enhancement, and visual polish."
        }
        if self == .socialMedia {
            return "Optimized for short-form: aggressive cuts, smart crop, and auto-framing."
        }
        return "Custom configuration"
    }
    
    // P0 FIX: Check if options are empty (no operations selected)
    var isEmpty: Bool {
        !removeSilence && !removeFillers && !generateCaptions && !enhanceAudio &&
        !autoEnhance && !findHighlights && !smartCrop && !autoFraming &&
        !scanForText && !analyzeMood && !magicRemovePeople && !generativeStyle
    }
    
    // P0 FIX: Get human-readable summary of selected options
    var summary: String {
        var parts: [String] = []
        if removeSilence { parts.append("Silence") }
        if removeFillers { parts.append("Fillers") }
        if generateCaptions { parts.append("Captions") }
        if enhanceAudio { parts.append("Audio") }
        if autoEnhance { parts.append("Color") }
        if smartCrop { parts.append("Crop") }
        if autoFraming { parts.append("Frame") }
        if parts.isEmpty {
            return "No options selected"
        }
        return parts.joined(separator: ", ")
    }
}
