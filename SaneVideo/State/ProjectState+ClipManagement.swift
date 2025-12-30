//
//  ProjectState+ClipManagement.swift
//  SaneVideo
//
//  Clip editing operations (split, trim, rotate, delete, transform, speed, effects)
//  Import operations are in ProjectState+Import.swift
//

import AppKit
import AVFoundation
import CoreMedia
import Foundation
import SwiftUI

extension ProjectState {

  // MARK: - Generic Clip Addition

  func addClip(_ clip: VideoClip) {
    guard var project = currentProject else {
      startNewProject()
      addClip(clip)
      return
    }

    var timeline = project.timeline

    registerUndo("Add Clip")

    var targetTrackIndex = timeline.tracks.firstIndex { $0.type == .video }
    if targetTrackIndex == nil {
      let newTrack = Track(name: "", type: .video, zIndex: 0)
      timeline.addTrack(newTrack)
      targetTrackIndex = timeline.tracks.count - 1
    }

    guard let trackIndex = targetTrackIndex else { return }
    var track = timeline.tracks[trackIndex]

    if track.clips.count >= 100 {
      AppLogger.project.warning("Track has \(track.clips.count) clips, consider creating a new track")
      ServiceContainer.shared.toastManager.show("Track has many clips. Consider creating a new track for better performance.", type: .info)
    }

    var mutableClip = clip

    let sortedClips = track.clips.sorted { $0.startTime < $1.startTime }
    var cumulativeTime = CMTime.zero
    for existingClip in sortedClips {
      cumulativeTime = CMTimeAdd(cumulativeTime, existingClip.effectiveDuration)
    }
    mutableClip.startTime = cumulativeTime

    track.clips.append(mutableClip)
    timeline.tracks[trackIndex] = track

    recalculateStartTimes(in: &timeline)
    timeline.updateDuration()

    if !validateTimelineState(timeline) {
      AppLogger.project.error("Timeline state invalid after adding clip, rolling back")
      ServiceContainer.shared.toastManager.show("Failed to add clip: Timeline state invalid", type: .error)
      return
    }

    project.timeline = timeline
    currentProject = project
    recentlyAddedClip = mutableClip
    saveProject(project)

    AppLogger.project.info("Added clip \(clip.id) to track '\(track.name)' at \(cumulativeTime.seconds)s")
    ServiceContainer.shared.toastManager.show("Added Clip")

    NotificationCenter.default.post(name: .clipAddedToTimeline, object: project)
  }

  // MARK: - Splitting

  func splitClip(_ clip: VideoClip, atTimelineTime globalTime: CMTime, transactionId: UUID? = nil) {
    guard var project = currentProject else { return }

    guard !shouldBlockOperation(transactionId: transactionId) else {
      AppLogger.project.warning("Ignored splitClip request (Processing busy)")
      return
    }

    if isTrackLocked(for: clip) {
      ServiceContainer.shared.toastManager.show("Track is locked", type: .error)
      return
    }

    guard globalTime > clip.startTime, globalTime < (clip.startTime + clip.effectiveDuration) else {
      AppLogger.project.warning("Split time \(globalTime.seconds)s is outside clip range")
      return
    }

    let localOffset = CMTimeSubtract(globalTime, clip.startTime)
    let splitAssetTime = CMTimeAdd(clip.trimStart, localOffset)

    guard splitAssetTime > clip.trimStart, splitAssetTime < clip.trimEnd else {
      AppLogger.project.warning("Calculated split time \(splitAssetTime.seconds)s invalid for clip bounds")
      return
    }

    var firstPart = clip
    firstPart.trimEnd = splitAssetTime

    var secondPart = clip.copy(trimStart: splitAssetTime, trimEnd: clip.trimEnd)

    let firstPartEffectiveDuration = firstPart.effectiveDuration
    secondPart.startTime = CMTimeAdd(clip.startTime, firstPartEffectiveDuration)

    var timeline = project.timeline

    var splitDone = false
    for (trackIndex, track) in timeline.tracks.enumerated() {
      if let index = track.clips.firstIndex(where: { $0.id == clip.id }) {
        registerUndo("Split Clip")

        var mutableTrack = track
        mutableTrack.clips[index] = firstPart
        mutableTrack.clips.insert(secondPart, at: index + 1)
        timeline.tracks[trackIndex] = mutableTrack

        splitDone = true
        break
      }
    }

    if splitDone {
      recalculateStartTimes(in: &timeline)

      if !validateTimelineState(timeline) {
        AppLogger.project.error("Timeline state invalid after split, rolling back")
        ServiceContainer.shared.toastManager.show("Split failed: Timeline state invalid", type: .error)
        return
      }

      project.timeline = timeline
      currentProject = project
      saveProject(project)
      AppLogger.project.info("Split clip \(clip.id) at timeline \(globalTime.seconds)s (Asset: \(splitAssetTime.seconds)s)")
      ServiceContainer.shared.toastManager.show("Split Clip")
    }
  }

  // MARK: - Trimming

  func updateClipTrim(clipId: UUID, trimStart: CMTime?, trimEnd: CMTime?, startTime _: CMTime? = nil, transactionId: UUID? = nil) {
    guard !shouldBlockOperation(transactionId: transactionId) else { return }
    guard var project = currentProject else { return }

    var timeline = project.timeline
    var clipFound = false

    for (trackIndex, track) in timeline.tracks.enumerated() {
      if let index = track.clips.firstIndex(where: { $0.id == clipId }) {
        var clip = track.clips[index]

        let newStart = trimStart ?? clip.trimStart
        let newEnd = trimEnd ?? clip.trimEnd

        guard newStart < newEnd else {
          AppLogger.project.warning("Invalid trim: start (\(newStart.seconds)s) >= end (\(newEnd.seconds)s)")
          ServiceContainer.shared.toastManager.show("Invalid trim range", type: .error)
          return
        }

        guard newStart >= .zero, newEnd <= clip.duration else {
          AppLogger.project.warning("Trim range outside clip duration (duration: \(clip.duration.seconds)s)")
          ServiceContainer.shared.toastManager.show("Trim range exceeds clip duration", type: .error)
          return
        }

        let trimRange = CMTimeRange(start: newStart, duration: CMTimeSubtract(newEnd, newStart))
        for removedRange in clip.removedRanges {
          let trimEndTime = CMTimeAdd(trimRange.start, trimRange.duration)
          let removedEnd = CMTimeAdd(removedRange.timeRange.start, removedRange.timeRange.duration)
          if trimRange.start < removedEnd && removedRange.timeRange.start < trimEndTime {
            AppLogger.project.warning("Trim range conflicts with removed range: \(removedRange.timeRange.start.seconds)s-\(removedEnd.seconds)s")
            ServiceContainer.shared.toastManager.show("Trim range conflicts with removed section", type: .error)
            return
          }
        }

        clip.setTrimRange(start: newStart, end: newEnd)

        registerUndo("Trim Clip")

        var mutableTrack = track
        mutableTrack.clips[index] = clip
        timeline.tracks[trackIndex] = mutableTrack
        clipFound = true
        break
      }
    }

    if clipFound {
      recalculateStartTimes(in: &timeline)
      timeline.updateDuration()

      if !validateTimelineState(timeline) {
        AppLogger.project.error("Timeline state invalid after trim, rolling back")
        ServiceContainer.shared.toastManager.show("Trim failed: Timeline state invalid", type: .error)
        return
      }

      project.timeline = timeline
      currentProject = project
      saveProject(project)
      AppLogger.project.info("Updated trim for clip \(clipId)")
      ServiceContainer.shared.toastManager.show("Trimmed Clip")
    }
  }

  // MARK: - Rotation

  func rotateClip(_ clip: VideoClip, transactionId: UUID? = nil) {
    guard !shouldBlockOperation(transactionId: transactionId) else { return }
    guard var project = currentProject else { return }

    var timeline = project.timeline
    var clipFound = false
    var newRotationName = ""

    for (trackIndex, track) in timeline.tracks.enumerated() {
      if let index = track.clips.firstIndex(where: { $0.id == clip.id }) {
        registerUndo("Rotate Clip")

        var mutableTrack = track
        var mutableClip = track.clips[index]
        mutableClip.rotateClockwise()
        newRotationName = mutableClip.rotation.displayName

        mutableTrack.clips[index] = mutableClip
        timeline.tracks[trackIndex] = mutableTrack
        clipFound = true
        break
      }
    }

    if clipFound {
      project.timeline = timeline
      currentProject = project
      saveProject(project)

      AppLogger.project.info("Rotated clip \(clip.id) to \(newRotationName)")
      ServiceContainer.shared.toastManager.show("Rotated \(newRotationName)")
    }
  }

  func setClipRotation(_ clip: VideoClip, to rotation: VideoClip.Rotation, transactionId: UUID? = nil) {
    guard !shouldBlockOperation(transactionId: transactionId) else { return }
    guard var project = currentProject else { return }

    guard clip.rotation != rotation else { return }

    var timeline = project.timeline
    var clipFound = false

    for (trackIndex, track) in timeline.tracks.enumerated() {
      if let index = track.clips.firstIndex(where: { $0.id == clip.id }) {
        registerUndo("Set Rotation")

        var mutableTrack = track
        var mutableClip = track.clips[index]
        mutableClip.rotation = rotation

        mutableTrack.clips[index] = mutableClip
        timeline.tracks[trackIndex] = mutableTrack
        clipFound = true
        break
      }
    }

    if clipFound {
      project.timeline = timeline
      currentProject = project
      saveProject(project)

      AppLogger.project.info("Set clip \(clip.id) rotation to \(rotation.displayName)")
      ServiceContainer.shared.toastManager.show("Rotated \(rotation.displayName)")
    }
  }

  // MARK: - Removal

  func deleteClip(_ clip: VideoClip, transactionId: UUID? = nil) {
    // CRITICAL: Log why deletion might be blocked
    if shouldBlockOperation(transactionId: transactionId) {
      AppLogger.project.warning("⚠️ Delete clip blocked: operation in progress (transaction: \(transactionId?.uuidString ?? "none"))")
      ServiceContainer.shared.toastManager.show("Cannot delete: Operation in progress", type: .info)
      return
    }
    
    guard var project = currentProject else {
      AppLogger.project.warning("⚠️ Delete clip blocked: No current project")
      ServiceContainer.shared.toastManager.show("Cannot delete: No project open", type: .error)
      return
    }

    if isTrackLocked(for: clip) {
      AppLogger.project.warning("⚠️ Delete clip blocked: Track is locked")
      ServiceContainer.shared.toastManager.show("Track is locked", type: .error)
      return
    }

    registerUndo("Delete Clip")

    var timeline = project.timeline
    var clipFound = false

    for (trackIndex, track) in timeline.tracks.enumerated()
    where track.clips.contains(where: { $0.id == clip.id }) {
      var mutableTrack = track
      mutableTrack.clips.removeAll { $0.id == clip.id }
      timeline.tracks[trackIndex] = mutableTrack
      clipFound = true
      break
    }

    if clipFound {
      recalculateStartTimes(in: &timeline)
      timeline.updateDuration()

      if !validateTimelineState(timeline) {
        AppLogger.project.error("Timeline state invalid after deletion, rolling back")
        ServiceContainer.shared.toastManager.show("Delete failed: Timeline state invalid", type: .error)
        return
      }

      project.timeline = timeline
      currentProject = project
      saveProject(project)

      AppLogger.project.info("✅ Removed clip from timeline: \(clip.url.lastPathComponent)")
      ServiceContainer.shared.toastManager.show("Deleted Clip")
    } else {
      AppLogger.project.warning("⚠️ Delete clip: Clip not found in timeline: \(clip.id)")
      ServiceContainer.shared.toastManager.show("Clip not found in project", type: .info)
    }
  }

  func deleteClipFile(_ clip: VideoClip) {
    guard var project = currentProject else { return }
    var timeline = project.timeline

    for (trackIndex, track) in timeline.tracks.enumerated() {
      if let clipIndex = track.clips.firstIndex(where: { $0.id == clip.id }) {
        var mutableTrack = track
        var mutableClip = track.clips[clipIndex]
        mutableClip.isMissing = true
        mutableTrack.clips[clipIndex] = mutableClip
        timeline.tracks[trackIndex] = mutableTrack
        project.timeline = timeline
        currentProject = project
        break
      }
    }

    deleteClip(clip)

    Task {
      do {
        try await ServiceContainer.shared.projectFileManager.deleteFile(at: clip.url)
        AppLogger.project.info("Moved file to Trash: \(clip.url.lastPathComponent)")
      } catch {
        AppLogger.project.error("Failed to move file to Trash: \(error)")
        await MainActor.run {
          ServiceContainer.shared.errorPresenter.present(AppError.unknown(error))
        }
      }
    }
  }

  // MARK: - Transform

  func updateClipTransform(_ clip: VideoClip, transform: VideoClip.Transform, transactionId: UUID? = nil) {
    guard !shouldBlockOperation(transactionId: transactionId) else { return }
    guard var project = currentProject else { return }

    var timeline = project.timeline
    var clipFound = false

    for (trackIndex, track) in timeline.tracks.enumerated() {
      if let index = track.clips.firstIndex(where: { $0.id == clip.id }) {
        if track.isLocked { return }

        var mutableTrack = track
        mutableTrack.clips[index].transform = transform
        timeline.tracks[trackIndex] = mutableTrack
        clipFound = true
        break
      }
    }

    if clipFound {
      project.timeline = timeline
      currentProject = project
      saveProject(project)
    }
  }

  // MARK: - Speed

  func updateClipSpeed(clipId: UUID, speed: Double, transactionId: UUID? = nil) {
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

        registerUndo("Change Speed")

        var mutableTrack = track
        mutableTrack.clips[index].speed = speed
        timeline.tracks[trackIndex] = mutableTrack
        clipFound = true
        break
      }
    }

    if clipFound {
      recalculateStartTimes(in: &timeline)
      // CRITICAL FIX: Speed changes affect effectiveDuration, so timeline duration must update
      timeline.updateDuration()
      project.timeline = timeline
      currentProject = project
      saveProject(project)

      AppLogger.project.info("Updated clip speed to \(speed)x")
      ServiceContainer.shared.toastManager.show(String(format: "Speed: %.2fx", speed))
    }
  }

  // MARK: - Effects

  func updateClipEffects(clipId: UUID, effects: [VideoEffect], transactionId: UUID? = nil) {
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

        registerUndo("Update Effects")

        var mutableTrack = track
        mutableTrack.clips[index].effects = effects
        timeline.tracks[trackIndex] = mutableTrack
        clipFound = true
        break
      }
    }

    if clipFound {
      project.timeline = timeline
      currentProject = project
      saveProject(project)

      AppLogger.project.info("Updated clip effects: \(effects.count) effects applied")

      NotificationCenter.default.post(
        name: NSNotification.Name("ProjectEffectsChanged"),
        object: project
      )
    }
  }

  func updateClipBackgroundEffect(clipId: UUID, effect: BackgroundEffect?, transactionId: UUID? = nil) {
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

        registerUndo("Update Background")

        var mutableTrack = track
        mutableTrack.clips[index].backgroundEffect = effect
        timeline.tracks[trackIndex] = mutableTrack
        clipFound = true
        break
      }
    }

    if clipFound {
      project.timeline = timeline
      currentProject = project
      saveProject(project)

      let effectName = effect?.displayName ?? "None"
      AppLogger.project.info("Updated clip background effect: \(effectName)")
      ServiceContainer.shared.toastManager.show("Background: \(effectName)")
    }
  }

  func applyEffect(to clip: VideoClip, effect: VideoEffect, transactionId: UUID? = nil) {
    var newEffects = clip.effects.filter { $0.type != effect.type }
    newEffects.append(effect)
    updateClipEffects(clipId: clip.id, effects: newEffects, transactionId: transactionId)
  }

  func removeEffect(from clip: VideoClip, type: VideoEffectType, transactionId: UUID? = nil) {
    let newEffects = clip.effects.filter { $0.type != type }
    if newEffects.count != clip.effects.count {
      updateClipEffects(clipId: clip.id, effects: newEffects, transactionId: transactionId)
    }
  }

  func clearEffects(from clip: VideoClip, transactionId: UUID? = nil) {
    updateClipEffects(clipId: clip.id, effects: [], transactionId: transactionId)
  }

  // MARK: - Overlay Management

  func updateClipOverlay(clipId: UUID, overlay: VideoClip.VideoOverlay, transactionId: UUID? = nil) {
    guard !shouldBlockOperation(transactionId: transactionId) else { return }
    guard var project = currentProject else { return }

    var timeline = project.timeline
    var clipFound = false

    for (trackIndex, track) in timeline.tracks.enumerated() {
      if let index = track.clips.firstIndex(where: { $0.id == clipId }) {
        if track.isLocked { return }

        var mutableTrack = track
        var clip = mutableTrack.clips[index]

        if let overlayIndex = clip.overlays.firstIndex(where: { $0.id == overlay.id }) {
          clip.overlays[overlayIndex] = overlay
        } else {
          clip.overlays.append(overlay)
        }

        mutableTrack.clips[index] = clip
        timeline.tracks[trackIndex] = mutableTrack
        clipFound = true
        break
      }
    }

    if clipFound {
      project.timeline = timeline
      currentProject = project
      saveProject(project)
    }
  }
}
