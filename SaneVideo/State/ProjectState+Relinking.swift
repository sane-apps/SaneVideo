//
//  ProjectState+Relinking.swift
//  SaneVideo
//
//  Created by SaneVideo Refactor
//

import AVFoundation
import Foundation
import SwiftUI

extension ProjectState {

    // P0 FIX: Relink clip to new file location
    func relinkClip(_ clip: VideoClip, to newURL: URL, transactionId: UUID? = nil) {
        guard !shouldBlockOperation(transactionId: transactionId) else { return }
        guard var project = currentProject else { return }

        var timeline = project.timeline
        var clipFound = false

        for (trackIndex, track) in timeline.tracks.enumerated() {
            if let index = track.clips.firstIndex(where: { $0.id == clip.id }) {
                if track.isLocked { return }

                registerUndo("Relink Clip")

                var mutableTrack = track
                mutableTrack.clips[index].url = newURL
                mutableTrack.clips[index].isMissing = false

                // P0 FIX: Create new bookmark for new file location
                if let bookmarkData = try? ServiceContainer.shared.projectFileManager.createBookmark(
                    for: newURL)
                {
                    mutableTrack.clips[index].bookmarkData = bookmarkData
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

            // P0 FIX: Notify UI of clip update
            NotificationCenter.default.post(name: .clipUpdated, object: project)
            ServiceContainer.shared.toastManager.show("Clip relinked to new file", type: .success)
            AppLogger.project.info("Relinked clip \(clip.id) to \(newURL.lastPathComponent)")
        }
    }
}
