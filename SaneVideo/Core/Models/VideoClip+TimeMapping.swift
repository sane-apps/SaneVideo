//
//  VideoClip+TimeMapping.swift
//  SaneVideo
//
//  Created by SaneVideo Refactor
//

import AVFoundation
import Foundation

extension VideoClip {
    
    // MARK: - Time Mapping

    /// Maps a time in the "effective" (played) duration to the original asset time.
    /// Handles skipping over removed ranges.
    func originalTime(forEffectiveTime effectiveTime: CMTime) -> CMTime {
        var currentOriginal = trimStart
        var remainingEffective = effectiveTime.seconds

        // Sort removals by start time
        let sortedRemovals = removedRanges
            .map { $0.timeRange }
            .sorted { $0.start < $1.start }

        for removal in sortedRemovals {
            // Check if removal is relevant (starts after current pos)
            let removalStart = max(removal.start, currentOriginal)

            // If no gap between current and removal
            if removalStart <= currentOriginal {
                // We are inside/at removal, jump to end
                currentOriginal = max(currentOriginal, removal.end)
                continue
            }

            // Distance to next removal
            let distance = removalStart.seconds - currentOriginal.seconds

            if remainingEffective < distance {
                // Target is in this valid segment
                return CMTime(seconds: currentOriginal.seconds + remainingEffective, preferredTimescale: 600)
            }

            // Consume this valid segment
            remainingEffective -= distance
            currentOriginal = removal.end
        }

        // After all removals, add remaining
        return CMTime(seconds: currentOriginal.seconds + remainingEffective, preferredTimescale: 600)
    }

    /// Maps a time in the original asset (source time) to the "effective" (played) time.
    /// Returns nil if the time is inside a removed range.
    func effectiveTime(forOriginalTime originalTime: CMTime) -> CMTime? {
        // 1. Check bounds
        if originalTime < trimStart || originalTime > trimEnd { return nil }

        // 2. Sort removals
        let sortedRemovals = removedRanges
            .map { $0.timeRange }
            .sorted { $0.start < $1.start }

        var effectiveDurationAccumulator: Double = 0
        var currentCursor = trimStart

        let target = originalTime

        for removal in sortedRemovals {
            // Overlapping removals handling similar to validSegments calculation
            if removal.end <= currentCursor { continue } // Already passed

            // Overlap check
            let start = max(removal.start, currentCursor)

            // If target is BEFORE this removal starts
            if target < start {
                // It's in the valid segment
                let diff = target.seconds - currentCursor.seconds
                return CMTime(seconds: effectiveDurationAccumulator + diff, preferredTimescale: 600)
            }

            // If target is INSIDE this removal
            if target < removal.end {
                return nil // Inside removed range
            }

            // Add valid duration before this removal to accumulator
            let validDuration = start.seconds - currentCursor.seconds
            if validDuration > 0 {
                effectiveDurationAccumulator += validDuration
            }

            // Jump cursor
            currentCursor = max(currentCursor, removal.end)
        }

        // Final segment
        if target >= currentCursor {
            let diff = target.seconds - currentCursor.seconds
            return CMTime(seconds: effectiveDurationAccumulator + diff, preferredTimescale: 600)
        }

        return nil
    }

    // MARK: - Computed Properties

    /// Effective duration after trimming and removing internal ranges
    var effectiveDuration: CMTime {
        let safeEnd = min(trimEnd, duration)
        let safeStart = min(trimStart, safeEnd)
        var totalDuration = CMTimeSubtract(safeEnd, safeStart)

        // Subtract duration of removed ranges that overlap with the active trim range
        let trimRange = CMTimeRange(start: safeStart, duration: totalDuration)

        for range in removedRanges {
            // Convert CodableTimeRange to CMTimeRange
            let removalRange = range.timeRange

            // Interaction: Only subtract the part that is INSIDE the current trim
            let intersection = CMTimeRangeGetIntersection(trimRange, otherRange: removalRange)
            if !intersection.isEmpty {
                totalDuration = CMTimeSubtract(totalDuration, intersection.duration)
            }
        }

        return totalDuration
    }

    /// Whether the clip has been trimmed or has internal cuts
    var isTrimmed: Bool {
        trimStart != .zero || trimEnd != duration || !removedRanges.isEmpty
    }

    /// Normalized progress through clip (0.0 to 1.0)
    var trimProgress: Double {
        guard duration.seconds > 0 else { return 0 }
        return effectiveDuration.seconds / duration.seconds
    }
    
    // MARK: - Mutations
    
    /// Set trim range with validation
    mutating func setTrimRange(start: CMTime, end: CMTime) {
        let validStart = max(.zero, min(start, duration))
        let validEnd = max(validStart, min(end, duration))
        trimStart = validStart
        trimEnd = validEnd
    }

    /// Reset trim to full duration
    mutating func resetTrim() {
        trimStart = .zero
        trimEnd = duration
        removedRanges.removeAll()
    }

    /// Add a range to be removed (skipped), merging overlaps
    mutating func addRemovedRange(_ range: CMTimeRange) {
        var newRanges = removedRanges.map { $0.timeRange }
        newRanges.append(range)

        // Sort by start time
        newRanges.sort { $0.start < $1.start }

        // Coalesce overlaps
        var mergedRanges: [CMTimeRange] = []
        if let first = newRanges.first {
            var currentRange = first

            for i in 1 ..< newRanges.count {
                let nextRange = newRanges[i]

                if nextRange.start <= currentRange.end {
                    // Overlap or adjacent - merge
                    let newEnd = max(currentRange.end, nextRange.end)
                    currentRange = CMTimeRange(start: currentRange.start, end: newEnd)
                } else {
                    // No overlap - push current and start new
                    mergedRanges.append(currentRange)
                    currentRange = nextRange
                }
            }
            mergedRanges.append(currentRange)
        }

        // Update storage
        removedRanges = mergedRanges.map { CodableTimeRange($0) }
    }
}
