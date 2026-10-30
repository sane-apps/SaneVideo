import AVFoundation
import CoreMedia
import Foundation

enum TextLayerBuilder {
    
    static func build(
        from visualTimelineTracks: [Track],
        project: VideoProject
    ) -> [TextLayerItem] {
        
        var textLayers: [TextLayerItem] = []
        
        let defaultCaptionX = 0.1
        let defaultCaptionY = 0.8
        let defaultCaptionW = 0.8
        let defaultCaptionH = 0.15

        // Project-wide caption offset, normalized.
        let captionX = defaultCaptionX + project.captionOffset.width
        let captionY = defaultCaptionY + project.captionOffset.height

        for timelineTrack in visualTimelineTracks {
            for clip in timelineTrack.clips {
                let clipStart = clip.startTime

                for caption in clip.captions.compactMap({ $0.removingWords(in: clip.removedRanges) }) {
                    guard let effective = clip.effectiveRange(for: caption) else { continue }
                    let offset = effective.start
                    let duration = effective.duration

                    let scaledOffset = CMTimeMultiplyByFloat64(offset, multiplier: 1.0 / clip.speed)
                    let scaledDuration = CMTimeMultiplyByFloat64(duration, multiplier: 1.0 / clip.speed)

                    let compStart = CMTimeAdd(clipStart, scaledOffset)
                    let compRange = CMTimeRange(start: compStart, duration: scaledDuration)

                    // Word times are source times; karaoke highlighting compares them with composition time.
                    // A word Clean Up kept can start inside the cut silence before it: start it where it plays.
                    let timelineWords = caption.words?.compactMap { word -> CaptionWord? in
                        let source = clip.firstPlayedSourceTime(
                            atOrAfter: CMTime(seconds: word.start, preferredTimescale: 600))
                        guard let start = clip.timelineTime(forSourceTime: source)?.seconds else { return nil }
                        return CaptionWord(
                            id: word.id,
                            text: word.text,
                            start: start,
                            end: start + max(0, word.end - source.seconds) / max(clip.speed, 0.000_1),
                            probability: word.probability
                        )
                    }

                    let item = TextLayerItem(
                        id: caption.id,
                        text: caption.text,
                        frame: CGRect(x: captionX, y: captionY, width: defaultCaptionW, height: defaultCaptionH),
                        timeRange: compRange,
                        isCaption: true,
                        style: project.captionStyle,
                        words: timelineWords
                    )
                    textLayers.append(item)
                }

                for overlay in clip.overlays {
                    let clipLocalDuration = CMTimeMultiplyByFloat64(
                        clip.effectiveDuration,
                        multiplier: clip.speed
                    )
                    let overlayStart = CMTime(
                        seconds: max(overlay.startTime, 0),
                        preferredTimescale: 600
                    )
                    let overlayEnd = CMTime(
                        seconds: max(overlay.startTime + overlay.duration, overlay.startTime),
                        preferredTimescale: 600
                    )
                    let clampedOverlayEnd = min(overlayEnd, clipLocalDuration)

                    guard clampedOverlayEnd > overlayStart else {
                        continue
                    }

                    // Overlays are stored relative to the clip's local timeline, not raw source time.
                    let originalStart = clip.originalTime(forEffectiveTime: overlayStart)
                    let originalEnd = clip.originalTime(forEffectiveTime: clampedOverlayEnd)

                    guard let effStart = clip.effectiveTime(forOriginalTime: originalStart),
                          let effEnd = clip.effectiveTime(forOriginalTime: originalEnd)
                    else {
                        continue
                    }

                    let offset = effStart
                    let duration = CMTimeSubtract(effEnd, effStart)

                    let scaledStart = CMTimeMultiplyByFloat64(offset, multiplier: 1.0 / clip.speed)
                    let scaledDuration = CMTimeMultiplyByFloat64(duration, multiplier: 1.0 / clip.speed)

                    let compStart = CMTimeAdd(clipStart, scaledStart)
                    let compRange = CMTimeRange(start: compStart, duration: scaledDuration)

                    let item = TextLayerItem(
                        id: overlay.id,
                        text: overlay.text,
                        frame: overlay.normalizedFrame,
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

    static func buildInteractionLayers(
        from visualTimelineTracks: [Track]
    ) -> [InteractionLayerItem] {
        let decoder = JSONDecoder()
        var interactionLayers: [InteractionLayerItem] = []

        for timelineTrack in visualTimelineTracks {
            for clip in timelineTrack.clips {
                let style = clip.interactionOverlayStyle
                guard style.highlightClicks || style.spotlightCursor || style.showKeystrokes else {
                    continue
                }

                let timeRange = CMTimeRange(start: clip.startTime, duration: clip.effectiveDuration)
                let clicks = loadClickItems(for: clip, decoder: decoder, enabled: style.highlightClicks)
                let cursorPath = loadCursorItems(for: clip, decoder: decoder, enabled: style.spotlightCursor)
                let keystrokes = loadKeystrokeItems(for: clip, decoder: decoder, enabled: style.showKeystrokes)

                guard !clicks.isEmpty || !cursorPath.isEmpty || !keystrokes.isEmpty else { continue }

                interactionLayers.append(
                    InteractionLayerItem(
                        clipID: clip.id,
                        timeRange: timeRange,
                        clicks: clicks,
                        cursorPath: cursorPath,
                        keystrokes: keystrokes,
                        style: style
                    )
                )
            }
        }

        return interactionLayers
    }

    private static func loadClickItems(
        for clip: VideoClip,
        decoder: JSONDecoder,
        enabled: Bool
    ) -> [InteractionClickItem] {
        guard enabled,
              let url = clip.clickDataURL,
              FileManager.default.fileExists(atPath: url.path)
        else {
            return []
        }

        do {
            let data = try Data(contentsOf: url)
            let samples = try decoder.decode([ClickSample].self, from: data)
            return samples.compactMap { sample in
                guard let compositionTime = mappedCompositionTime(for: sample.timestamp, clip: clip) else {
                    return nil
                }
                return InteractionClickItem(
                    time: compositionTime,
                    x: sample.x,
                    y: sample.y,
                    button: sample.button
                )
            }
        } catch {
            AppLogger.timeline.warning("Failed to load click data for interaction overlays: \(error.localizedDescription)")
            return []
        }
    }

    private static func loadCursorItems(
        for clip: VideoClip,
        decoder: JSONDecoder,
        enabled: Bool
    ) -> [InteractionCursorItem] {
        guard enabled,
              let url = clip.cursorDataURL,
              FileManager.default.fileExists(atPath: url.path)
        else {
            return []
        }

        do {
            let data = try Data(contentsOf: url)
            let samples = try decoder.decode([CursorSample].self, from: data)
            return samples.compactMap { sample in
                guard let compositionTime = mappedCompositionTime(for: sample.timestamp, clip: clip) else {
                    return nil
                }
                return InteractionCursorItem(
                    time: compositionTime,
                    x: sample.x,
                    y: sample.y,
                    isDown: sample.isDown
                )
            }
        } catch {
            AppLogger.timeline.warning("Failed to load cursor data for interaction overlays: \(error.localizedDescription)")
            return []
        }
    }

    private static func loadKeystrokeItems(
        for clip: VideoClip,
        decoder: JSONDecoder,
        enabled: Bool
    ) -> [InteractionKeystrokeItem] {
        guard enabled,
              let url = clip.keystrokeDataURL,
              FileManager.default.fileExists(atPath: url.path)
        else {
            return []
        }

        do {
            let data = try Data(contentsOf: url)
            let samples = try decoder.decode([KeystrokeSample].self, from: data)
            return samples.compactMap { sample in
                guard let compositionTime = mappedCompositionTime(for: sample.timestamp, clip: clip) else {
                    return nil
                }
                return InteractionKeystrokeItem(
                    id: sample.id,
                    time: compositionTime,
                    text: sample.displayText
                )
            }
        } catch {
            AppLogger.timeline.warning("Failed to load keystroke data for interaction overlays: \(error.localizedDescription)")
            return []
        }
    }

    private static func mappedCompositionTime(
        for timestamp: TimeInterval,
        clip: VideoClip
    ) -> CMTime? {
        let originalTime = CMTime(seconds: timestamp, preferredTimescale: 600)
        guard let effectiveTime = clip.effectiveTime(forOriginalTime: originalTime) else { return nil }
        let scaledTime = CMTimeMultiplyByFloat64(effectiveTime, multiplier: 1.0 / max(clip.speed, 0.000_1))
        return CMTimeAdd(clip.startTime, scaledTime)
    }
}
