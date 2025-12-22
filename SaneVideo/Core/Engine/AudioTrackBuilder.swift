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

                    trackParams?.setVolume(finalVolume, at: currentAudioInsertStart)

                    // SEMANTIC GATING: Apply volume drops for non-speech if enabled
                    if clip.isGatingEnabled {
                        let gatingSegments = try? await ServiceContainer.shared.soundAnalysisService.generateGatingMetadata(for: audioURL)
                        if let segments = gatingSegments {
                            for segment in segments where !segment.shouldOpenGate {
                                // Map segment time to composition time
                                // Simple mapping for now, assuming 1:1 or handled by trim
                                let compositionStart = CMTimeAdd(currentAudioInsertStart, segment.timeRange.start)
                                trackParams?.setVolume(0.0, at: compositionStart)
                                trackParams?.setVolume(finalVolume, at: CMTimeAdd(compositionStart, segment.timeRange.duration))
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

                // Volume
                let finalVolume = clip.isMuted ? 0.0 : clip.volume
                trackParams.setVolume(finalVolume, at: clip.startTime)
                
                // SEMANTIC GATING
                if clip.isGatingEnabled {
                    let gatingSegments = try? await ServiceContainer.shared.soundAnalysisService.generateGatingMetadata(for: clip.url)
                    if let segments = gatingSegments {
                        for segment in segments where !segment.shouldOpenGate {
                            let compositionStart = CMTimeAdd(clip.startTime, segment.timeRange.start)
                            trackParams.setVolume(0.0, at: compositionStart)
                            trackParams.setVolume(finalVolume, at: CMTimeAdd(compositionStart, segment.timeRange.duration))
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
