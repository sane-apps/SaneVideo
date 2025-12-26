//
//  ProjectState+Transitions.swift
//  SaneVideo
//
//  Created by SaneVideo Refactor
//

import AVFoundation
import Foundation
import SwiftUI

extension ProjectState {

    // MARK: - Transitions

    /// Set transition for a clip (transition INTO this clip from previous)
    func setClipTransition(clipId: UUID, transitionType: TransitionType, transactionId: UUID? = nil) {
        guard !shouldBlockOperation(transactionId: transactionId) else { return }
        guard var project = currentProject else { return }

        var timeline = project.timeline
        var clipFound = false

        for (trackIndex, track) in timeline.tracks.enumerated() {
            if let index = track.clips.firstIndex(where: { $0.id == clipId }) {
                if track.isLocked {
                    ServiceContainer.shared.toastManager.show("Track is locked", type: .error)
                    return
                }

                registerUndo("Set Transition")

                var mutableTrack = track
                if transitionType == .none {
                    mutableTrack.clips[index].transition = nil
                } else {
                    mutableTrack.clips[index].transition = VideoTransition(type: transitionType)
                }
                timeline.tracks[trackIndex] = mutableTrack
                clipFound = true
                break
            }
        }

        if clipFound {
            project.timeline = timeline
            currentProject = project
            saveProject(project)

            if transitionType == .none {
                ServiceContainer.shared.toastManager.show("Removed transition")
            } else {
                ServiceContainer.shared.toastManager.show("Added \(transitionType.displayName) transition")
            }
            AppLogger.project.info("Set transition \(transitionType.rawValue) for clip \(clipId)")
        }
    }
}
