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
        var populatedTracks: [AVMutableCompositionTrack] = []

        func notePopulatedTrack(_ track: AVMutableCompositionTrack) {
          if populatedTracks.contains(where: { $0.trackID == track.trackID }) { return }
          populatedTracks.append(track)
        }

        // Define overlap for smooth cuts (internal to clip)
        // NOTE: Overlap must be expressed in PLAYED time, and mapped to SOURCE time based on clip speed.
        // This prevents mismatched overlap ranges (and potential A/V sync drift) when speed != 1.0.
        let overlap = TimeUtils.smoothCutOverlap(clipSpeed: clip.speed, overlapPlayedSeconds: 0.15)

        for (segIndex, segment) in validSegments.enumerated() {
          let targetTrack = segmentCompTrack
          var finalSegment = segment
          var finalInsertStart = currentInsertStart
          var actualOverlapPlayed = CMTime.zero

          // Logic for internal transitions if enabled
          if clip.useSmoothCutForRemovals && validSegments.count > 1 {
            // Extend segments to overlap for transition
            if segIndex > 0 {
              // Start earlier to overlap with previous.
              // Clamp overlap so we never extend before the trimmed start.
              let maxBackwards = CMTimeSubtract(segment.start, clip.trimStart)
              var actualOverlapSource = CMTimeMinimum(overlap.source, maxBackwards)
              // Clamp overlap so we never exceed the previous segment length (prevents triple-overlap on A/B tracks).
              let prevSegment = validSegments[segIndex - 1]
              actualOverlapSource = CMTimeMinimum(actualOverlapSource, prevSegment.duration)

              if actualOverlapSource > .zero {
                // Convert the actual clamped SOURCE overlap back into PLAYED overlap.
                // played = source / speed
                actualOverlapPlayed = CMTimeMultiplyByFloat64(
                  actualOverlapSource, multiplier: 1.0 / max(clip.speed, 0.000_001))

                finalSegment.start = CMTimeSubtract(finalSegment.start, actualOverlapSource)
                finalSegment.duration = CMTimeAdd(finalSegment.duration, actualOverlapSource)
                finalInsertStart = CMTimeSubtract(finalInsertStart, actualOverlapPlayed)
              }
            }
          }

          try? targetTrack.insertTimeRange(finalSegment, of: assetTrack, at: finalInsertStart)
          notePopulatedTrack(targetTrack)

          let segmentDuration = finalSegment.duration
          let playDuration = CMTimeMultiplyByFloat64(segmentDuration, multiplier: 1.0 / clip.speed)

          if clip.speed != 1.0 {
            let scaleRange = CMTimeRange(start: finalInsertStart, duration: segmentDuration)
            targetTrack.scaleTimeRange(scaleRange, toDuration: playDuration)
          }

          // Add Internal Transition Metadata
          if clip.useSmoothCutForRemovals && segIndex > 0 && actualOverlapPlayed > .zero {
            let fromTrackID = (targetTrack === trackA) ? trackB.trackID : trackA.trackID
            let toTrackID = targetTrack.trackID

            // Transition happens during the overlap
            let transitionRange = CMTimeRange(start: finalInsertStart, duration: actualOverlapPlayed)
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
            segmentCompTrack = (targetTrack === trackA) ? trackB : trackA
          }
        }

        let totalPlayDuration = CMTimeSubtract(currentInsertStart, insertStart)
        let playDuration = totalPlayDuration
        let instructionTracks = populatedTracks.isEmpty ? [currentCompTrack] : populatedTracks

        // Ensure useTrackA is updated based on the LAST track used for this clip
        useTrackA = (segmentCompTrack === trackA)

        // Video Metadata Collection

        // A. Transform
        let transform = try? await TransformCalculator.calculateTransform(
          assetTrack: assetTrack,
          rotation: clip.rotation,
          userTransform: clip.transform,
          renderSize: renderSize
        )

        for instructionTrack in instructionTracks {
          let layerInstruction: AVVideoCompositionLayerInstruction

          if let transform {
#if compiler(>=6.2)
            if #available(macOS 26.0, *) {
              var layerConfig = AVVideoCompositionLayerInstruction.Configuration(
                trackID: instructionTrack.trackID)
              layerConfig.setTransform(transform, at: insertStart)
              layerConfig.setOpacity(1.0, at: insertStart)
              layerConfig.setOpacity(0.0, at: CMTimeAdd(insertStart, playDuration))
              layerInstruction = AVVideoCompositionLayerInstruction(configuration: layerConfig)
            } else {
              layerInstruction = makeMutableLayerInstruction(
                for: instructionTrack,
                transform: transform,
                insertStart: insertStart,
                playDuration: playDuration
              )
            }
#else
            layerInstruction = makeMutableLayerInstruction(
              for: instructionTrack,
              transform: transform,
              insertStart: insertStart,
              playDuration: playDuration
            )
#endif
          } else {
#if compiler(>=6.2)
            if #available(macOS 26.0, *) {
              let layerConfig = AVVideoCompositionLayerInstruction.Configuration(
                trackID: instructionTrack.trackID)
              layerInstruction = AVVideoCompositionLayerInstruction(configuration: layerConfig)
            } else {
              layerInstruction = AVMutableVideoCompositionLayerInstruction(assetTrack: instructionTrack)
            }
#else
            layerInstruction = AVMutableVideoCompositionLayerInstruction(assetTrack: instructionTrack)
#endif
          }

          layerInstructions.append(layerInstruction)
        }

        // B. Effects
        if !clip.effects.isEmpty {
          for instructionTrack in instructionTracks {
            var effects = trackEffects[instructionTrack.trackID] ?? []
            effects.append((CMTimeRange(start: insertStart, duration: playDuration), clip.effects))
            trackEffects[instructionTrack.trackID] = effects
          }
        }

        // C. Keyframes
        if let keyframes = clip.keyframeAnimation {
          for instructionTrack in instructionTracks {
            var kfs = trackKeyframes[instructionTrack.trackID] ?? []
            kfs.append((CMTimeRange(start: insertStart, duration: playDuration), [keyframes]))
            trackKeyframes[instructionTrack.trackID] = kfs
          }
        }

        // D. Background Effects (Person Segmentation)
        if let bgEffect = clip.backgroundEffect {
          for instructionTrack in instructionTracks {
            var bgEffects = trackBackgroundEffects[instructionTrack.trackID] ?? []
            bgEffects.append((CMTimeRange(start: insertStart, duration: playDuration), [bgEffect]))
            trackBackgroundEffects[instructionTrack.trackID] = bgEffects
          }
        }

        // E. Privacy Regions
        if !clip.privacyRegions.isEmpty {
          for instructionTrack in instructionTracks {
            var regions = trackPrivacyRegions[instructionTrack.trackID] ?? []
            regions.append(
              (CMTimeRange(start: insertStart, duration: playDuration), clip.privacyRegions))
            trackPrivacyRegions[instructionTrack.trackID] = regions
          }
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

  private static func makeMutableLayerInstruction(
    for track: AVCompositionTrack,
    transform: CGAffineTransform,
    insertStart: CMTime,
    playDuration: CMTime
  ) -> AVMutableVideoCompositionLayerInstruction {
    // Use the composition track, not the source asset track, so the compositor can resolve frames.
    let mutableInstruction = AVMutableVideoCompositionLayerInstruction(assetTrack: track)
    mutableInstruction.setTransform(transform, at: insertStart)
    mutableInstruction.setOpacity(1.0, at: insertStart)
    mutableInstruction.setOpacity(0.0, at: CMTimeAdd(insertStart, playDuration))
    return mutableInstruction
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
