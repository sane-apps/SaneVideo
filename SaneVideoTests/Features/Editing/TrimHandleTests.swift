//
//  TrimHandleTests.swift
//  SaneVideoTests
//
//  Tests for trim handle functionality and gesture handling
//

import XCTest
import AVFoundation
@testable import SaneVideo

@MainActor
final class TrimHandleTests: XCTestCase {
    
    var projectState: ProjectState!
    
    override func setUp() async throws {
        projectState = ProjectState(projectStore: MockProjectStore())
        projectState.startNewProject()
    }
    
    func testTrimHandleLeftTrim() {
        // Create a clip
        let clip = VideoClip(
            url: URL(fileURLWithPath: "/tmp/test.mov"),
            duration: CMTime(seconds: 10, preferredTimescale: 600)
        )
        projectState.addClip(clip)
        
        guard let addedClip = projectState.currentProject?.timeline.tracks.first?.clips.first else {
            XCTFail("Clip should be added")
            return
        }
        
        let originalTrimStart = addedClip.trimStart
        let trimAmount = CMTime(seconds: 2, preferredTimescale: 600)
        let newTrimStart = CMTimeAdd(originalTrimStart, trimAmount)
        
        // Simulate trim start update
        projectState.updateClipTrim(
            clipId: addedClip.id,
            trimStart: newTrimStart,
            trimEnd: nil,
            startTime: nil
        )
        
        let updatedClip = projectState.currentProject?.timeline.tracks.first?.clips.first
        XCTAssertNotNil(updatedClip, "Clip should still exist")
        XCTAssertEqual(updatedClip?.trimStart.seconds ?? -1, newTrimStart.seconds, accuracy: 0.01, "Trim start should be updated")
    }
    
    func testTrimHandleRightTrim() {
        // Create a clip
        let clip = VideoClip(
            url: URL(fileURLWithPath: "/tmp/test.mov"),
            duration: CMTime(seconds: 10, preferredTimescale: 600)
        )
        projectState.addClip(clip)
        
        guard let addedClip = projectState.currentProject?.timeline.tracks.first?.clips.first else {
            XCTFail("Clip should be added")
            return
        }
        
        let originalTrimEnd = addedClip.trimEnd
        let trimAmount = CMTime(seconds: 2, preferredTimescale: 600)
        let newTrimEnd = CMTimeSubtract(originalTrimEnd, trimAmount)
        
        // Simulate trim end update (note: onTrimEnd callback uses different calculation)
        // The actual implementation calculates: CMTimeSubtract(clip.duration, clampedEnd)
        _ = addedClip.duration
        
        projectState.updateClipTrim(
            clipId: addedClip.id,
            trimStart: nil,
            trimEnd: newTrimEnd,
            startTime: nil
        )
        
        let updatedClip = projectState.currentProject?.timeline.tracks.first?.clips.first
        XCTAssertNotNil(updatedClip, "Clip should still exist")
        XCTAssertLessThan(updatedClip?.trimEnd.seconds ?? 0, originalTrimEnd.seconds, "Trim end should be reduced")
    }

    func testRightTrimHandleReturnsAbsoluteTrimEnd() {
        let clip = VideoClip(
            url: URL(fileURLWithPath: "/tmp/test.mov"),
            duration: CMTime(seconds: 10, preferredTimescale: 600)
        )
        projectState.addClip(clip)

        guard let addedClip = projectState.currentProject?.timeline.tracks.first?.clips.first else {
            XCTFail("Clip should be added")
            return
        }

        let dragDelta = CMTime(seconds: -2, preferredTimescale: 600)
        let resolvedEnd = ClipTrimHandle.resolvedTrimEnd(for: addedClip, delta: dragDelta)

        XCTAssertEqual(resolvedEnd.seconds, 8, accuracy: 0.01, "Right trim should resolve to an absolute media end time")

        projectState.updateClipTrim(
            clipId: addedClip.id,
            trimStart: nil,
            trimEnd: resolvedEnd,
            startTime: nil
        )

        let updatedClip = projectState.currentProject?.timeline.tracks.first?.clips.first
        XCTAssertEqual(updatedClip?.trimEnd.seconds ?? -1, 8, accuracy: 0.01)
        XCTAssertEqual(updatedClip?.effectiveDuration.seconds ?? -1, 8, accuracy: 0.01)
    }
    
    func testTrimHandleClamping() {
        // Create a clip
        let clip = VideoClip(
            url: URL(fileURLWithPath: "/tmp/test.mov"),
            duration: CMTime(seconds: 10, preferredTimescale: 600)
        )
        projectState.addClip(clip)
        
        guard let addedClip = projectState.currentProject?.timeline.tracks.first?.clips.first else {
            XCTFail("Clip should be added")
            return
        }
        
        // Try to trim beyond clip duration (should clamp)
        let excessiveTrim = CMTime(seconds: 20, preferredTimescale: 600)
        let newTrimEnd = CMTimeAdd(addedClip.trimEnd, excessiveTrim)
        
        projectState.updateClipTrim(
            clipId: addedClip.id,
            trimStart: nil,
            trimEnd: newTrimEnd,
            startTime: nil
        )
        
        let updatedClip = projectState.currentProject?.timeline.tracks.first?.clips.first
        XCTAssertNotNil(updatedClip, "Clip should still exist")
        XCTAssertLessThanOrEqual(updatedClip?.trimEnd.seconds ?? 0, addedClip.duration.seconds, "Trim end should not exceed duration")
    }
    
    func testTrimHandleMinimumDuration() {
        // Create a clip
        let clip = VideoClip(
            url: URL(fileURLWithPath: "/tmp/test.mov"),
            duration: CMTime(seconds: 10, preferredTimescale: 600)
        )
        projectState.addClip(clip)
        
        guard let addedClip = projectState.currentProject?.timeline.tracks.first?.clips.first else {
            XCTFail("Clip should be added")
            return
        }
        
        // Try to trim so start >= end (should maintain minimum 0.1s gap)
        let almostFullTrim = CMTime(seconds: 9.9, preferredTimescale: 600)
        let newTrimStart = almostFullTrim
        
        projectState.updateClipTrim(
            clipId: addedClip.id,
            trimStart: newTrimStart,
            trimEnd: nil,
            startTime: nil
        )
        
        let updatedClip = projectState.currentProject?.timeline.tracks.first?.clips.first
        XCTAssertNotNil(updatedClip, "Clip should still exist")
        
        let duration = updatedClip?.trimEnd.seconds ?? 0 - (updatedClip?.trimStart.seconds ?? 0)
        XCTAssertGreaterThanOrEqual(duration, 0.1, "Should maintain minimum 0.1s duration")
    }
}
