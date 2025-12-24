//
//  ProjectState+Editing.swift
//  SaneVideo
//
//  Created by SaneVideo Refactor
//

import Foundation
import CoreMedia

extension ProjectState {
    
    /// Updates captions for a specific clip.
    @MainActor
    func updateCaptions(_ newCaptions: [Caption], for clip: VideoClip) {
        guard let project = currentProject else { return }
        
        // Find and update the clip in the timeline
        for (trackIndex, track) in project.timeline.tracks.enumerated() {
            if let clipIndex = track.clips.firstIndex(where: { $0.id == clip.id }) {
                var updatedClip = clip
                updatedClip.captions = newCaptions
                
                var tracks = project.timeline.tracks
                var clips = track.clips
                clips[clipIndex] = updatedClip
                tracks[trackIndex].clips = clips
                
                var updatedProject = project
                updatedProject.timeline.tracks = tracks
                
                self.currentProject = updatedProject
                saveProject(updatedProject)
                
                AppLogger.project.info("📝 ProjectState: Updated \(newCaptions.count) captions for clip \(clip.id)")
                return
            }
        }
    }
    
    /// Removes a time range from a clip (Text-Based Editing).
    /// - Parameters:
    ///   - range: The time range to remove (in media time)
    ///   - clip: The clip to remove the range from
    ///   - rippleDelete: If true, shifts subsequent clips left (ripple delete). Default: false (only removes from this clip)
    @MainActor
    func removeRange(_ range: CMTimeRange, from clip: VideoClip, rippleDelete: Bool = false) {
        guard let project = currentProject else { return }
        
        registerUndo("Remove Range")
        
        for (trackIndex, track) in project.timeline.tracks.enumerated() {
            if let clipIndex = track.clips.firstIndex(where: { $0.id == clip.id }) {
                var updatedClip = clip
                
                // Add to removedRanges (in media time) - uses merge logic
                updatedClip.addRemovedRange(range)
                
                // Remove captions that fall within the removed range
                let removedDuration = range.duration.seconds
                updatedClip.captions = updatedClip.captions.compactMap { caption in
                    // If caption is entirely within removed range, remove it
                    if caption.startTime >= range.start && caption.endTime <= range.end {
                        return nil
                    }
                    // If caption overlaps with removed range, adjust it
                    if caption.startTime < range.end && caption.endTime > range.start {
                        // Caption overlaps - adjust start/end times
                        var adjusted = caption
                        if caption.startTime < range.start {
                            // Caption starts before removal, ends during/after
                            adjusted.endTime = min(caption.endTime, range.start)
                        } else {
                            // Caption starts during/after removal
                            adjusted.startTime = max(caption.startTime, range.end)
                            adjusted.endTime = caption.endTime
                        }
                        // Only keep if duration is reasonable
                        if adjusted.endTime > adjusted.startTime && 
                           (adjusted.endTime.seconds - adjusted.startTime.seconds) > 0.1 {
                            return adjusted
                        }
                        return nil
                    }
                    // If caption is after the removed range, shift it left
                    if caption.startTime >= range.end {
                        var shifted = caption
                        shifted.startTime = CMTimeSubtract(caption.startTime, range.duration)
                        shifted.endTime = CMTimeSubtract(caption.endTime, range.duration)
                        return shifted
                    }
                    return caption
                }
                
                var tracks = project.timeline.tracks
                var clips = track.clips
                clips[clipIndex] = updatedClip
                
                // Ripple delete: Shift subsequent clips left
                if rippleDelete {
                    let removedDurationCM = range.duration
                    for i in (clipIndex + 1)..<clips.count {
                        clips[i].startTime = CMTimeSubtract(clips[i].startTime, removedDurationCM)
                    }
                }
                
                tracks[trackIndex].clips = clips
                
                // Recalculate timeline start times
                var updatedProject = project
                updatedProject.timeline.tracks = tracks
                recalculateStartTimes(in: &updatedProject.timeline)
                
                self.currentProject = updatedProject
                saveProject(updatedProject)
                
                AppLogger.project.info("✂️ ProjectState: Removed range \(range.start.seconds)-\(range.end.seconds) from clip \(clip.id) (ripple: \(rippleDelete))")
                
                // Trigger a re-composition/re-render if necessary
                NotificationCenter.default.post(name: .clipAddedToTimeline, object: updatedProject)
                return
            }
        }
    }
    
    /// Maps a text selection range to a video time range for text-based editing
    /// - Parameters:
    ///   - textRange: The NSRange of selected text in the transcript
    ///   - clip: The clip containing the transcript
    /// - Returns: The corresponding CMTimeRange in media time, or nil if mapping fails
    @MainActor
    func textRangeToTimeRange(_ textRange: NSRange, in clip: VideoClip) -> CMTimeRange? {
        // Helper struct to avoid large tuple violation
        struct WordSegment {
            let text: String
            let startTime: CMTime
            let endTime: CMTime
            let offset: Int
        }
        
        // Build word segments from captions
        var wordSegments: [WordSegment] = []
        var currentOffset = 0
        
        for caption in clip.captions.sorted(by: { $0.startTime.seconds < $1.startTime.seconds }) {
            if let words = caption.words, !words.isEmpty {
                for word in words {
                    wordSegments.append(WordSegment(
                        text: word.text,
                        startTime: CMTime(seconds: word.start, preferredTimescale: 600),
                        endTime: CMTime(seconds: word.end, preferredTimescale: 600),
                        offset: currentOffset
                    ))
                    currentOffset += word.text.count + 1 // +1 for space
                }
            } else {
                // Fallback: estimate from caption
                let words = caption.text.split(separator: " ")
                guard !words.isEmpty else { continue }
                let wordDuration = (caption.endTime.seconds - caption.startTime.seconds) / Double(words.count)
                
                for (index, word) in words.enumerated() {
                    let startTime = caption.startTime.seconds + (Double(index) * wordDuration)
                    let endTime = startTime + wordDuration
                    wordSegments.append(WordSegment(
                        text: String(word),
                        startTime: CMTime(seconds: startTime, preferredTimescale: 600),
                        endTime: CMTime(seconds: endTime, preferredTimescale: 600),
                        offset: currentOffset
                    ))
                    currentOffset += word.count + 1
                }
            }
        }
        
        // Find segments that overlap with text range
        guard let startSegment = wordSegments.first(where: { $0.offset <= textRange.location && $0.offset + $0.text.count > textRange.location }),
              let endSegment = wordSegments.first(where: { $0.offset <= textRange.location + textRange.length && $0.offset + $0.text.count >= textRange.location + textRange.length }) else {
            return nil
        }
        
        return CMTimeRange(start: startSegment.startTime, duration: CMTimeSubtract(endSegment.endTime, startSegment.startTime))
    }
}
