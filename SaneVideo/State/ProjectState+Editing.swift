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
    @MainActor
    func removeRange(_ range: CMTimeRange, from clip: VideoClip) {
        guard let project = currentProject else { return }
        
        for (trackIndex, track) in project.timeline.tracks.enumerated() {
            if let clipIndex = track.clips.firstIndex(where: { $0.id == clip.id }) {
                var updatedClip = clip
                
                // Add to removedRanges (in media time)
                updatedClip.removedRanges.append(CodableTimeRange(range))
                
                // Recalculate duration and update captions
                // (Assuming logic to shift following captions exists in VideoClip or here)
                
                var tracks = project.timeline.tracks
                var clips = track.clips
                clips[clipIndex] = updatedClip
                tracks[trackIndex].clips = clips
                
                var updatedProject = project
                updatedProject.timeline.tracks = tracks
                
                self.currentProject = updatedProject
                saveProject(updatedProject)
                
                AppLogger.project.info("✂️ ProjectState: Removed range \(range.start.seconds)-\(range.end.seconds) from clip \(clip.id)")
                
                // Trigger a re-composition/re-render if necessary
                NotificationCenter.default.post(name: .clipAddedToTimeline, object: updatedProject)
                return
            }
        }
    }
}
