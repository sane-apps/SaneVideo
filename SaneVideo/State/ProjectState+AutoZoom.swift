//
//  ProjectState+AutoZoom.swift
//  SaneVideo
//
//  Auto-zoom feature: Generate keyframes from click events
//  Screen Studio style: Automatically zooms in on mouse clicks
//

import AVFoundation
import Foundation

extension ProjectState {
    
    /// Apply auto-zoom keyframes from click events
    /// - Parameter clip: The video clip to apply auto-zoom to
    func applyAutoZoom(to clip: VideoClip) async {
        guard !isProcessing else { return }
        guard let clickDataURL = clip.clickDataURL else {
            await MainActor.run {
                ServiceContainer.shared.toastManager.show("No click data found for auto-zoom", type: .info)
            }
            return
        }
        
        isProcessing = true
        
        await MainActor.run {
            ServiceContainer.shared.toastManager.show("🎯 Generating auto-zoom keyframes...")
        }
        
        defer {
            Task { @MainActor in self.isProcessing = false }
        }
        
        do {
            // Load click events from JSON
            let data = try Data(contentsOf: clickDataURL)
            let decoder = JSONDecoder()
            let clicks = try decoder.decode([ClickSample].self, from: data)
            
            guard !clicks.isEmpty else {
                await MainActor.run {
                    ServiceContainer.shared.toastManager.show("No clicks recorded for auto-zoom", type: .info)
                }
                return
            }
            
            // Generate keyframes using AutoZoomService
            let keyframes = AutoZoomService.generateAutoZoomKeyframes(
                from: clicks,
                clipDuration: clip.duration,
                config: .default
            )
            
            // Apply keyframes to clip
            await MainActor.run {
                self.applyKeyframes(keyframes, to: clip)
                ServiceContainer.shared.toastManager.show("✅ Auto-zoom applied (\(clicks.count) clicks)")
            }
            
        } catch {
            AppLogger.project.error("Auto-zoom failed: \(error)")
            await MainActor.run {
                ServiceContainer.shared.toastManager.show("Failed to apply auto-zoom: \(error.localizedDescription)", type: .error)
            }
        }
    }
    
    /// Apply keyframes to a clip (helper method)
    private func applyKeyframes(_ keyframes: KeyframeAnimation, to clip: VideoClip) {
        guard var project = currentProject else { return }
        
        var timeline = project.timeline
        var clipFound = false
        
        for (trackIndex, track) in timeline.tracks.enumerated() {
            if let index = track.clips.firstIndex(where: { $0.id == clip.id }) {
                if track.isLocked {
                    ServiceContainer.shared.toastManager.show("Track is locked", type: .error)
                    return
                }
                
                registerUndo("Apply Auto-Zoom")
                
                var mutableTrack = track
                mutableTrack.clips[index].keyframeAnimation = keyframes
                timeline.tracks[trackIndex] = mutableTrack
                clipFound = true
                break
            }
        }
        
        if clipFound {
            project.timeline = timeline
            currentProject = project
            saveProject(project)
            
            // Trigger immediate preview update
            NotificationCenter.default.post(
                name: NSNotification.Name("ProjectEffectsChanged"),
                object: project
            )
        }
    }
}

