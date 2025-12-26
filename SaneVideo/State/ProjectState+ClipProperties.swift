//
//  ProjectState+ClipProperties.swift
//  SaneVideo
//
//  Created by SaneVideo Refactor
//

import AppKit
import Foundation
import SwiftUI

extension ProjectState {

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
      // Note: For high-frequency updates (drag), we might want to debounce saving.
      // But for safety, we queue it.
      saveProject(project)
    }
  }

  // MARK: - Speed

  /// Update clip playback speed
  func updateClipSpeed(clipId: UUID, speed: Double, transactionId: UUID? = nil) {
    guard !shouldBlockOperation(transactionId: transactionId) else { return }
    guard var project = currentProject else { return }

    var timeline = project.timeline
    var clipFound = false

    for (trackIndex, track) in timeline.tracks.enumerated() {
      if let index = track.clips.firstIndex(where: { $0.id == clipId }) {
        // Check lock
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
      project.timeline = timeline
      currentProject = project
      saveProject(project)

      AppLogger.project.info("Updated clip speed to \(speed)x")
      ServiceContainer.shared.toastManager.show(String(format: "Speed: %.2fx", speed))
    }
  }

  // MARK: - Effects

  /// Update clip effects
  /// - Parameter transactionId: Optional transaction ID to bypass processing guard
  func updateClipEffects(clipId: UUID, effects: [VideoEffect], transactionId: UUID? = nil) {
    guard !shouldBlockOperation(transactionId: transactionId) else { return }
    guard var project = currentProject else { return }

    var timeline = project.timeline
    var clipFound = false

    for (trackIndex, track) in timeline.tracks.enumerated() {
      if let index = track.clips.firstIndex(where: { $0.id == clipId }) {
        // Check lock
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

      // INSTANT PREVIEW: Trigger immediate project reload to show effects
      // This ensures effects appear instantly in video preview
      // Post notification to trigger reload via UnifiedStateChangeModifier
      NotificationCenter.default.post(
        name: NSNotification.Name("ProjectEffectsChanged"),
        object: project
      )
    }
  }

  /// Update clip background effect (person segmentation)
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

  /// Apply a single effect to a clip (replaces existing effects of same type)
  func applyEffect(to clip: VideoClip, effect: VideoEffect, transactionId: UUID? = nil) {
    // Replace any existing effect of the same type, or add new
    var newEffects = clip.effects.filter { $0.type != effect.type }
    newEffects.append(effect)
    updateClipEffects(clipId: clip.id, effects: newEffects, transactionId: transactionId)
  }

  /// Remove an effect of a specific type from a clip
  func removeEffect(from clip: VideoClip, type: VideoEffectType, transactionId: UUID? = nil) {
    let newEffects = clip.effects.filter { $0.type != type }
    // Only update if something changed
    if newEffects.count != clip.effects.count {
      updateClipEffects(clipId: clip.id, effects: newEffects, transactionId: transactionId)
    }
  }

  /// Clear all effects from a clip
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
          // Update existing
          clip.overlays[overlayIndex] = overlay
        } else {
          // Add new (safeguard)
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
      // Queue save
      saveProject(project)
    }
  }

  // MARK: - Cursor Enhancements

  func updateClipCursorHighlight(_ clip: VideoClip, show: Bool, transactionId: UUID? = nil) {
    guard !shouldBlockOperation(transactionId: transactionId) else { return }
    guard var project = currentProject else { return }

    var timeline = project.timeline
    var clipFound = false

    for (trackIndex, track) in timeline.tracks.enumerated() {
      if let index = track.clips.firstIndex(where: { $0.id == clip.id }) {
        if track.isLocked {
          ServiceContainer.shared.toastManager.show("Track is locked", type: .error)
          return
        }

        registerUndo("Toggle Cursor Highlight")

        var mutableTrack = track
        mutableTrack.clips[index].showCursorHighlight = show
        timeline.tracks[trackIndex] = mutableTrack
        clipFound = true
        break
      }
    }

    if clipFound {
      project.timeline = timeline
      currentProject = project
      saveProject(project)

      AppLogger.project.info("Updated clip cursor highlight to \(show)")
    }
  }
}
