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
    let frame: CGRect // Normalized rect (0-1)
    let timeRange: CMTimeRange
    let isCaption: Bool
    var rotation: Double = 0.0
    var scale: CGFloat = 1.0
    // Future: Font, color, etc.
}

// MARK: - Instruction Class

/// Custom Instruction that carries effect metadata
class SaneVideoCompositionInstruction: NSObject, AVVideoCompositionInstructionProtocol, @unchecked Sendable {
    // MARK: - AVVideoCompositionInstructionProtocol

    var timeRange: CMTimeRange
    var enablePostProcessing: Bool = true
    var containsTweening: Bool = true // Tweeing allowed for transitions
    var requiredSourceTrackIDs: [NSValue]? // IDs of tracks used in this instruction
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

    /// Track ID -> Cursor Data URL (if enabled)
    let trackCursorData: [CMPersistentTrackID: URL]

    /// Vision service for background effects (optional)
    let visionService: PersonSegmentationService?

    /// Main Layer Instructions (for transforms/opacity)
    let layerInstructions: [AVVideoCompositionLayerInstruction]

    init(timeRange: CMTimeRange, layerInstructions: [AVVideoCompositionLayerInstruction], trackEffects: [CMPersistentTrackID: [(CMTimeRange, [VideoEffect])]] = [:], trackKeyframes: [CMPersistentTrackID: [(CMTimeRange, [KeyframeAnimation])]] = [:], trackBackgroundEffects: [CMPersistentTrackID: [(CMTimeRange, [BackgroundEffect])]] = [:], trackPrivacyRegions: [CMPersistentTrackID: [(CMTimeRange, [PrivacyRegion])]] = [:], activeTransitions: [TransitionMetadata] = [], textLayers: [TextLayerItem] = [], trackCursorData: [CMPersistentTrackID: URL] = [:], visionService: PersonSegmentationService? = nil) {
        self.timeRange = timeRange
        self.layerInstructions = layerInstructions
        self.trackEffects = trackEffects
        self.trackKeyframes = trackKeyframes
        self.trackBackgroundEffects = trackBackgroundEffects
        self.trackPrivacyRegions = trackPrivacyRegions
        self.activeTransitions = activeTransitions
        self.textLayers = textLayers
        self.trackCursorData = trackCursorData
        self.visionService = visionService

        // Extract required track IDs from layer instructions
        requiredSourceTrackIDs = layerInstructions.map { NSNumber(value: $0.trackID) }
    }
}
