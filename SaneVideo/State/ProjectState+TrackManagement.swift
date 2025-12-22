import AVFoundation
import Foundation
import SwiftUI

// MARK: - Track Management (Phase 2)

extension ProjectState {
    /// Add a new track to the timeline
    func addTrack(type: TrackType, name: String? = nil) {
        guard var project = currentProject else { return }

        registerUndo("Add Track")

        var timeline = project.timeline

        // Auto-generate name based on type and count
        let trackName: String
        if let name = name {
            trackName = name
        } else {
            let existingCount = timeline.tracks.filter { $0.type == type }.count
            switch type {
            case .video:
                trackName = "Video \(existingCount + 1)"
            case .audio:
                trackName = "Audio \(existingCount + 1)"
            case .overlay:
                trackName = "Overlay \(existingCount + 1)"
            }
        }

        // Calculate zIndex (higher tracks render on top)
        let maxZIndex = timeline.tracks.map(\.zIndex).max() ?? -1
        let newTrack = Track(name: trackName, type: type, zIndex: maxZIndex + 1)

        timeline.addTrack(newTrack)
        project.timeline = timeline
        currentProject = project
        saveProject(project)

        AppLogger.project.info("Added track: \(trackName)")
        ServiceContainer.shared.toastManager.show("Added \(trackName)")
    }

    /// Delete a track from the timeline
    func deleteTrack(_ track: Track) {
        guard var project = currentProject else { return }
        guard project.timeline.tracks.count > 1 else {
            ServiceContainer.shared.toastManager.show("Cannot delete the last track", type: .error)
            return
        }

        registerUndo("Delete Track")

        var timeline = project.timeline
        timeline.tracks.removeAll { $0.id == track.id }
        project.timeline = timeline
        currentProject = project
        saveProject(project)

        AppLogger.project.info("Deleted track: \(track.name)")
        ServiceContainer.shared.toastManager.show("Deleted \(track.name)")
    }

    /// Toggle mute state for a track
    func toggleTrackMute(_ track: Track) {
        guard var project = currentProject else { return }
        guard let index = project.timeline.tracks.firstIndex(where: { $0.id == track.id }) else { return }

        registerUndo("Toggle Mute")

        var timeline = project.timeline
        timeline.tracks[index].isMuted.toggle()
        let isMuted = timeline.tracks[index].isMuted

        project.timeline = timeline
        currentProject = project
        saveProject(project)

        AppLogger.project.info("Track \(track.name) muted: \(isMuted)")
        ServiceContainer.shared.toastManager.show(isMuted ? "Muted \(track.name)" : "Unmuted \(track.name)")
    }

    /// Toggle lock state for a track
    func toggleTrackLock(_ track: Track) {
        guard var project = currentProject else { return }
        guard let index = project.timeline.tracks.firstIndex(where: { $0.id == track.id }) else { return }

        registerUndo("Toggle Lock")

        var timeline = project.timeline
        timeline.tracks[index].isLocked.toggle()
        let isLocked = timeline.tracks[index].isLocked

        project.timeline = timeline
        currentProject = project
        saveProject(project)

        AppLogger.project.info("Track \(track.name) locked: \(isLocked)")
        ServiceContainer.shared.toastManager.show(isLocked ? "Locked \(track.name)" : "Unlocked \(track.name)")
    }
}
