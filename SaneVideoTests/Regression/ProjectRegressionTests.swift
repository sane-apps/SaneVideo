//
//  ProjectRegressionTests.swift
//  SaneVideoTests
//
//  Created by SaneVideo Refactor
//

import AVFoundation
import CoreMedia
import XCTest

@testable import SaneVideo

final class ProjectRegressionTests: XCTestCase {

  // MARK: - Bug Fix: Project Persistence

  // Regression Test for: "Project file corruption" prevention
  func testProjectPersistenceSanity() throws {
    let tempDir = FileManager.default.temporaryDirectory
    let projectFile = tempDir.appendingPathComponent("RegressionTest.svproj")

    let project = VideoProject(id: UUID(), name: "Test Save", createdAt: Date())
    var updatedProject = project
    updatedProject.presentationPreset = .supportTutorial
    updatedProject.speakerNotes = SpeakerNotes(
      text: "Walk through the setup flow",
      fontSize: 26,
      opacity: 0.8,
      widthFraction: 0.7,
      scrollSpeed: 24,
      isMirrored: true,
      isVisible: true
    )
    updatedProject.chapterMarkers = [
      ChapterMarker(title: "Intro", timestamp: 0),
      ChapterMarker(title: "Setup", timestamp: 42)
    ]
    updatedProject.workflowBrief = WorkflowBrief(
      workflow: .commentary,
      instructions: "Group the concerns by concept.",
      voiceBriefSummary: "Keep the source timestamps visible.",
      maxMoments: 4
    )
    updatedProject.commentaryPlanItems = [
      CommentaryPlanItem(
        concept: "Framing",
        claim: "They shifted from substance to optics.",
        supportingReferences: "1 Timothy 3:1-7",
        sourceExcerpt: "The issue became how it was handled.",
        startTime: 148,
        endTime: 156,
        confidence: 0.82,
        sortOrder: 0
      )
    ]
    updatedProject.commentaryMarkers = [
      CommentaryMarker(
        title: "Main point",
        startTime: 148,
        endTime: 156,
        scriptureReferences: "1 Timothy 3:1-7; Titus 1:5-9"
      )
    ]
    updatedProject.demoPackSettings = DemoPackSettings(
      includeLandscapeVideo: true,
      includeVerticalVariant: true,
      includeSquareVariant: false,
      includeThumbnail: true,
      includeTranscriptText: true,
      includeTranscriptPDF: false,
      includeSpeakerNotes: true,
      includeChapters: true,
      includePublishMetadata: true
    )
    updatedProject.publishMetadata = PublishMetadata(
      title: "Test Save",
      subtitle: "Offline demo",
      description: "A privacy-first walkthrough.",
      callToAction: "Try it locally"
    )

    // Save
    let data = try JSONEncoder().encode(updatedProject)
    try data.write(to: projectFile)

    // Load
    let loadedData = try Data(contentsOf: projectFile)
    let loadedProject = try JSONDecoder().decode(VideoProject.self, from: loadedData)

    XCTAssertEqual(updatedProject.id, loadedProject.id)
    XCTAssertEqual(updatedProject.name, loadedProject.name)
    XCTAssertEqual(loadedProject.presentationPreset, .supportTutorial)
    XCTAssertEqual(loadedProject.speakerNotes.text, "Walk through the setup flow")
    XCTAssertEqual(loadedProject.chapterMarkers.count, 2)
    XCTAssertEqual(loadedProject.workflowBrief.workflow, .commentary)
    XCTAssertEqual(loadedProject.workflowBrief.maxMoments, 4)
    XCTAssertEqual(loadedProject.commentaryPlanItems.count, 1)
    XCTAssertEqual(loadedProject.commentaryPlanItems.first?.concept, "Framing")
    XCTAssertEqual(loadedProject.commentaryMarkers.count, 1)
    XCTAssertEqual(loadedProject.commentaryMarkers.first?.scriptureReferences, "1 Timothy 3:1-7; Titus 1:5-9")
    XCTAssertTrue(loadedProject.demoPackSettings.includeVerticalVariant)
    XCTAssertEqual(loadedProject.publishMetadata.callToAction, "Try it locally")

    // Cleanup
    try? FileManager.default.removeItem(at: projectFile)
  }

  // MARK: - Bug Fix: clipCount Performance (2025-12-30)

  /// Regression test for: Projects browser performance issue
  /// Bug: reduce() was called in view body for every project card on every frame
  /// Fix: Added clipCount computed property to VideoProject model
  func testVideoProjectClipCountProperty() throws {
    // Create project with timeline containing clips
    var project = VideoProject(id: UUID(), name: "ClipCount Test", createdAt: Date())

    // Empty project should have 0 clips
    XCTAssertEqual(project.clipCount, 0, "Empty project should have 0 clips")
    XCTAssertFalse(project.hasContent, "Empty project should have no content")

    // Add a track with clips
    var track = Track(name: "Video Track", type: .video, zIndex: 0)
    let clip1 = VideoClip(
      url: URL(fileURLWithPath: "/tmp/test1.mp4"),
      duration: CMTime(seconds: 10, preferredTimescale: 600)
    )
    let clip2 = VideoClip(
      url: URL(fileURLWithPath: "/tmp/test2.mp4"),
      duration: CMTime(seconds: 5, preferredTimescale: 600),
      startTime: CMTime(seconds: 10, preferredTimescale: 600)
    )
    track.clips = [clip1, clip2]
    project.timeline.tracks = [track]

    // clipCount should now reflect the clips
    XCTAssertEqual(project.clipCount, 2, "Project should have 2 clips")
    XCTAssertTrue(project.hasContent, "Project with clips should have content")

    // Add another track
    var track2 = Track(name: "Audio Track", type: .audio, zIndex: 1)
    let clip3 = VideoClip(
      url: URL(fileURLWithPath: "/tmp/test3.mp4"),
      duration: CMTime(seconds: 3, preferredTimescale: 600)
    )
    track2.clips = [clip3]
    project.timeline.tracks.append(track2)

    // clipCount should sum across all tracks
    XCTAssertEqual(project.clipCount, 3, "Project should have 3 clips across 2 tracks")
  }

  /// Regression test for: hasCaptions computed property
  /// Ensures project can detect if any clip has captions
  func testVideoProjectHasCaptionsProperty() throws {
    var project = VideoProject(id: UUID(), name: "Captions Test", createdAt: Date())

    // Empty project has no captions
    XCTAssertFalse(project.hasCaptions, "Empty project should have no captions")

    // Add track with clip without captions
    var track = Track(name: "Video Track", type: .video, zIndex: 0)
    var clip = VideoClip(
      url: URL(fileURLWithPath: "/tmp/test.mp4"),
      duration: CMTime(seconds: 10, preferredTimescale: 600)
    )
    track.clips = [clip]
    project.timeline.tracks = [track]

    XCTAssertFalse(project.hasCaptions, "Project with no captions should return false")

    // Add captions to clip
    clip.captions = [
      Caption(text: "Hello", startTime: .zero, endTime: CMTime(seconds: 1, preferredTimescale: 600))
    ]
    project.timeline.tracks[0].clips[0] = clip

    XCTAssertTrue(project.hasCaptions, "Project with captioned clip should return true")
  }

  func testCommentaryMarkerParseAndSerializeRoundTrip() throws {
    let raw = """
    29:44-29:52 | Impartiality | Fairness question around Jake's absence | Proverbs 18:17; 1 Timothy 5:21
    02:28-05:35 | Framing The Issue | Main issue became optics over substance | 1 Timothy 3:1-7; Titus 1:5-9
    """

    let markers = CommentaryMarker.parseLines(raw)

    XCTAssertEqual(markers.count, 2)
    XCTAssertEqual(markers[0].startTime, 1784)
    XCTAssertEqual(markers[0].trimmedConcept, "Impartiality")
    XCTAssertEqual(markers[0].sortOrder, 0)
    XCTAssertEqual(markers[1].startTime, 148)
    XCTAssertEqual(markers[1].endTime, 335)
    XCTAssertEqual(markers[1].title, "Main issue became optics over substance")
    XCTAssertEqual(markers[1].trimmedConcept, "Framing The Issue")
    XCTAssertEqual(markers[1].scriptureReferences, "1 Timothy 3:1-7; Titus 1:5-9")
    XCTAssertEqual(markers[0].overlayText, "Fairness question around Jake's absence\nProverbs 18:17; 1 Timothy 5:21")

    let serialized = CommentaryMarker.serializeLines(markers)
    let lines = serialized.components(separatedBy: "\n")
    XCTAssertEqual(lines[0], "29:44-29:52 | Impartiality | Fairness question around Jake's absence | Proverbs 18:17; 1 Timothy 5:21")
    XCTAssertEqual(lines[1], "02:28-05:35 | Framing The Issue | Main issue became optics over substance | 1 Timothy 3:1-7; Titus 1:5-9")
  }

  @MainActor
  func testRelinkClipRefreshesDurationAndTrimEnd() async throws {
    let replacementURL = TestEnvironment.mockAssetURL
    guard FileManager.default.fileExists(atPath: replacementURL.path) else {
      throw XCTSkip("Mock asset not available for relink regression test")
    }

    let expectedDuration = try await AVURLAsset(url: replacementURL).load(.duration)
    XCTAssertTrue(expectedDuration.seconds > 0)

    let clip = VideoClip(
      url: URL(fileURLWithPath: "/tmp/original.mp4"),
      duration: CMTime(seconds: 999, preferredTimescale: 600)
    )

    var project = VideoProject(id: UUID(), name: "Relink Test", createdAt: Date())
    var track = Track(name: "Video", type: .video, zIndex: 0)
    var oversizedClip = clip
    oversizedClip.trimEnd = CMTime(seconds: 999, preferredTimescale: 600)
    track.clips = [oversizedClip]
    project.timeline.tracks = [track]

    let projectState = ProjectState()
    projectState.currentProject = project
    projectState.relinkClip(oversizedClip, to: replacementURL)

    let relinkedClip = try XCTUnwrap(projectState.currentProject?.timeline.tracks.first?.clips.first)
    XCTAssertEqual(relinkedClip.url, replacementURL)
    XCTAssertEqual(relinkedClip.duration.seconds, expectedDuration.seconds, accuracy: 0.01)
    XCTAssertLessThanOrEqual(relinkedClip.trimEnd.seconds, expectedDuration.seconds + 0.01)
  }
}
