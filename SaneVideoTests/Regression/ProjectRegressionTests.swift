//
//  ProjectRegressionTests.swift
//  SaneVideoTests
//

import AVFoundation
import CoreMedia
import Foundation
@testable import SaneVideo
import Testing

@Suite("Project Regression")
struct ProjectRegressionTests {
    /// A project saved by SaneVideo 1.0, with keys from Demo Studio, Commentary Reel and Demo Pack,
    /// which no longer exist. Dates are seconds since 2001 (JSONEncoder's default).
    private static let legacyProjectJSON = """
    {
      "id": "6F1C2D3E-4B5A-4C6D-8E7F-901234567890",
      "name": "Old Walkthrough",
      "createdAt": 780000000,
      "modifiedAt": 780000500,
      "captionStyleName": "Bold",
      "captionOffset": [12, -8],
      "captionFontName": "Avenir Next",
      "currentTime": 4.5,
      "scrollOffset": 0,
      "zoomLevel": 2,
      "presentationPreset": "productWalkthrough",
      "chapterMarkers": [{"title": "Intro", "timestamp": 0}],
      "commentaryMarkers": [{"title": "Point", "startTime": 1, "endTime": 2}],
      "commentaryPlanItems": [],
      "workflowBrief": {"instructions": "", "maxMoments": 5, "voiceBriefSummary": "", "workflow": "commentary"},
      "demoPackSettings": {"includeChapters": true, "includeThumbnail": false},
      "publishMetadata": {"title": "T", "subtitle": "S", "description": "D", "callToAction": "C"},
      "speakerNotes": {
        "text": "Walk through the setup flow", "fontSize": 26, "opacity": 0.8, "widthFraction": 0.7,
        "scrollSpeed": 24, "isMirrored": true, "isVisible": false
      },
      "timeline": {
        "currentTime": 0,
        "duration": 10,
        "tracks": [{
          "id": "11111111-2222-3333-4444-555555555555", "name": "Video", "type": "video",
          "zIndex": 0, "isMuted": false, "isLocked": false,
          "clips": [{
            "id": "AAAAAAAA-BBBB-CCCC-DDDD-EEEEEEEEEEEE", "url": "file:///tmp/old-clip.mov",
            "duration": 10, "trimStart": 0, "trimEnd": 10, "startTime": 0, "speed": 1, "volume": 1,
            "isMuted": false, "opacity": 1, "rotation": 0, "effects": [], "captions": [], "overlays": [],
            "privacyRegions": [], "removedRanges": [], "useSmoothCutForRemovals": false,
            "isGatingEnabled": false, "isVoiceIsolationEnabled": false,
            "transform": {"offset": [0, 0], "scale": 1}
          }]
        }]
      }
    }
    """

    @Test("A 1.0 project with removed-feature keys still opens and keeps its notes and settings")
    func legacyProjectDecodes() throws {
        let project = try JSONDecoder().decode(VideoProject.self, from: Data(Self.legacyProjectJSON.utf8))

        #expect(project.name == "Old Walkthrough")
        #expect(project.speakerNotes.text == "Walk through the setup flow")
        #expect(project.speakerNotes.fontSize == 26)
        #expect(project.speakerNotes.isMirrored)
        #expect(project.captionStyleName == "Bold")
        #expect(project.captionOffset == CGSize(width: 12, height: -8))
        #expect(project.captionFontName == "Avenir Next")
        #expect(project.zoomLevel == 2)
        #expect(project.clipCount == 1)
        #expect(project.timeline.tracks.first?.clips.first?.duration.seconds == 10)
    }

    @Test("A legacy project survives a save and reload unchanged")
    func legacyProjectRoundTrips() throws {
        let decoded = try JSONDecoder().decode(VideoProject.self, from: Data(Self.legacyProjectJSON.utf8))

        let data = try JSONEncoder().encode(decoded)
        let reloaded = try JSONDecoder().decode(VideoProject.self, from: data)

        #expect(reloaded == decoded)
        #expect(reloaded.modifiedAt == decoded.modifiedAt)
        let keys = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any]).keys
        #expect(!keys.contains("presentationPreset"))
        #expect(!keys.contains("commentaryMarkers"))
    }

    @Test("clipCount and hasContent count clips across all tracks")
    func clipCountSumsTracks() {
        var project = VideoProject(name: "ClipCount Test")
        #expect(project.clipCount == 0)
        #expect(!project.hasContent)

        var video = Track(name: "Video Track", type: .video, zIndex: 0)
        video.clips = [
            VideoClip(url: URL(fileURLWithPath: "/tmp/test1.mp4"), duration: CMTime(seconds: 10, preferredTimescale: 600)),
            VideoClip(
                url: URL(fileURLWithPath: "/tmp/test2.mp4"),
                duration: CMTime(seconds: 5, preferredTimescale: 600),
                startTime: CMTime(seconds: 10, preferredTimescale: 600)
            )
        ]
        var audio = Track(name: "Audio Track", type: .audio, zIndex: 1)
        audio.clips = [VideoClip(url: URL(fileURLWithPath: "/tmp/test3.mp4"), duration: CMTime(seconds: 3, preferredTimescale: 600))]
        project.timeline.tracks = [video, audio]

        #expect(project.clipCount == 3)
        #expect(project.hasContent)
    }

    @Test("hasCaptions is true only once a clip has captions")
    func hasCaptionsDetectsCaptionedClip() {
        var project = VideoProject(name: "Captions Test")
        var track = Track(name: "Video Track", type: .video, zIndex: 0)
        var clip = VideoClip(url: URL(fileURLWithPath: "/tmp/test.mp4"), duration: CMTime(seconds: 10, preferredTimescale: 600))
        track.clips = [clip]
        project.timeline.tracks = [track]
        #expect(!project.hasCaptions)

        clip.captions = [Caption(text: "Hello", startTime: .zero, endTime: CMTime(seconds: 1, preferredTimescale: 600))]
        project.timeline.tracks[0].clips[0] = clip

        #expect(project.hasCaptions)
    }

    @Test("Relinking a clip refreshes its duration and clamps trimEnd to the new file")
    @MainActor
    func relinkClipRefreshesDurationAndTrimEnd() async throws {
        let replacementURL = TestEnvironment.mockAssetURL
        let expectedDuration = try await AVURLAsset(url: replacementURL).load(.duration)

        var oversizedClip = VideoClip(
            url: URL(fileURLWithPath: "/tmp/original.mp4"),
            duration: CMTime(seconds: 999, preferredTimescale: 600)
        )
        oversizedClip.trimEnd = CMTime(seconds: 999, preferredTimescale: 600)
        var project = VideoProject(name: "Relink Test")
        var track = Track(name: "Video", type: .video, zIndex: 0)
        track.clips = [oversizedClip]
        project.timeline.tracks = [track]

        let projectState = ProjectState(projectStore: MockProjectStore())
        projectState.currentProject = project
        projectState.relinkClip(oversizedClip, to: replacementURL)

        let relinked = try #require(projectState.currentProject?.timeline.tracks.first?.clips.first)
        #expect(relinked.url == replacementURL)
        #expect(abs(relinked.duration.seconds - expectedDuration.seconds) < 0.01)
        #expect(relinked.trimEnd.seconds <= expectedDuration.seconds + 0.01)
    }
}
