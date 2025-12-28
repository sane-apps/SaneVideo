//
//  VideoTrackBuilder.swift
//  SaneVideo
//
//  Created by SaneVideo Refactor
//

import AVFoundation
import CoreMedia

/// Helper for building video tracks from timeline clips
enum VideoTrackBuilder {

  /// Result containing composition tracks and metadata for video composition
  struct BuildResult {

    let compositionVideoTracks: [AVMutableCompositionTrack]
    let layerInstructions: [AVVideoCompositionLayerInstruction]
    let trackEffects: [CMPersistentTrackID: [(CMTimeRange, [VideoEffect])]]
    let trackKeyframes: [CMPersistentTrackID: [(CMTimeRange, [KeyframeAnimation])]]
    let trackBackgroundEffects: [CMPersistentTrackID: [(CMTimeRange, [BackgroundEffect])]]
    let trackPrivacyRegions: [CMPersistentTrackID: [(CMTimeRange, [PrivacyRegion])]]
    let activeTransitions: [TransitionMetadata]
  }

  /// Build video tracks with A/B roll architecture
  static func build(
    from visualTimelineTracks: [Track],
    into composition: AVMutableComposition,
    assetCache: inout [URL: AVURLAsset],
    renderSize: CGSize
  ) async throws -> BuildResult {

    var abTracks: [(AVMutableCompositionTrack, AVMutableCompositionTrack)] = []
    var compositionVideoTracks: [AVMutableCompositionTrack] = []  // All created tracks flattened

    for track in visualTimelineTracks {
      guard track.type == .video || track.type == .overlay else { continue }

      guard
        let trackA = composition.addMutableTrack(
          withMediaType: .video, preferredTrackID: kCMPersistentTrackID_Invalid),
        let trackB = composition.addMutableTrack(
          withMediaType: .video, preferredTrackID: kCMPersistentTrackID_Invalid)
      else { continue }

      abTracks.append((trackA, trackB))
      compositionVideoTracks.append(trackA)
      compositionVideoTracks.append(trackB)
    }

    // Metadata collections for VideoComposition
    var layerInstructions: [AVVideoCompositionLayerInstruction] = []
    var trackEffects: [CMPersistentTrackID: [(CMTimeRange, [VideoEffect])]] = [:]
    var trackKeyframes: [CMPersistentTrackID: [(CMTimeRange, [KeyframeAnimation])]] = [:]
    var trackBackgroundEffects: [CMPersistentTrackID: [(CMTimeRange, [BackgroundEffect])]] = [:]
    var trackPrivacyRegions: [CMPersistentTrackID: [(CMTimeRange, [PrivacyRegion])]] = [:]
    var activeTransitions: [TransitionMetadata] = []

    // Iterate Timeline Tracks and Insert Clips
    for (index, timelineTrack) in visualTimelineTracks.enumerated() {
      guard index < abTracks.count else { continue }
      let (trackA, trackB) = abTracks[index]

      var useTrackA = true
      let sortedClips = timelineTrack.clips.sorted { $0.startTime < $1.startTime }

      for (clipIndex, clip) in sortedClips.enumerated() {
        let asset = getAsset(for: clip.url, cache: &assetCache)
        guard
          let assetTrack = try? await asset.load(.tracks).first(where: { $0.mediaType == .video })
        else { continue }
        let assetDuration = (try? await asset.load(.duration)) ?? .zero

        // Effective Source Duration (Visual trimming)
        let sourceDuration = CMTimeSubtract(min(clip.trimEnd, assetDuration), clip.trimStart)
        guard sourceDuration > .zero else { continue }

        // Current Target Composition Track
        let currentCompTrack = useTrackA ? trackA : trackB

        // Insertion Time
        let insertStart = clip.startTime

        // Handling Transitions (Overlap)
        var overlapDuration = CMTime.zero
        var transitionType: TransitionType = .none

        if clipIndex > 0 {
          let prevClip = sortedClips[clipIndex - 1]
          if let trans = prevClip.transition {
            overlapDuration = trans.duration
            transitionType = trans.type
          }
        }

        // Compute Valid Segments (Handle Silence Removal)
        let validSegments = computeValidSegments(clip: clip, sourceDuration: sourceDuration)

        // Insert Video Segments
        var currentInsertStart = insertStart
        var segmentCompTrack = useTrackA ? trackA : trackB

        // Define overlap for smooth cuts (internal to clip)
        let smoothCutOverlap = CMTime(seconds: 0.15, preferredTimescale: 600)

        for (segIndex, segment) in validSegments.enumerated() {
          var finalSegment = segment
          var finalInsertStart = currentInsertStart

          // Logic for internal transitions if enabled
          if clip.useSmoothCutForRemovals && validSegments.count > 1 {
            // Extend segments to overlap for transition
            if segIndex > 0 {
              // Start earlier to overlap with previous
              finalSegment.start = CMTimeSubtract(finalSegment.start, smoothCutOverlap)
              finalSegment.duration = CMTimeAdd(finalSegment.duration, smoothCutOverlap)
              finalInsertStart = CMTimeSubtract(finalInsertStart, smoothCutOverlap)
            }
          }

          try? segmentCompTrack.insertTimeRange(finalSegment, of: assetTrack, at: finalInsertStart)

          let segmentDuration = finalSegment.duration
          let playDuration = CMTimeMultiplyByFloat64(segmentDuration, multiplier: 1.0 / clip.speed)

          if clip.speed != 1.0 {
            let scaleRange = CMTimeRange(start: finalInsertStart, duration: segmentDuration)
            segmentCompTrack.scaleTimeRange(scaleRange, toDuration: playDuration)
          }

          // Add Internal Transition Metadata
          if clip.useSmoothCutForRemovals && segIndex > 0 {
            let fromTrackID = (segmentCompTrack === trackA) ? trackB.trackID : trackA.trackID
            let toTrackID = segmentCompTrack.trackID

            // Transition happens during the overlap
            let transitionRange = CMTimeRange(start: finalInsertStart, duration: smoothCutOverlap)
            activeTransitions.append(
              TransitionMetadata(
                timeRange: transitionRange,
                fromTrackID: fromTrackID,
                toTrackID: toTrackID,
                type: .smoothCut
              ))
          }

          // Update currentInsertStart based on ORIGINAL (non-extended) segment duration to preserve timeline timing
          let originalPlayDuration = CMTimeMultiplyByFloat64(
            segment.duration, multiplier: 1.0 / clip.speed)
          currentInsertStart = CMTimeAdd(currentInsertStart, originalPlayDuration)

          // Switch tracks for next segment if doing smooth cuts
          if clip.useSmoothCutForRemovals {
            segmentCompTrack = (segmentCompTrack === trackA) ? trackB : trackA
          }
        }

        let totalPlayDuration = CMTimeSubtract(currentInsertStart, insertStart)
        let playDuration = totalPlayDuration

        // Ensure useTrackA is updated based on the LAST track used for this clip
        useTrackA = (segmentCompTrack === trackA)

        // Video Metadata Collection

        // A. Transform
        var layerConfig = AVVideoCompositionLayerInstruction.Configuration(
          trackID: currentCompTrack.trackID)

        if let transform = try? await TransformCalculator.calculateTransform(
          assetTrack: assetTrack,
          rotation: clip.rotation,
          userTransform: clip.transform,
          renderSize: renderSize
        ) {
          layerConfig.setTransform(transform, at: insertStart)
          layerConfig.setOpacity(1.0, at: insertStart)
          layerConfig.setOpacity(0.0, at: CMTimeAdd(insertStart, playDuration))
        }
        let layerInstruction = AVVideoCompositionLayerInstruction(configuration: layerConfig)
        layerInstructions.append(layerInstruction)

        // B. Effects
        if !clip.effects.isEmpty {
          var effects = trackEffects[currentCompTrack.trackID] ?? []
          effects.append((CMTimeRange(start: insertStart, duration: playDuration), clip.effects))
          trackEffects[currentCompTrack.trackID] = effects
        }

        // C. Keyframes
        if let keyframes = clip.keyframeAnimation {
          var kfs = trackKeyframes[currentCompTrack.trackID] ?? []
          kfs.append((CMTimeRange(start: insertStart, duration: playDuration), [keyframes]))
          trackKeyframes[currentCompTrack.trackID] = kfs
        }

        // D. Background Effects (Person Segmentation)
        if let bgEffect = clip.backgroundEffect {
          var bgEffects = trackBackgroundEffects[currentCompTrack.trackID] ?? []
          bgEffects.append((CMTimeRange(start: insertStart, duration: playDuration), [bgEffect]))
          trackBackgroundEffects[currentCompTrack.trackID] = bgEffects
        }

        // E. Privacy Regions
        if !clip.privacyRegions.isEmpty {
          var regions = trackPrivacyRegions[currentCompTrack.trackID] ?? []
          regions.append(
            (CMTimeRange(start: insertStart, duration: playDuration), clip.privacyRegions))
          trackPrivacyRegions[currentCompTrack.trackID] = regions
        }

        // F. Active Transition (Incoming)
        if overlapDuration > .zero {
          let prevTrackID = useTrackA ? trackB.trackID : trackA.trackID
          let currentTrackID = currentCompTrack.trackID
          let transitionRange = CMTimeRange(start: insertStart, duration: overlapDuration)

          let meta = TransitionMetadata(
            timeRange: transitionRange,
            fromTrackID: prevTrackID,
            toTrackID: currentTrackID,
            type: transitionType
          )
          activeTransitions.append(meta)
        }

        // Toggle A/B for next clip
        useTrackA.toggle()
      }
    }

    return BuildResult(
      compositionVideoTracks: compositionVideoTracks,
      layerInstructions: layerInstructions,
      trackEffects: trackEffects,
      trackKeyframes: trackKeyframes,
      trackBackgroundEffects: trackBackgroundEffects,
      trackPrivacyRegions: trackPrivacyRegions,
      activeTransitions: activeTransitions
    )
  }

  // MARK: - Private Helpers

  private static func getAsset(for url: URL, cache: inout [URL: AVURLAsset]) -> AVURLAsset {
    if let cached = cache[url] {
      return cached
    }
    let asset = AVURLAsset(url: url)
    cache[url] = asset
    return asset
  }

  /// Compute valid segments after removing silence/cut ranges
  static func computeValidSegments(clip: VideoClip, sourceDuration: CMTime) -> [CMTimeRange] {
    var validSegments: [CMTimeRange] = []
    let fullTrimRange = CMTimeRange(start: clip.trimStart, duration: sourceDuration)

    if clip.removedRanges.isEmpty {
      validSegments.append(fullTrimRange)
    } else {
      let removals = clip.removedRanges.map { $0.timeRange }.sorted { $0.start < $1.start }
      var cursor = clip.trimStart

      for removal in removals {
        let endLimit = clip.trimEnd
        if cursor >= endLimit { break }

        let removalStart = removal.start
        let removalEnd = removal.end

        if removalEnd <= cursor { continue }

        if removalStart > cursor {
          let validEnd = min(removalStart, endLimit)
          let duration = CMTimeSubtract(validEnd, cursor)
          if duration.seconds > 0.001 {
            validSegments.append(CMTimeRange(start: cursor, duration: duration))
          }
        }

        cursor = max(cursor, removalEnd)
      }

      // Tail segment
      if cursor < clip.trimEnd {
        let duration = CMTimeSubtract(clip.trimEnd, cursor)
        if duration.seconds > 0.001 {
          validSegments.append(CMTimeRange(start: cursor, duration: duration))
        }
      }
    }

    return validSegments
  }
}
