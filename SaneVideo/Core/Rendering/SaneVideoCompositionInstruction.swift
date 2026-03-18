//
//  SaneVideoCompositionInstruction.swift
//  SaneVideo
//
//  Created by SaneVideo Refactor
//

import AVFoundation
import CoreMedia
import Foundation

// MARK: - Metadata Structs

/// Metadata needed to render a transition between two tracks
struct TransitionMetadata: Sendable {
  let timeRange: CMTimeRange
  let fromTrackID: CMPersistentTrackID
  let toTrackID: CMPersistentTrackID
  let type: TransitionType
}

/// Metadata for a text overlay (Caption or Overlay)
struct TextLayerItem: Sendable {
  let id: UUID
  let text: String
  let frame: CGRect  // Normalized rect (0-1)
  let timeRange: CMTimeRange
  let isCaption: Bool
  var rotation: Double = 0.0
  var scale: CGFloat = 1.0

  // Styling (from CaptionStyle)
  let style: CaptionStyle?

  // Word-level timing for karaoke highlighting
  let words: [CaptionWord]?
}

struct InteractionClickItem: Sendable {
  let time: CMTime
  let x: Double
  let y: Double
  let button: Int
}

struct InteractionCursorItem: Sendable {
  let time: CMTime
  let x: Double
  let y: Double
  let isDown: Bool
}

struct InteractionKeystrokeItem: Sendable {
  let id: UUID
  let time: CMTime
  let text: String
}

struct InteractionLayerItem: Sendable {
  let clipID: UUID
  let timeRange: CMTimeRange
  let clicks: [InteractionClickItem]
  let cursorPath: [InteractionCursorItem]
  let keystrokes: [InteractionKeystrokeItem]
  let style: InteractionOverlayStyle

  func cursorPosition(at compositionTime: CMTime) -> (x: Double, y: Double)? {
    guard !cursorPath.isEmpty else { return nil }

    if compositionTime <= cursorPath[0].time {
      return (cursorPath[0].x, cursorPath[0].y)
    }

    for index in 1..<cursorPath.count {
      let previous = cursorPath[index - 1]
      let next = cursorPath[index]
      if compositionTime <= next.time {
        let span = next.time.seconds - previous.time.seconds
        guard span > 0.000_1 else { return (next.x, next.y) }
        let progress = max(0, min(1, (compositionTime.seconds - previous.time.seconds) / span))
        return (
          previous.x + ((next.x - previous.x) * progress),
          previous.y + ((next.y - previous.y) * progress)
        )
      }
    }

    if let last = cursorPath.last {
      return (last.x, last.y)
    }

    return nil
  }
}

// MARK: - Instruction Class

/// Custom Instruction that carries effect metadata
class SaneVideoCompositionInstruction: NSObject, AVVideoCompositionInstructionProtocol,
  @unchecked Sendable {
  // MARK: - AVVideoCompositionInstructionProtocol

  var timeRange: CMTimeRange
  var enablePostProcessing: Bool = true
  var containsTweening: Bool = true  // Tweeing allowed for transitions
  var requiredSourceTrackIDs: [NSValue]?  // IDs of tracks used in this instruction
  var passthroughTrackID: CMPersistentTrackID = kCMPersistentTrackID_Invalid

  // MARK: - Custom Metadata

  /// Track ID -> List of (TimeRange, Effects)
  let trackEffects: [CMPersistentTrackID: [(CMTimeRange, [VideoEffect])]]

  /// Track ID -> List of (TimeRange, [KeyframeAnimation])
  let trackKeyframes: [CMPersistentTrackID: [(CMTimeRange, [KeyframeAnimation])]]

  /// Track ID -> List of (TimeRange, [BackgroundEffect]) for person segmentation
  let trackBackgroundEffects: [CMPersistentTrackID: [(CMTimeRange, [BackgroundEffect])]]

  /// Track ID -> List of (TimeRange, [PrivacyRegion]) for privacy blur
  let trackPrivacyRegions: [CMPersistentTrackID: [(CMTimeRange, [PrivacyRegion])]]

  /// Active Transitions in this instruction
  let activeTransitions: [TransitionMetadata]

  /// Active Text Layers (Captions + Overlays) for this instruction time range
  let textLayers: [TextLayerItem]

  /// Active interaction overlays (click rings, cursor spotlight, keystroke pills)
  let interactionLayers: [InteractionLayerItem]

  /// Vision service for background effects (optional)
  let visionService: PersonSegmentationService?

  /// Main Layer Instructions (for transforms/opacity)
  let layerInstructions: [AVVideoCompositionLayerInstruction]

  /// Smart crop keyframes for AI-powered reframing (from SmartCropService)
  /// Maps composition time -> crop suggestion (center X/Y, scale)
  let smartCropKeyframes: [CMTime: SuggestedCrop]?

  init(
    timeRange: CMTimeRange, layerInstructions: [AVVideoCompositionLayerInstruction],
    trackEffects: [CMPersistentTrackID: [(CMTimeRange, [VideoEffect])]] = [:],
    trackKeyframes: [CMPersistentTrackID: [(CMTimeRange, [KeyframeAnimation])]] = [:],
    trackBackgroundEffects: [CMPersistentTrackID: [(CMTimeRange, [BackgroundEffect])]] = [:],
    trackPrivacyRegions: [CMPersistentTrackID: [(CMTimeRange, [PrivacyRegion])]] = [:],
    activeTransitions: [TransitionMetadata] = [], textLayers: [TextLayerItem] = [],
    interactionLayers: [InteractionLayerItem] = [],
    visionService: PersonSegmentationService? = nil,
    smartCropKeyframes: [CMTime: SuggestedCrop]? = nil
  ) {
    self.timeRange = timeRange
    self.layerInstructions = layerInstructions
    self.trackEffects = trackEffects
    self.trackKeyframes = trackKeyframes
    self.trackBackgroundEffects = trackBackgroundEffects
    self.trackPrivacyRegions = trackPrivacyRegions
    self.activeTransitions = activeTransitions
    self.textLayers = textLayers
    self.interactionLayers = interactionLayers
    self.visionService = visionService
    self.smartCropKeyframes = smartCropKeyframes

    // Extract required track IDs from layer instructions
    requiredSourceTrackIDs = layerInstructions.map { NSNumber(value: $0.trackID) }
  }
}
