//
//  MagicFixService.swift
//  SaneVideo
//
//  Created by SaneVideo Refactor
//

import AVFoundation
import Combine
import Foundation

/// Service for performing Magic Fix operations on clips
enum MagicFixService {
    
    /// Applies a series of Magic Fix operations to a video clip.
    /// Returns a list of time ranges to KEEP (the "good" parts).
    @MainActor static func applyMagicFix(
        to clip: VideoClip,
        options: MagicFixOptions,
        progressHandler: @escaping @Sendable (Int, Int) -> Void
    ) async throws -> [CMTimeRange] {
        // Respect existing manual cuts
        var rangesToRemove: [CMTimeRange] = clip.removedRanges.map { $0.timeRange }
        let duration = clip.duration.seconds
        
        // 1. Silence Detection
        if options.removeSilence {
            do {
                // ROBUSTNESS: Add timeout (5 minutes max for silence detection) with retry
                let silenceRanges = try await retryOperation(maxAttempts: 2, initialDelay: 1.0) {
                    try await withTimeout(seconds: 300.0) {
                        try await detectSilence(
                            in: clip,
                            options: options,
                            progressHandler: { p, _ in progressHandler(Int(Double(p)/100.0 * 30.0), 100) }
                        )
                    }
                }
                rangesToRemove.append(contentsOf: silenceRanges)
            } catch {
                AppLogger.project.error("⚠️ Magic Fix: Silence detection failed after retries: \(error.localizedDescription)")
                // Continue execution - do not fail the whole process (graceful degradation)
            }
        }
        
        // 2. Filler Detection & AI Analysis
        progressHandler(30, 100)
        
        if options.removeFillers || options.autoEnhance {
            let transcript = clip.captions.sorted { $0.startTime.seconds < $1.startTime.seconds }
                .map { $0.text }
                .joined(separator: " ")
            AppLogger.project.info("✨ Magic Fix: Analyzing transcript (length: \(transcript.count))")
            
            // Linguistic Filler Detection (Fast)
            if options.removeFillers {
                let fillerRanges = await detectFillerWords(in: clip)
                AppLogger.project.info("✨ Magic Fix: Detected \(fillerRanges.count) filler ranges")
                rangesToRemove.append(contentsOf: fillerRanges)
            }
            
            // NOTE: We use on-device NaturalLanguage framework for filler detection (SmartFillerDetector)
            // Cloud AI analysis is optional and only used if explicitly enabled via API keys
            // The primary Magic Fix uses 100% on-device Apple APIs:
            // - SpeechAnalyzer for transcription
            // - NaturalLanguage for filler detection
            // - Vision framework for visual analysis
            // - Accelerate/vDSP for audio processing
            // Cloud AI is only for optional title/description generation
        }
        
        progressHandler(90, 100)
        
        let keepRanges = calculateKeepRanges(
            removals: rangesToRemove,
            duration: CMTime(seconds: duration, preferredTimescale: 600)
        )
        
        progressHandler(100, 100)
        return keepRanges
    }
    
    /// Helper to consolidate removals and invert to get KEEP ranges
    /// Internal for testing
    static func calculateKeepRanges(removals: [CMTimeRange], duration: CMTime) -> [CMTimeRange] {
        // Consolidate overlapping removal ranges
        let sortedRemovals = removals.sorted { $0.start < $1.start }
        var consolidatedRemovals: [CMTimeRange] = []
        
        if let first = sortedRemovals.first {
            var current = first
            for range in sortedRemovals.dropFirst() {
                if range.start < current.end {
                    // Overlap or adjacent
                    let newEnd = max(range.end, current.end)
                    current = CMTimeRange(start: current.start, end: newEnd)
                } else {
                    consolidatedRemovals.append(current)
                    current = range
                }
            }
            consolidatedRemovals.append(current)
        }
        
        // Invert to get KEEP ranges
        var keepRanges: [CMTimeRange] = []
        var cursor = CMTime.zero
        
        for remove in consolidatedRemovals {
            // If the removal starts after cursor, we have a keep range
            if remove.start > cursor {
                // Ensure we don't go beyond clip duration
                let end = min(remove.start, duration)
                if end > cursor {
                    keepRanges.append(CMTimeRange(start: cursor, end: end))
                }
            }
            cursor = max(cursor, remove.end)
        }
        
        // Add final segment if any duration remains
        if cursor < duration {
            keepRanges.append(CMTimeRange(start: cursor, end: duration))
        }
        
        return keepRanges
    }
    
    /// Helper to invert Keep Ranges to get Removed Ranges
    static func calculateRemovedRanges(from keepRanges: [CMTimeRange], duration: CMTime) -> [CMTimeRange] {
        var removed: [CMTimeRange] = []
        var cursor = CMTime.zero
        
        for keep in keepRanges {
            // Gap between cursor and keep.start is removed
            if keep.start > cursor {
               removed.append(CMTimeRange(start: cursor, end: keep.start))
            }
            cursor = keep.end
        }
        
        // Final gap
        if cursor < duration {
            removed.append(CMTimeRange(start: cursor, end: duration))
        }
        
        return removed
    }
    
    /// Detect and return silent ranges for a clip
    @MainActor static func detectSilence(
        in clip: VideoClip,
        options: MagicFixOptions,
        progressHandler: @escaping @Sendable (Int, Int) -> Void
    ) async throws -> [CMTimeRange] {
        let silenceDetector = ServiceContainer.shared.silenceDetector
        
        let config = SilenceDetector.Configuration(
            dbThreshold: Float(options.silenceThreshold),
            minDuration: options.minSilenceDuration
        )
        
        return try await silenceDetector.detectSilence(
            in: clip,
            config: config,
            progressHandler: { processed, total in
                progressHandler(Int((processed / total) * 100), 100)
            }
        )
    }
    
    /// Detect filler words in captions and return their time ranges
    static func detectFillerWords(in clip: VideoClip) async -> [CMTimeRange] {
        let detector = await ServiceContainer.shared.smartFillerDetector
        let words = clip.allWords
        
        // Use the smart detector for linguistic analysis
        let fillerIndices = await detector.detectFillers(in: words)
        
        var fillerRanges: [CMTimeRange] = []
        for index in fillerIndices where index < words.count {
            let word = words[index]
            fillerRanges.append(word.timeRange)
            AppLogger.project.debug("Found smart filler: '\(word.text)' at \(word.start)s")
        }
        
        // Fallback for clips with captions but NO word-level timestamps (rare with Apple Speech)
        if fillerRanges.isEmpty && !clip.captions.isEmpty && words.isEmpty {
            let fillerWords: Set<String> = [
                "um", "uh", "uhh", "umm", "hmm", "like", "you know",
                "basically", "literally", "actually", "so", "well"
            ]
            
            for caption in clip.captions {
                let cleanedText = caption.text.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
                let sentenceWords = cleanedText.components(separatedBy: .whitespacesAndNewlines)
                    .map { $0.trimmingCharacters(in: .punctuationCharacters) }
                    .filter { !$0.isEmpty }
                
                for word in sentenceWords where fillerWords.contains(word) {
                    let range = CMTimeRange(start: caption.startTime, end: caption.endTime)
                    fillerRanges.append(range)
                    break
                }
            }
        }
        
        return fillerRanges
    }
    
    /// Find highlight moments (applause, laughter) in a clip
    @MainActor static func findHighlights(in url: URL) async throws -> [AudioClassification] {
        return try await ServiceContainer.shared.soundAnalysisService.findHighlights(in: url)
    }
    
    /// Filter ranges to only those within clip's active trim window
    static func filterRangesToTrimWindow(
        ranges: [CMTimeRange],
        clip: VideoClip
    ) -> [CMTimeRange] {
        let activeRange = CMTimeRange(start: clip.trimStart, end: clip.trimEnd)
        return ranges
            .filter { $0.intersection(activeRange).duration.seconds > 0 }
            .sorted { $0.start < $1.start }
    }
}
