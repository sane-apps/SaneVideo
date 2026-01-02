//
//  TextLayerBuilder.swift
//  SaneVideo
//
//  Created by SaneVideo Refactor
//

import AVFoundation
import CoreMedia

/// Helper for building text layers (captions and overlays) from timeline clips
enum TextLayerBuilder {
    
    /// Build text layers for captions and overlays
    static func build(
        from visualTimelineTracks: [Track],
        project: VideoProject
    ) -> [TextLayerItem] {
        
        var textLayers: [TextLayerItem] = []
        
        // Calculate Caption Geometry
        let defaultCaptionX = 0.1
        let defaultCaptionY = 0.8
        let defaultCaptionW = 0.8
        let defaultCaptionH = 0.15

        // Apply Project Global Offset (Normalized)
        let captionX = defaultCaptionX + project.captionOffset.width
        let captionY = defaultCaptionY + project.captionOffset.height

        for timelineTrack in visualTimelineTracks {
            for clip in timelineTrack.clips {
                let clipStart = clip.startTime

                // 1. Captions
                for caption in clip.captions {
                    let capStart = caption.startTime
                    let capEnd = caption.endTime

                    // Check availability in valid ranges
                    guard let effStart = clip.effectiveTime(forOriginalTime: capStart),
                          let effEnd = clip.effectiveTime(forOriginalTime: capEnd)
                    else {
                        continue
                    }

                    let offset = effStart
                    let duration = CMTimeSubtract(effEnd, effStart)

                    // Speed adjustment
                    let scaledOffset = CMTimeMultiplyByFloat64(offset, multiplier: 1.0 / clip.speed)
                    let scaledDuration = CMTimeMultiplyByFloat64(duration, multiplier: 1.0 / clip.speed)

                    let compStart = CMTimeAdd(clipStart, scaledOffset)
                    let compRange = CMTimeRange(start: compStart, duration: scaledDuration)

                    // Create Item with style and word-level timing
                    let item = TextLayerItem(
                        id: caption.id,
                        text: caption.text,
                        frame: CGRect(x: captionX, y: captionY, width: defaultCaptionW, height: defaultCaptionH),
                        timeRange: compRange,
                        isCaption: true,
                        style: project.captionStyle,
                        words: caption.words
                    )
                    textLayers.append(item)
                }

                // 2. Overlays
                for overlay in clip.overlays {
                    let overlayStartSeconds = overlay.startTime
                    let overlayDurSeconds = overlay.duration

                    let overlayStart = CMTime(seconds: overlayStartSeconds, preferredTimescale: 600)
                    let overlayEnd = CMTime(seconds: overlayStartSeconds + overlayDurSeconds, preferredTimescale: 600)

                    // Map to effective time
                    guard let effStart = clip.effectiveTime(forOriginalTime: overlayStart),
                          let effEnd = clip.effectiveTime(forOriginalTime: overlayEnd)
                    else {
                        continue
                    }

                    let offset = effStart
                    let duration = CMTimeSubtract(effEnd, effStart)

                    // Speed adjustment
                    let scaledStart = CMTimeMultiplyByFloat64(offset, multiplier: 1.0 / clip.speed)
                    let scaledDuration = CMTimeMultiplyByFloat64(duration, multiplier: 1.0 / clip.speed)

                    let compStart = CMTimeAdd(clipStart, scaledStart)
                    let compRange = CMTimeRange(start: compStart, duration: scaledDuration)

                    let item = TextLayerItem(
                        id: overlay.id,
                        text: overlay.text,
                        frame: CGRect(x: overlay.position.x, y: overlay.position.y, width: 0.5, height: 0.2),
                        timeRange: compRange,
                        isCaption: false,
                        rotation: overlay.rotation,
                        scale: overlay.scale,
                        style: nil,  // Overlays don't use caption styling
                        words: nil   // Overlays don't have word-level timing
                    )
                    textLayers.append(item)
                }
            }
        }
        
        return textLayers
    }
}
