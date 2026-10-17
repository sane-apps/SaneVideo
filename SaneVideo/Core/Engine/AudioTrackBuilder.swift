import AVFoundation
import CoreMedia

enum AudioTrackBuilder {

    private struct VolumeRampRequest {
        let params: AVMutableAudioMixInputParameters
        let trackID: CMPersistentTrackID
        let fromStartVolume: Float
        let toEndVolume: Float
        let timeRange: CMTimeRange
        let label: String
    }

    /// Enhanced audio files must be duration-aligned with the clip's original timeline.
    /// If they drift (e.g., resample-induced duration mismatch), we fall back to original audio to prevent A/V desync.
    ///
    /// Internal for tests.
    static func shouldUseEnhancedAudio(clipDuration: CMTime, enhancedDuration: CMTime) -> Bool {
        guard clipDuration > .zero, enhancedDuration > .zero else { return false }
        let toleranceSeconds = 0.05
        return abs(enhancedDuration.seconds - clipDuration.seconds) <= toleranceSeconds
    }

    /// Build audio tracks with A/B roll architecture for visual timeline tracks
    static func buildVisualAudio(
        from visualTimelineTracks: [Track],
        into composition: AVMutableComposition,
        assetCache: inout [URL: AVURLAsset]
    ) async throws -> [AVMutableAudioMixInputParameters] {

        var audioMixParams: [AVMutableAudioMixInputParameters] = []
        var scheduledRampRangesByTrackID: [CMPersistentTrackID: [CMTimeRange]] = [:]

        func rangesOverlap(_ a: CMTimeRange, _ b: CMTimeRange, toleranceSeconds: Double = 0.000_5) -> Bool {
            let aStart = a.start.seconds
            let aEnd = (CMTimeAdd(a.start, a.duration)).seconds
            let bStart = b.start.seconds
            let bEnd = (CMTimeAdd(b.start, b.duration)).seconds

            // Treat touching edges as non-overlapping (with a tiny tolerance to avoid floating-point fuzz).
            if abs(aEnd - bStart) <= toleranceSeconds || abs(bEnd - aStart) <= toleranceSeconds {
                return false
            }

            return aStart < bEnd && bStart < aEnd
        }

        func setVolumeRampSafely(_ request: VolumeRampRequest) {
            guard CMTimeCompare(request.timeRange.duration, .zero) > 0 else { return }

            let existing = scheduledRampRangesByTrackID[request.trackID, default: []]
            if existing.contains(where: { rangesOverlap($0, request.timeRange) }) {
                AppLogger.timeline.warning(
                    "⚠️ AudioTrackBuilder: Skipping overlapping volume ramp (\(request.label)) on trackID=\(request.trackID) " +
                        "range=[\(request.timeRange.start.seconds)s .. " +
                        "\(CMTimeAdd(request.timeRange.start, request.timeRange.duration).seconds)s]"
                )
                return
            }

            request.params.setVolumeRamp(
                fromStartVolume: request.fromStartVolume,
                toEndVolume: request.toEndVolume,
                timeRange: request.timeRange
            )
            scheduledRampRangesByTrackID[request.trackID, default: []].append(request.timeRange)
        }

        let audioTrackA = composition.addMutableTrack(withMediaType: .audio, preferredTrackID: kCMPersistentTrackID_Invalid)
        let audioTrackB = composition.addMutableTrack(withMediaType: .audio, preferredTrackID: kCMPersistentTrackID_Invalid)

        guard let ata = audioTrackA, let atb = audioTrackB else { return [] }

        for timelineTrack in visualTimelineTracks {
            var useTrackA = true
            let sortedClips = timelineTrack.clips.sorted { $0.startTime < $1.startTime }

            for clip in sortedClips {
                // Must mirror VideoTrackBuilder's A/B track selection semantics.
                // When smooth cuts are enabled, we also alternate tracks *within* a clip.
                // If we only toggle per-clip, audio can end up on a different A/B track pattern than video,
                // which causes perceived A/V sync issues and can create overlapping segments on the same track.
                let targetAudioTrack = useTrackA ? ata : atb

                // Use enhanced audio only when its duration matches the clip; a mismatch breaks insertTimeRange or drifts A/V sync.
                var selectedAudioURL = clip.enhancedAudioURL ?? clip.url
                var asset = getAsset(for: selectedAudioURL, cache: &assetCache)

                if clip.enhancedAudioURL != nil {
                    let enhancedDuration = (try? await asset.load(.duration)) ?? .zero
                    if !shouldUseEnhancedAudio(clipDuration: clip.duration, enhancedDuration: enhancedDuration) {
                        AppLogger.timeline.warning(
                            "⚠️ AudioTrackBuilder: Enhanced audio duration mismatch for \(clip.url.lastPathComponent). " +
                                "clip=\(clip.duration.seconds)s enhanced=\(enhancedDuration.seconds)s. Falling back to original audio."
                        )
                        selectedAudioURL = clip.url
                        asset = getAsset(for: selectedAudioURL, cache: &assetCache)
                    }
                }

                guard let assetAudioTrack = try? await asset.load(.tracks).first(where: { $0.mediaType == .audio }) else {
                    AppLogger.timeline.warning("⚠️ AudioTrackBuilder: Clip \(clip.url.lastPathComponent) has no audio track, skipping")
                    continue
                }

                // Time segments by the original video duration, not the enhanced file's: resampling changes its length slightly, and trims are relative to the video.
                let sourceDuration = CMTimeSubtract(min(clip.trimEnd, clip.duration), clip.trimStart)
                guard sourceDuration > .zero else { continue }

                let insertStart = clip.startTime

                // Same segments as the video so audio stays in sync.
                let audioValidSegments = VideoTrackBuilder.computeValidSegments(clip: clip, sourceDuration: sourceDuration)

                // Smooth cut overlap (internal to clip) must be expressed in PLAYED time, and mapped to SOURCE time.
                // This keeps audio and video using the same overlap window, preventing perceived A/V desync at jump cuts.
                let overlap = TimeUtils.smoothCutOverlap(clipSpeed: clip.speed, overlapPlayedSeconds: 0.15)

                // Gating data is computed once per clip, not per segment.
                let gatingSegments: [SoundAnalysisService.GatingSegment]? = clip.isGatingEnabled
                    ? try? await ServiceContainer.shared.soundAnalysisService.generateGatingMetadata(for: selectedAudioURL)
                    : nil

                var currentAudioInsertStart = insertStart
                var segmentAudioTrack: AVMutableCompositionTrack = targetAudioTrack
                var previousSegmentAudioTrack: AVMutableCompositionTrack?

                for (segIndex, segment) in audioValidSegments.enumerated() {
                    var finalSegment = segment
                    var segmentInsertStart = currentAudioInsertStart
                    var actualOverlapPlayed = CMTime.zero

                    if clip.useSmoothCutForRemovals && audioValidSegments.count > 1 && segIndex > 0 {
                        // Clamp overlap so we never extend before trimmed start.
                        let maxBackwards = CMTimeSubtract(segment.start, clip.trimStart)
                        var actualOverlapSource = CMTimeMinimum(overlap.source, maxBackwards)
                        // Clamp overlap so we never exceed the previous segment length (prevents triple-overlap on A/B tracks).
                        let prevSegment = audioValidSegments[segIndex - 1]
                        actualOverlapSource = CMTimeMinimum(actualOverlapSource, prevSegment.duration)

                        if actualOverlapSource > .zero {
                            actualOverlapPlayed = CMTimeMultiplyByFloat64(
                                actualOverlapSource, multiplier: 1.0 / max(clip.speed, 0.000_001))

                            finalSegment.start = CMTimeSubtract(finalSegment.start, actualOverlapSource)
                            finalSegment.duration = CMTimeAdd(finalSegment.duration, actualOverlapSource)
                            segmentInsertStart = CMTimeSubtract(segmentInsertStart, actualOverlapPlayed)
                        }
                    }

                    try? segmentAudioTrack.insertTimeRange(finalSegment, of: assetAudioTrack, at: segmentInsertStart)

                    let segmentDuration = finalSegment.duration
                    let playDuration = CMTimeMultiplyByFloat64(segmentDuration, multiplier: 1.0 / clip.speed)

                    if clip.speed != 1.0 {
                        let scaleRange = CMTimeRange(start: segmentInsertStart, duration: segmentDuration)
                        segmentAudioTrack.scaleTimeRange(scaleRange, toDuration: playDuration)
                    }

                    let finalVolume = clip.isMuted ? 0.0 : clip.volume

                    AppLogger.timeline.info("🔊 AudioTrackBuilder: clip \(clip.url.lastPathComponent) - isMuted=\(clip.isMuted), volume=\(clip.volume), finalVolume=\(finalVolume)")

                    func getOrCreateParams(for track: AVMutableCompositionTrack) -> AVMutableAudioMixInputParameters {
                        if let existing = audioMixParams.first(where: { $0.trackID == track.trackID }) {
                            return existing
                        }
                        let created = AVMutableAudioMixInputParameters(track: track)
                        audioMixParams.append(created)
                        return created
                    }

                    let currentParams = getOrCreateParams(for: segmentAudioTrack)
                    let outgoingParams: AVMutableAudioMixInputParameters? = {
                        guard let prev = previousSegmentAudioTrack else { return nil }
                        return getOrCreateParams(for: prev)
                    }()

                    // Click prevention:
                    // - Always fade-in at clip start
                    // - If smooth cuts are enabled, crossfade at each internal cut using the overlap window
                    // - Always fade-out at clip end
                    let fadeDuration = CMTime(seconds: 0.05, preferredTimescale: 600)

                    let isFirstSegment = segIndex == 0
                    let isLastSegment = segIndex == audioValidSegments.count - 1
                    let segmentEnd = CMTimeAdd(segmentInsertStart, playDuration)

                    if clip.useSmoothCutForRemovals && segIndex > 0 && actualOverlapPlayed > .zero {
                        // Crossfade the overlap region: outgoing ramps down while incoming ramps up.
                        let safeOverlap = CMTimeMinimum(actualOverlapPlayed, playDuration)
                        if safeOverlap > .zero {
                            let rampUpRange = CMTimeRange(start: segmentInsertStart, duration: safeOverlap)
                            setVolumeRampSafely(VolumeRampRequest(
                                params: currentParams,
                                trackID: segmentAudioTrack.trackID,
                                fromStartVolume: 0.0,
                                toEndVolume: finalVolume,
                                timeRange: rampUpRange,
                                label: "smooth-cut incoming ramp up"
                            ))
                            currentParams.setVolume(finalVolume, at: CMTimeAdd(segmentInsertStart, safeOverlap))

                            // Outgoing ramp down (ends at the cursor boundary = currentAudioInsertStart)
                            if let outgoingParams = outgoingParams {
                                let rampDownStart = CMTimeSubtract(currentAudioInsertStart, safeOverlap)
                                if rampDownStart >= .zero {
                                    let rampDownRange = CMTimeRange(start: rampDownStart, duration: safeOverlap)
                                    setVolumeRampSafely(VolumeRampRequest(
                                        params: outgoingParams,
                                        trackID: previousSegmentAudioTrack?.trackID ?? segmentAudioTrack.trackID,
                                        fromStartVolume: finalVolume,
                                        toEndVolume: 0.0,
                                        timeRange: rampDownRange,
                                        label: "smooth-cut outgoing ramp down"
                                    ))
                                }
                            }
                        }

                        // Always fade out at the very end of the clip to avoid an abrupt cutoff.
                        if isLastSegment {
                            let safeFadeDuration = CMTimeMinimum(fadeDuration, playDuration)
                            if safeFadeDuration > .zero,
                               CMTimeCompare(playDuration, CMTimeMultiply(safeFadeDuration, multiplier: 2)) > 0 {
                                let availableForFadeOut = CMTimeSubtract(playDuration, safeFadeDuration)
                                let actualFadeOutDuration = CMTimeMinimum(safeFadeDuration, availableForFadeOut)
                                let fadeOutStart = CMTimeSubtract(segmentEnd, actualFadeOutDuration)
                                if CMTimeCompare(fadeOutStart, CMTimeAdd(segmentInsertStart, safeFadeDuration)) > 0 {
                                    let fadeOutRange = CMTimeRange(start: fadeOutStart, duration: actualFadeOutDuration)
                                    setVolumeRampSafely(VolumeRampRequest(
                                        params: currentParams,
                                        trackID: segmentAudioTrack.trackID,
                                        fromStartVolume: finalVolume,
                                        toEndVolume: 0.0,
                                        timeRange: fadeOutRange,
                                        label: "clip end fade out (smooth)"
                                    ))
                                }
                            }
                        }
                    } else {
                        // Non-smooth path: use short fade in/out to prevent clicks at segment edges.
                        let safeFadeDuration = CMTimeMinimum(fadeDuration, playDuration)
                        if safeFadeDuration > .zero {
                            if isFirstSegment {
                                let fadeInRange = CMTimeRange(start: segmentInsertStart, duration: safeFadeDuration)
                                setVolumeRampSafely(VolumeRampRequest(
                                    params: currentParams,
                                    trackID: segmentAudioTrack.trackID,
                                    fromStartVolume: 0.0,
                                    toEndVolume: finalVolume,
                                    timeRange: fadeInRange,
                                    label: "clip start fade in"
                                ))
                                currentParams.setVolume(finalVolume, at: CMTimeAdd(segmentInsertStart, safeFadeDuration))
                            } else {
                                currentParams.setVolume(finalVolume, at: segmentInsertStart)
                            }

                            if isLastSegment && CMTimeCompare(playDuration, CMTimeMultiply(safeFadeDuration, multiplier: 2)) > 0 {
                                let availableForFadeOut = CMTimeSubtract(playDuration, safeFadeDuration)
                                let actualFadeOutDuration = CMTimeMinimum(safeFadeDuration, availableForFadeOut)
                                let fadeOutStart = CMTimeSubtract(segmentEnd, actualFadeOutDuration)
                                if CMTimeCompare(fadeOutStart, CMTimeAdd(segmentInsertStart, safeFadeDuration)) > 0 {
                                    let fadeOutRange = CMTimeRange(start: fadeOutStart, duration: actualFadeOutDuration)
                                    setVolumeRampSafely(VolumeRampRequest(
                                        params: currentParams,
                                        trackID: segmentAudioTrack.trackID,
                                        fromStartVolume: finalVolume,
                                        toEndVolume: 0.0,
                                        timeRange: fadeOutRange,
                                        label: "clip end fade out"
                                    ))
                                }
                            }
                        } else {
                            currentParams.setVolume(finalVolume, at: segmentInsertStart)
                        }
                    }

                    // Duck non-speech when gating is on.
                    if let gatingData = gatingSegments {
                        // Use ramps for gating transitions to prevent clicks
                        let gateRampDuration = CMTime(seconds: 0.03, preferredTimescale: 600)

                        for gatingSegment in gatingData where !gatingSegment.shouldOpenGate {
                            // Gating times are in FILE TIME - check if they overlap with this audio segment
                            let gatingStart = gatingSegment.timeRange.start
                            let gatingEnd = gatingSegment.timeRange.end

                            // Audio segment range in file time (from computeValidSegments, with optional overlap extension)
                            let audioSegmentStart = finalSegment.start
                            let audioSegmentEnd = finalSegment.end

                            guard CMTimeCompare(gatingEnd, audioSegmentStart) > 0,
                                  CMTimeCompare(gatingStart, audioSegmentEnd) < 0 else {
                                continue
                            }

                            let clampedGatingStart = CMTimeMaximum(gatingStart, audioSegmentStart)
                            let clampedGatingEnd = CMTimeMinimum(gatingEnd, audioSegmentEnd)

                            // Map to composition time:
                            // offset = (gatingTime - audioSegmentStart) / speed
                            let offsetFromSegmentStart = CMTimeSubtract(clampedGatingStart, audioSegmentStart)
                            let offsetFromSegmentEnd = CMTimeSubtract(clampedGatingEnd, audioSegmentStart)
                            let scaledOffsetStart = CMTimeMultiplyByFloat64(offsetFromSegmentStart, multiplier: 1.0 / clip.speed)
                            let scaledOffsetEnd = CMTimeMultiplyByFloat64(offsetFromSegmentEnd, multiplier: 1.0 / clip.speed)

                            let compositionStart = CMTimeAdd(segmentInsertStart, scaledOffsetStart)
                            let compositionEnd = CMTimeAdd(segmentInsertStart, scaledOffsetEnd)
                            let gatingDuration = CMTimeSubtract(compositionEnd, compositionStart)

                            let segmentEnd = CMTimeAdd(segmentInsertStart, playDuration)
                            guard CMTimeCompare(compositionStart, segmentEnd) < 0,
                                  CMTimeCompare(gatingDuration, .zero) > 0 else {
                                continue
                            }

                            let safeGateRampDuration = CMTimeMinimum(gateRampDuration, gatingDuration)
                            guard CMTimeCompare(safeGateRampDuration, .zero) > 0 else { continue }

                            let rampDownRange = CMTimeRange(start: compositionStart, duration: safeGateRampDuration)
                            if CMTimeCompare(CMTimeAdd(compositionStart, safeGateRampDuration), segmentEnd) <= 0 {
                                setVolumeRampSafely(VolumeRampRequest(
                                    params: currentParams,
                                    trackID: segmentAudioTrack.trackID,
                                    fromStartVolume: finalVolume,
                                    toEndVolume: 0.0,
                                    timeRange: rampDownRange,
                                    label: "gating ramp down"
                                ))
                            }

                            if CMTimeCompare(compositionEnd, CMTimeAdd(compositionStart, safeGateRampDuration)) > 0 {
                                let rampUpStart = CMTimeSubtract(compositionEnd, safeGateRampDuration)
                                if CMTimeCompare(rampUpStart, CMTimeAdd(compositionStart, safeGateRampDuration)) > 0 {
                                    let rampUpRange = CMTimeRange(start: rampUpStart, duration: safeGateRampDuration)
                                    setVolumeRampSafely(VolumeRampRequest(
                                        params: currentParams,
                                        trackID: segmentAudioTrack.trackID,
                                        fromStartVolume: 0.0,
                                        toEndVolume: finalVolume,
                                        timeRange: rampUpRange,
                                        label: "gating ramp up"
                                    ))
                                }
                            }
                        }
                    }

                    // Preserve timeline timing: advance by the ORIGINAL (non-extended) segment duration.
                    let originalPlayDuration = CMTimeMultiplyByFloat64(segment.duration, multiplier: 1.0 / clip.speed)
                    currentAudioInsertStart = CMTimeAdd(currentAudioInsertStart, originalPlayDuration)

                    // Track switching for internal smooth cuts (matches video behavior).
                    if clip.useSmoothCutForRemovals {
                        previousSegmentAudioTrack = segmentAudioTrack
                        segmentAudioTrack = (segmentAudioTrack === ata) ? atb : ata
                    } else {
                        previousSegmentAudioTrack = segmentAudioTrack
                    }
                }

                // Mirror VideoTrackBuilder:
                // `segmentAudioTrack` has already been toggled for the next segment, so it represents
                // the "next track" after finishing the clip's internal segments.
                // Update `useTrackA` so the next clip continues on the expected track parity.
                useTrackA = (segmentAudioTrack === ata)
                useTrackA.toggle()
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

                let playDuration = CMTimeMultiplyByFloat64(sourceDuration, multiplier: 1.0 / clip.speed)
                if clip.speed != 1.0 {
                    let scaleRange = CMTimeRange(start: clip.startTime, duration: sourceDuration)
                    targetTrack.scaleTimeRange(scaleRange, toDuration: playDuration)
                }

                // Volume with fade ramps to prevent clicks
                let finalVolume = clip.isMuted ? 0.0 : clip.volume

                let fadeDuration = CMTime(seconds: 0.05, preferredTimescale: 600)

                // Validate time range before calling setVolumeRamp to prevent crashes
                let safeFadeDuration = CMTimeMinimum(fadeDuration, playDuration)
                guard CMTimeCompare(safeFadeDuration, .zero) > 0 else {
                    // Skip fade if clip is too short
                    trackParams.setVolume(finalVolume, at: clip.startTime)
                    continue
                }

                let fadeInRange = CMTimeRange(start: clip.startTime, duration: safeFadeDuration)
                trackParams.setVolumeRamp(fromStartVolume: 0.0, toEndVolume: finalVolume, timeRange: fadeInRange)

                let afterFadeIn = CMTimeAdd(clip.startTime, safeFadeDuration)
                trackParams.setVolume(finalVolume, at: afterFadeIn)

                // Fade out any clip longer than twice the fade; a 3x limit caused clicks on 0.05-0.15 s clips.
                let clipEnd = CMTimeAdd(clip.startTime, playDuration)
                if CMTimeCompare(playDuration, CMTimeMultiply(safeFadeDuration, multiplier: 2)) > 0 {
                    // Calculate proportional fade-out duration for short clips
                    let availableForFadeOut = CMTimeSubtract(playDuration, safeFadeDuration)
                    let actualFadeOutDuration = CMTimeMinimum(safeFadeDuration, availableForFadeOut)
                    let fadeOutStart = CMTimeSubtract(clipEnd, actualFadeOutDuration)
                    if CMTimeCompare(fadeOutStart, CMTimeAdd(clip.startTime, safeFadeDuration)) > 0 {
                        let fadeOutRange = CMTimeRange(start: fadeOutStart, duration: actualFadeOutDuration)
                        trackParams.setVolumeRamp(fromStartVolume: finalVolume, toEndVolume: 0.0, timeRange: fadeOutRange)
                    }
                }

                if clip.isGatingEnabled {
                    let gatingSegments = try? await ServiceContainer.shared.soundAnalysisService.generateGatingMetadata(for: clip.url)
                    if let segments = gatingSegments {
                        let gateRampDuration = CMTime(seconds: 0.03, preferredTimescale: 600)
                        let clipEnd = CMTimeAdd(clip.startTime, playDuration)

                        for gatingSegment in segments where !gatingSegment.shouldOpenGate {
                            // Gating times are in FILE TIME - must map through trimStart and speed
                            let gatingStart = gatingSegment.timeRange.start
                            let gatingEnd = gatingSegment.timeRange.end

                            guard CMTimeCompare(gatingEnd, clip.trimStart) > 0,
                                  CMTimeCompare(gatingStart, clip.trimEnd) < 0 else {
                                continue
                            }

                            let clampedGatingStart = CMTimeMaximum(gatingStart, clip.trimStart)
                            let clampedGatingEnd = CMTimeMinimum(gatingEnd, clip.trimEnd)

                            // Map to composition time: (gatingTime - trimStart) / speed + clipStart
                            let offsetFromTrimStart = CMTimeSubtract(clampedGatingStart, clip.trimStart)
                            let offsetFromTrimEnd = CMTimeSubtract(clampedGatingEnd, clip.trimStart)
                            let scaledOffsetStart = CMTimeMultiplyByFloat64(offsetFromTrimStart, multiplier: 1.0 / clip.speed)
                            let scaledOffsetEnd = CMTimeMultiplyByFloat64(offsetFromTrimEnd, multiplier: 1.0 / clip.speed)

                            let compositionStart = CMTimeAdd(clip.startTime, scaledOffsetStart)
                            let compositionEnd = CMTimeAdd(clip.startTime, scaledOffsetEnd)
                            let gatingDuration = CMTimeSubtract(compositionEnd, compositionStart)

                            guard CMTimeCompare(compositionStart, clipEnd) < 0,
                                  CMTimeCompare(gatingDuration, .zero) > 0 else {
                                continue
                            }

                            let safeGateRampDuration = CMTimeMinimum(gateRampDuration, gatingDuration)
                            guard CMTimeCompare(safeGateRampDuration, .zero) > 0 else { continue }

                            let rampDownRange = CMTimeRange(start: compositionStart, duration: safeGateRampDuration)
                            if CMTimeCompare(CMTimeAdd(compositionStart, safeGateRampDuration), clipEnd) <= 0 {
                                trackParams.setVolumeRamp(fromStartVolume: finalVolume, toEndVolume: 0.0, timeRange: rampDownRange)
                            }

                            if CMTimeCompare(compositionEnd, CMTimeAdd(compositionStart, safeGateRampDuration)) > 0 {
                                let rampUpStart = CMTimeSubtract(compositionEnd, safeGateRampDuration)
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
