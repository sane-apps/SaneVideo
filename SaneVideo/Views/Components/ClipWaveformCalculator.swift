//
//  ClipWaveformCalculator.swift
//  SaneVideo
//
//  Created by SaneVideo Refactor
//

import CoreMedia
import Foundation

/// Calculates waveform samples and stitch markers for clips with removed ranges
enum ClipWaveformCalculator {
    
    /// Compute samples that respect removed ranges (gaps)
    static func computeStitchedSamples(
        originalSamples: [Float],
        clip: VideoClip
    ) -> [Float] {
        guard !clip.removedRanges.isEmpty else { return originalSamples }
        
        let totalSamples = originalSamples.count
        if totalSamples == 0 { return [] }
        
        var stitched: [Float] = []
        let samplesPerSecond = Double(totalSamples) / clip.duration.seconds
        
        var cursor = clip.trimStart
        let clipEnd = min(clip.trimEnd, clip.duration)
        
        let removals = clip.removedRanges
            .map { $0.timeRange }
            .sorted { $0.start < $1.start }
        
        for removal in removals {
            if removal.end <= cursor { continue }
            if removal.start >= clipEnd { break }
            
            // Keep segment before removal
            let fragmentEnd = min(removal.start, clipEnd)
            if fragmentEnd > cursor {
                let startSample = Int(cursor.seconds * samplesPerSecond)
                let endSample = Int(fragmentEnd.seconds * samplesPerSecond)
                
                if startSample < totalSamples && endSample > startSample {
                    let safeEnd = min(endSample, totalSamples)
                    stitched.append(contentsOf: originalSamples[startSample..<safeEnd])
                }
            }
            cursor = max(cursor, removal.end)
        }
        
        // Final segment
        if cursor < clipEnd {
            let startSample = Int(cursor.seconds * samplesPerSecond)
            let endSample = Int(clipEnd.seconds * samplesPerSecond)
            if startSample < totalSamples && endSample > startSample {
                let safeEnd = min(endSample, totalSamples)
                stitched.append(contentsOf: originalSamples[startSample..<safeEnd])
            }
        }
        
        return stitched
    }
    
    /// Calculate stitch marker locations (normalized 0-1)
    static func computeStitchMarkers(clip: VideoClip) -> [Double] {
        guard !clip.removedRanges.isEmpty else { return [] }
        guard clip.effectiveDuration.seconds > 0 else { return [] }
        
        var markers: [Double] = []
        var effectiveCursor: Double = 0
        var cursor = clip.trimStart
        let clipEnd = min(clip.trimEnd, clip.duration)
        
        let removals = clip.removedRanges
            .map { $0.timeRange }
            .sorted { $0.start < $1.start }
        
        for removal in removals {
            if removal.end <= cursor { continue }
            if removal.start >= clipEnd { break }
            
            // Add valid duration before this cut
            let fragmentEnd = min(removal.start, clipEnd)
            if fragmentEnd > cursor {
                effectiveCursor += (fragmentEnd.seconds - cursor.seconds)
            }
            
            // This is a cut point! Add marker
            let progress = effectiveCursor / clip.effectiveDuration.seconds
            if progress > 0 && progress < 1.0 {
                markers.append(progress)
            }
            
            cursor = max(cursor, removal.end)
        }
        
        return markers
    }
}
