import AVFoundation
@testable import SaneVideo
import XCTest

@MainActor
final class TimelineTests: XCTestCase {
    var timeline: Timeline!

    override func setUp() {
        super.setUp()
        timeline = Timeline()
    }

    func testAddClip() {
        let clip = VideoClip(url: URL(fileURLWithPath: "/tmp/test.mp4"), duration: CMTime(seconds: 10, preferredTimescale: 600))
        
        // Ensure at least one track
        var track = Track(name: "Background", type: .video, zIndex: 0)
        track.clips.append(clip)
        timeline.tracks = [track]
        
        XCTAssertEqual(timeline.tracks.first?.clips.count, 1)
        XCTAssertEqual(timeline.duration.seconds, 10.0)
    }
    
    func testMoveClip() {
        let clip1 = VideoClip(url: URL(fileURLWithPath: "/tmp/1.mp4"), duration: CMTime(seconds: 5, preferredTimescale: 600))
        let clip2 = VideoClip(url: URL(fileURLWithPath: "/tmp/2.mp4"), duration: CMTime(seconds: 5, preferredTimescale: 600))
        let clip3 = VideoClip(url: URL(fileURLWithPath: "/tmp/3.mp4"), duration: CMTime(seconds: 5, preferredTimescale: 600))
        
        var track = Track(name: "Main", type: .video, zIndex: 0)
        track.clips = [clip1, clip2, clip3]
        timeline.tracks = [track]
        
        // Move clip 3 (index 2) to index 0 within the track
        timeline.tracks[0].clips.move(fromOffsets: IndexSet(integer: 2), toOffset: 0)
        
        // Recalculate helper (simulating ProjectState logic)
        var cumulativeTime = CMTime.zero
        for i in 0..<timeline.tracks[0].clips.count {
            timeline.tracks[0].clips[i].startTime = cumulativeTime
            cumulativeTime = CMTimeAdd(cumulativeTime, timeline.tracks[0].clips[i].effectiveDuration)
        }
        
        let updatedClips = timeline.tracks[0].clips
        XCTAssertEqual(updatedClips[0].id, clip3.id)
        XCTAssertEqual(updatedClips[1].id, clip1.id)
        XCTAssertEqual(updatedClips[2].id, clip2.id) // Indices shift: 3->0, 1->1, 2->2
        
        // Verify start times
        XCTAssertEqual(updatedClips[0].startTime.seconds, 0)
        XCTAssertEqual(updatedClips[1].startTime.seconds, 5)
        XCTAssertEqual(updatedClips[2].startTime.seconds, 10)
    }

    func testSplitClipLogic() {
        // Setup
        var clip = VideoClip(url: URL(fileURLWithPath: "/tmp/test.mp4"), duration: CMTime(seconds: 10, preferredTimescale: 600))
        clip.startTime = .zero
        
        let splitTime = CMTime(seconds: 5, preferredTimescale: 600)
        
        // Manual Split Logic (mirroring ProjectState)
        var firstPart = clip
        firstPart.trimEnd = splitTime
        
        var secondPart = clip
        secondPart = VideoClip(url: clip.url, duration: clip.duration)
        secondPart.trimStart = splitTime
        secondPart.trimEnd = clip.trimEnd
        
        XCTAssertEqual(firstPart.effectiveDuration.seconds, 5.0)
        XCTAssertEqual(secondPart.effectiveDuration.seconds, 5.0)
        
        // Verify timeline integration
        var track = Track(name: "Video Track", type: .video, zIndex: 0)
        track.clips = [firstPart, secondPart]
        timeline.tracks = [track]
        
        XCTAssertEqual(timeline.duration.seconds, 10.0)
    }
}
