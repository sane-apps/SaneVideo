//
//  AudioTrackBuilder.swift
//  SaneVideo
//
//  Created by SaneVideo Refactor
//

import AVFoundation
import CoreMedia

/// Helper for building audio tracks from timeline clips
enum AudioTrackBuilder {

    /// Build audio tracks with A/B roll architecture for visual timeline tracks
    static func buildVisualAudio(
        from visualTimelineTracks: [Track],
        into composition: AVMutableComposition,
        assetCache: inout [URL: AVURLAsset]
    ) async throws -> [AVMutableAudioMixInputParameters] {

        var audioMixParams: [AVMutableAudioMixInputParameters] = []

        // A/B Audio Tracks
        let audioTrackA = composition.addMutableTrack(withMediaType: .audio, preferredTrackID: kCMPersistentTrackID_Invalid)
        let audioTrackB = composition.addMutableTrack(withMediaType: .audio, preferredTrackID: kCMPersistentTrackID_Invalid)

        guard let ata = audioTrackA, let atb = audioTrackB else { return [] }

        for timelineTrack in visualTimelineTracks {
            var useTrackA = true
            let sortedClips = timelineTrack.clips.sorted { $0.startTime < $1.startTime }

            for clip in sortedClips {
                let targetAudioTrack = useTrackA ? ata : atb
                useTrackA.toggle()

                // AUDIO POLISH: Use enhanced audio if available
                let audioURL = clip.enhancedAudioURL ?? clip.url
                let asset = getAsset(for: audioURL, cache: &assetCache)

                // Check for audio
                guard let assetAudioTrack = try? await asset.load(.tracks).first(where: { $0.mediaType == .audio }) else { continue }
                let assetDuration = (try? await asset.load(.duration)) ?? .zero

                let sourceDuration = CMTimeSubtract(min(clip.trimEnd, assetDuration), clip.trimStart)
                guard sourceDuration > .zero else { continue }

                let insertStart = clip.startTime

                // Compute Valid Segments (Copied from Video Logic for Sync)
                let audioValidSegments = VideoTrackBuilder.computeValidSegments(clip: clip, sourceDuration: sourceDuration)

                // Insert Audio Segments
                var currentAudioInsertStart = insertStart

                for segment in audioValidSegments {
                    try? targetAudioTrack.insertTimeRange(segment, of: assetAudioTrack, at: currentAudioInsertStart)

                    let segmentDuration = segment.duration
                    let playDuration = CMTimeMultiplyByFloat64(segmentDuration, multiplier: 1.0 / clip.speed)

                    if clip.speed != 1.0 {
                        let scaleRange = CMTimeRange(start: currentAudioInsertStart, duration: segmentDuration)
                        targetAudioTrack.scaleTimeRange(scaleRange, toDuration: playDuration)
                    }

                    // Volume Automation per segment
                    let finalVolume = clip.isMuted ? 0.0 : clip.volume

                    // Find or create params
                    var trackParams = audioMixParams.first(where: { $0.trackID == targetAudioTrack.trackID })
                    if trackParams == nil {
                        trackParams = AVMutableAudioMixInputParameters(track: targetAudioTrack)
                        audioMixParams.append(trackParams!)
                    }

                    // CRITICAL FIX: Add fade ramp to prevent audio clicks at clip boundaries
                    // Use 50ms (0.05s) fade in/out at clip edges
                    let fadeDuration = CMTime(seconds: 0.05, preferredTimescale: 600)

                    // CRITICAL FIX: Validate time range before calling setVolumeRamp to prevent crashes
                    // Ensure fade duration doesn't exceed segment duration
                    let safeFadeDuration = CMTimeMinimum(fadeDuration, playDuration)
                    guard CMTimeCompare(safeFadeDuration, .zero) > 0 else {
                        // Skip fade if segment is too short
                        trackParams?.setVolume(finalVolume, at: currentAudioInsertStart)
                        currentAudioInsertStart = CMTimeAdd(currentAudioInsertStart, playDuration)
                        continue
                    }

                    let fadeInRange = CMTimeRange(start: currentAudioInsertStart, duration: safeFadeDuration)
                    trackParams?.setVolumeRamp(fromStartVolume: 0.0, toEndVolume: finalVolume, timeRange: fadeInRange)

                    // Set steady volume after fade-in
                    let afterFadeIn = CMTimeAdd(currentAudioInsertStart, fadeDuration)
                    trackParams?.setVolume(finalVolume, at: afterFadeIn)

                    // Add fade-out at segment end (only if segment is long enough)
                    let segmentEnd = CMTimeAdd(currentAudioInsertStart, playDuration)
                    if CMTimeCompare(playDuration, CMTimeMultiply(safeFadeDuration, multiplier: 3)) > 0 {
                        let fadeOutStart = CMTimeSubtract(segmentEnd, safeFadeDuration)
                        // CRITICAL FIX: Validate fade-out range doesn't overlap with fade-in
                        if CMTimeCompare(fadeOutStart, CMTimeAdd(currentAudioInsertStart, safeFadeDuration)) > 0 {
                            let fadeOutRange = CMTimeRange(start: fadeOutStart, duration: safeFadeDuration)
                            trackParams?.setVolumeRamp(fromStartVolume: finalVolume, toEndVolume: 0.0, timeRange: fadeOutRange)
                        }
                    }

                    // SEMANTIC GATING: Apply volume drops for non-speech if enabled
                    if clip.isGatingEnabled {
                        let gatingSegments = try? await ServiceContainer.shared.soundAnalysisService.generateGatingMetadata(for: audioURL)
                        if let segments = gatingSegments {
                            // CRITICAL FIX: Use ramps for gating transitions to prevent clicks
                            let gateRampDuration = CMTime(seconds: 0.03, preferredTimescale: 600) // 30ms gate ramp
                            for segment in segments where !segment.shouldOpenGate {
                                // Map segment time to composition time
                                let compositionStart = CMTimeAdd(currentAudioInsertStart, segment.timeRange.start)
                                let compositionEnd = CMTimeAdd(compositionStart, segment.timeRange.duration)

                                // CRITICAL FIX: Validate time ranges are within segment bounds
                                let segmentStart = currentAudioInsertStart
                                let segmentEnd = CMTimeAdd(currentAudioInsertStart, playDuration)

                                // Ensure compositionStart is within segment
                                guard CMTimeCompare(compositionStart, segmentStart) >= 0,
                                      CMTimeCompare(compositionStart, segmentEnd) < 0 else {
                                    continue
                                }

                                // Ramp down at gate close - validate range
                                let safeGateRampDuration = CMTimeMinimum(gateRampDuration, segment.timeRange.duration)
                                guard CMTimeCompare(safeGateRampDuration, .zero) > 0 else { continue }

                                let rampDownRange = CMTimeRange(start: compositionStart, duration: safeGateRampDuration)
                                // Ensure ramp doesn't extend beyond segment
                                if CMTimeCompare(CMTimeAdd(compositionStart, safeGateRampDuration), segmentEnd) <= 0 {
                                    trackParams?.setVolumeRamp(fromStartVolume: finalVolume, toEndVolume: 0.0, timeRange: rampDownRange)
                                }

                                // Ramp up at gate open - validate range
                                if CMTimeCompare(compositionEnd, CMTimeAdd(compositionStart, safeGateRampDuration)) > 0 {
                                    let rampUpStart = CMTimeSubtract(compositionEnd, safeGateRampDuration)
                                    // Ensure ramp doesn't overlap with ramp down
                                    if CMTimeCompare(rampUpStart, CMTimeAdd(compositionStart, safeGateRampDuration)) > 0 {
                                        let rampUpRange = CMTimeRange(start: rampUpStart, duration: safeGateRampDuration)
                                        trackParams?.setVolumeRamp(fromStartVolume: 0.0, toEndVolume: finalVolume, timeRange: rampUpRange)
                                    }
                                }
                            }
                        }
                    }

                    currentAudioInsertStart = CMTimeAdd(currentAudioInsertStart, playDuration)
                }
            }
        }

        return audioMixParams
    }

    /// Build dedicated audio tracks (for audio-only timeline tracks)
    static func buildDedicatedAudio(
        from audioTimelineTracks: [Track],
        into composition: AVMutableComposition,
        assetCache: inout [URL: AVURLAsset]
    ) async throws -> [AVMutableAudioMixInputParameters] {

        var audioMixParams: [AVMutableAudioMixInputParameters] = []

        for track in audioTimelineTracks {
            guard track.type == .audio else { continue }

            let newAudioTrack = composition.addMutableTrack(withMediaType: .audio, preferredTrackID: kCMPersistentTrackID_Invalid)
            guard let targetTrack = newAudioTrack else { continue }

            let trackParams = AVMutableAudioMixInputParameters(track: targetTrack)
            var hasParamUpdates = false

            for clip in track.clips {
                let asset = getAsset(for: clip.url, cache: &assetCache)
                guard let assetTrack = try? await asset.load(.tracks).first(where: { $0.mediaType == .audio }) else { continue }
                let duration = (try? await asset.load(.duration)) ?? .zero
                let sourceDuration = CMTimeSubtract(min(clip.trimEnd, duration), clip.trimStart)
                let range = CMTimeRange(start: clip.trimStart, duration: sourceDuration)

                try? targetTrack.insertTimeRange(range, of: assetTrack, at: clip.startTime)

                // Speed
                let playDuration = CMTimeMultiplyByFloat64(sourceDuration, multiplier: 1.0 / clip.speed)
                if clip.speed != 1.0 {
                    let scaleRange = CMTimeRange(start: clip.startTime, duration: sourceDuration)
                    targetTrack.scaleTimeRange(scaleRange, toDuration: playDuration)
                }

                // Volume with fade ramps to prevent clicks
                let finalVolume = clip.isMuted ? 0.0 : clip.volume

                // CRITICAL FIX: Add fade ramps at clip boundaries with validation
                let fadeDuration = CMTime(seconds: 0.05, preferredTimescale: 600) // 50ms fade

                // CRITICAL FIX: Validate time range before calling setVolumeRamp to prevent crashes
                let safeFadeDuration = CMTimeMinimum(fadeDuration, playDuration)
                guard CMTimeCompare(safeFadeDuration, .zero) > 0 else {
                    // Skip fade if clip is too short
                    trackParams.setVolume(finalVolume, at: clip.startTime)
                    continue
                }

                let fadeInRange = CMTimeRange(start: clip.startTime, duration: safeFadeDuration)
                trackParams.setVolumeRamp(fromStartVolume: 0.0, toEndVolume: finalVolume, timeRange: fadeInRange)

                // Set steady volume after fade-in
                let afterFadeIn = CMTimeAdd(clip.startTime, safeFadeDuration)
                trackParams.setVolume(finalVolume, at: afterFadeIn)

                // Add fade-out at clip end
                let clipEnd = CMTimeAdd(clip.startTime, playDuration)
                if CMTimeCompare(playDuration, CMTimeMultiply(safeFadeDuration, multiplier: 3)) > 0 {
                    let fadeOutStart = CMTimeSubtract(clipEnd, safeFadeDuration)
                    // CRITICAL FIX: Validate fade-out range doesn't overlap with fade-in
                    if CMTimeCompare(fadeOutStart, CMTimeAdd(clip.startTime, safeFadeDuration)) > 0 {
                        let fadeOutRange = CMTimeRange(start: fadeOutStart, duration: safeFadeDuration)
                        trackParams.setVolumeRamp(fromStartVolume: finalVolume, toEndVolume: 0.0, timeRange: fadeOutRange)
                    }
                }

                // SEMANTIC GATING with smooth ramps
                if clip.isGatingEnabled {
                    let gatingSegments = try? await ServiceContainer.shared.soundAnalysisService.generateGatingMetadata(for: clip.url)
                    if let segments = gatingSegments {
                        let gateRampDuration = CMTime(seconds: 0.03, preferredTimescale: 600) // 30ms gate ramp
                        for segment in segments where !segment.shouldOpenGate {
                            let compositionStart = CMTimeAdd(clip.startTime, segment.timeRange.start)
                            let compositionEnd = CMTimeAdd(compositionStart, segment.timeRange.duration)

                            // CRITICAL FIX: Validate time ranges are within clip bounds
                            let clipStart = clip.startTime
                            let clipEnd = CMTimeAdd(clip.startTime, playDuration)

                            // Ensure compositionStart is within clip
                            guard CMTimeCompare(compositionStart, clipStart) >= 0,
                                  CMTimeCompare(compositionStart, clipEnd) < 0 else {
                                continue
                            }

                            // Ramp down at gate close - validate range
                            let safeGateRampDuration = CMTimeMinimum(gateRampDuration, segment.timeRange.duration)
                            guard CMTimeCompare(safeGateRampDuration, .zero) > 0 else { continue }

                            let rampDownRange = CMTimeRange(start: compositionStart, duration: safeGateRampDuration)
                            // Ensure ramp doesn't extend beyond clip
                            if CMTimeCompare(CMTimeAdd(compositionStart, safeGateRampDuration), clipEnd) <= 0 {
                                trackParams.setVolumeRamp(fromStartVolume: finalVolume, toEndVolume: 0.0, timeRange: rampDownRange)
                            }

                            // Ramp up at gate open - validate range
                            if CMTimeCompare(compositionEnd, CMTimeAdd(compositionStart, safeGateRampDuration)) > 0 {
                                let rampUpStart = CMTimeSubtract(compositionEnd, safeGateRampDuration)
                                // Ensure ramp doesn't overlap with ramp down
                                if CMTimeCompare(rampUpStart, CMTimeAdd(compositionStart, safeGateRampDuration)) > 0 {
                                    let rampUpRange = CMTimeRange(start: rampUpStart, duration: safeGateRampDuration)
                                    trackParams.setVolumeRamp(fromStartVolume: 0.0, toEndVolume: finalVolume, timeRange: rampUpRange)
                                }
                            }
                        }
                    }
                }

                hasParamUpdates = true
            }

            if hasParamUpdates {
                audioMixParams.append(trackParams)
            }
        }

        return audioMixParams
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
}
