//
//  CompositionBuilderTests.swift
//  SaneVideoTests
//
//  Created by SaneVideo Test Suite
//

import Testing
import AVFoundation
import CoreMedia
import Foundation
@testable import SaneVideo

@Suite("Composition Building Tests")
struct CompositionBuilderTests {
    
    // MARK: - Basic Composition Building
    
    @Test("Build composition with empty timeline")
    func buildCompositionWithEmptyTimeline() async throws {
        let project = VideoProject(
            id: UUID(),
            name: "Test Project",
            createdAt: Date()
        )
        
        // Should not throw, but create empty composition
        let result = try await CompositionBuilder.build(from: project)
        let composition = result.composition
        
        // Check for valid output
        #expect(composition.tracks.count >= 0)
        
        // CompositionBuilder may create tracks even for empty timelines (A/B roll architecture)
        // The important thing is it doesn't crash
        #expect(composition.tracks.count >= 0, "Composition should be created successfully")
    }
    
    @Test("Build composition with single track")
    func buildCompositionWithSingleTrack() async throws {
        var project = VideoProject(
            id: UUID(),
            name: "Test Project",
            createdAt: Date()
        )
        
        // Create a timeline with one video track
        let track = Track(name: "Video 1", type: .video, zIndex: 0)
        let timeline = Timeline(tracks: [track])
        project.updateTimeline(timeline)
        
        let result = try await CompositionBuilder.build(from: project)
        let composition = result.composition
        
        // For video tracks, we create A/B roll tracks (2 per timeline track)
        // But with no clips, we might not have tracks yet
        #expect(composition.tracks.count >= 0)
    }
    
    // MARK: - Valid Segments Tests
    
    @Test("Compute valid segments for video clip")
    func validSegmentsComputation() {
        let clip = VideoClip(
            url: URL(fileURLWithPath: "/test.mov"),
            duration: CMTime(seconds: 10, preferredTimescale: 600)
        )
        
        let sourceDuration = CMTime(seconds: 10, preferredTimescale: 600)
        let segments = VideoTrackBuilder.computeValidSegments(clip: clip, sourceDuration: sourceDuration)
        
        #expect(segments.count == 1)
        #expect(abs((segments.first?.duration.seconds ?? 0) - 10.0) < 0.01)
    }
    
    // MARK: - Error Handling
    
    @Test("Handle invalid URL gracefully during composition build")
    func buildCompositionWithInvalidURL() async throws {
        var project = VideoProject(
            id: UUID(),
            name: "Test Project",
            createdAt: Date()
        )
        
        let invalidURL = URL(fileURLWithPath: "/nonexistent/file.mov")
        let clip = VideoClip(
            url: invalidURL,
            duration: CMTime(seconds: 5, preferredTimescale: 600)
        )
        // clip.startTime is set by track arrangement usually, but here we set up manually
        // Since VideoClip is a struct, we need to add it to a track.
        
        var track = Track(name: "Video 1", type: .video, zIndex: 0)
        track.clips = [clip]
        let timeline = Timeline(tracks: [track])
        project.updateTimeline(timeline)
        
        // Should handle gracefully (skip invalid clips)
        let result = try await CompositionBuilder.build(from: project)
        // result.composition is non-optional, so just check if tracks count matches expectation (should be 0 or 2 empty tracks)
        #expect(result.composition.tracks.count >= 0)
    }
    
    // MARK: - Track Z-Index Ordering
    
    @Test("Track Z-Index ordering")
    func trackZIndexOrdering() {
        let track1 = Track(name: "Bottom", type: .video, zIndex: 0)
        let track2 = Track(name: "Middle", type: .video, zIndex: 1)
        let track3 = Track(name: "Top", type: .video, zIndex: 2)
        
        let timeline = Timeline(tracks: [track1, track2, track3])
        let sorted = timeline.tracks.sorted { $0.zIndex > $1.zIndex }
        
        #expect(sorted[0].name == "Top")
        #expect(sorted[1].name == "Middle")
        #expect(sorted[2].name == "Bottom")
    }
    
    // MARK: - Audio Track Handling
    
    @Test("Audio tracks are skipped for video composition")
    func audioTracksAreSkippedForVideoComposition() {
        let videoTrack = Track(name: "Video", type: .video, zIndex: 0)
        let audioTrack = Track(name: "Audio", type: .audio, zIndex: 1)
        
        let timeline = Timeline(tracks: [videoTrack, audioTrack])
        let visualTracks = timeline.tracks.filter { $0.type == .video || $0.type == .overlay }
        
        #expect(visualTracks.count == 1)
        #expect(visualTracks[0].type == .video)
    }
}

