import AVFoundation
import Foundation

extension VideoClip {
    /// Source-time ranges a short must leave out: Clean Up cuts plus anything trimmed off either end.
    var removedForShorts: [CMTimeRange] {
        var ranges = removedRanges.map(\.timeRange)
        if trimStart > .zero {
            ranges.append(CMTimeRange(start: .zero, end: trimStart))
        }
        if trimEnd < duration {
            ranges.append(CMTimeRange(start: trimEnd, end: duration))
        }
        return ranges
    }

    
    // MARK: - Time Mapping

    /// Maps a time in the "effective" (played) duration to the original asset time.
    /// Handles skipping over removed ranges.
    func originalTime(forEffectiveTime effectiveTime: CMTime) -> CMTime {
        var currentOriginal = trimStart
        var remainingEffective = effectiveTime.seconds

        let sortedRemovals = removedRanges
            .map { $0.timeRange }
            .sorted { $0.start < $1.start }

        for removal in sortedRemovals {
            let removalStart = max(removal.start, currentOriginal)

            if removalStart <= currentOriginal {
                currentOriginal = max(currentOriginal, removal.end)
                continue
            }

            let distance = removalStart.seconds - currentOriginal.seconds

            if remainingEffective < distance {
                return CMTime(seconds: currentOriginal.seconds + remainingEffective, preferredTimescale: 600)
            }

            remainingEffective -= distance
            currentOriginal = removal.end
        }

        return CMTime(seconds: currentOriginal.seconds + remainingEffective, preferredTimescale: 600)
    }

    /// Maps a time in the original asset (source time) to the "effective" (played) time.
    /// Returns nil if the time is inside a removed range.
    func effectiveTime(forOriginalTime originalTime: CMTime) -> CMTime? {
        if originalTime < trimStart || originalTime > trimEnd { return nil }

        let sortedRemovals = removedRanges
            .map { $0.timeRange }
            .sorted { $0.start < $1.start }

        var effectiveDurationAccumulator: Double = 0
        var currentCursor = trimStart

        let target = originalTime

        for removal in sortedRemovals {
            if removal.end <= currentCursor { continue }

            let start = max(removal.start, currentCursor)

            if target < start {
                let diff = target.seconds - currentCursor.seconds
                return CMTime(seconds: effectiveDurationAccumulator + diff, preferredTimescale: 600)
            }

            if target < removal.end {
                return nil
            }

            let validDuration = start.seconds - currentCursor.seconds
            if validDuration > 0 {
                effectiveDurationAccumulator += validDuration
            }

            currentCursor = max(currentCursor, removal.end)
        }

        if target >= currentCursor {
            let diff = target.seconds - currentCursor.seconds
            return CMTime(seconds: effectiveDurationAccumulator + diff, preferredTimescale: 600)
        }

        return nil
    }

    /// The source-file time playing at a timeline time inside this clip: undoes speed, then skips trims and cuts.
    func sourceTime(atTimelineTime timelineTime: CMTime) -> CMTime {
        let played = CMTimeSubtract(timelineTime, startTime)
        return originalTime(forEffectiveTime: CMTimeMultiplyByFloat64(played, multiplier: speed))
    }

    /// The timeline time where a source-file time plays; nil if it was trimmed off or cut.
    func timelineTime(forSourceTime sourceTime: CMTime) -> CMTime? {
        guard let effective = effectiveTime(forOriginalTime: sourceTime) else { return nil }
        return CMTimeAdd(startTime, CMTimeMultiplyByFloat64(effective, multiplier: 1.0 / max(speed, 0.000_1)))
    }

    /// The first source time at or after `sourceTime` that plays: a time inside a Clean Up cut or before the
    /// trim start moves to where play resumes. Word timestamps often start in the silence Clean Up cut.
    func firstPlayedSourceTime(atOrAfter sourceTime: CMTime) -> CMTime {
        var time = max(sourceTime, trimStart)
        for removal in removedRanges.map(\.timeRange).sorted(by: { $0.start < $1.start })
        where time >= removal.start && time < removal.end {
            time = removal.end
        }
        return time
    }

    /// The timeline time where a caption starts playing; nil if none of it plays.
    func timelineStart(of caption: Caption) -> CMTime? {
        guard let range = effectiveRange(for: caption) else { return nil }
        return CMTimeAdd(startTime, CMTimeMultiplyByFloat64(range.start, multiplier: 1.0 / max(speed, 0.000_1)))
    }

    // MARK: - Computed Properties

    /// Effective duration after trimming, removing internal ranges, and applying speed
    var effectiveDuration: CMTime {
        let safeEnd = min(trimEnd, duration)
        let safeStart = min(trimStart, safeEnd)
        var totalDuration = CMTimeSubtract(safeEnd, safeStart)

        // Subtract duration of removed ranges that overlap with the active trim range
        let trimRange = CMTimeRange(start: safeStart, duration: totalDuration)

        for range in removedRanges {
            let removalRange = range.timeRange

            let intersection = CMTimeRangeGetIntersection(trimRange, otherRange: removalRange)
            if !intersection.isEmpty {
                totalDuration = CMTimeSubtract(totalDuration, intersection.duration)
            }
        }

        guard speed > 0 else { return totalDuration }
        let scaledSeconds = totalDuration.seconds / speed
        return CMTime(seconds: scaledSeconds, preferredTimescale: totalDuration.timescale)
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
    
    mutating func setTrimRange(start: CMTime, end: CMTime) {
        let validStart = max(.zero, min(start, duration))
        let validEnd = max(validStart, min(end, duration))
        trimStart = validStart
        trimEnd = validEnd
    }

    mutating func resetTrim() {
        trimStart = .zero
        trimEnd = duration
        removedRanges.removeAll()
    }

    /// Add a range to be removed (skipped), merging overlaps
    mutating func addRemovedRange(_ range: CMTimeRange) {
        var newRanges = removedRanges.map { $0.timeRange }
        newRanges.append(range)

        newRanges.sort { $0.start < $1.start }

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
                    mergedRanges.append(currentRange)
                    currentRange = nextRange
                }
            }
            mergedRanges.append(currentRange)
        }

        removedRanges = mergedRanges.map { CodableTimeRange($0) }
    }

    /// Where a caption plays inside this clip's edited duration (before speed). Uses the first and last
    /// kept words, because caption edges often sit in a silence that was cut; nil if nothing plays.
    func effectiveRange(for caption: Caption) -> CMTimeRange? {
        let firstStart = caption.words?.first?.start ?? caption.startTime.seconds
        let lastEnd = caption.words?.last?.end ?? caption.endTime.seconds
        // Keep the part that plays: a caption crossing a split, a trim or a cut used to vanish entirely.
        let startSeconds = max(firstStart, trimStart.seconds)
        let endSeconds = min(max(firstStart, lastEnd - 0.02), trimEnd.seconds)
        guard startSeconds < endSeconds,
              let start = effectiveTime(forOriginalTime: playedTime(startSeconds, forward: true)),
              let finish = effectiveTime(forOriginalTime: playedTime(endSeconds, forward: false)),
              finish > start else { return nil }
        return CMTimeRange(start: start, end: finish)
    }

    /// Moves a time that falls inside a cut to the nearest edge that plays.
    private func playedTime(_ seconds: Double, forward: Bool) -> CMTime {
        for removal in removedRanges.map(\.timeRange)
        where seconds >= removal.start.seconds && seconds < removal.end.seconds {
            let edge = forward ? removal.end.seconds : max(trimStart.seconds, removal.start.seconds - 0.001)
            return CMTime(seconds: edge, preferredTimescale: 600)
        }
        return CMTime(seconds: seconds, preferredTimescale: 600)
    }
}
