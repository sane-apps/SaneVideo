//
//  ProjectRegressionTests.swift
//  SaneVideoTests
//
//  Created by SaneVideo Refactor
//

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

    // Save
    let data = try JSONEncoder().encode(project)
    try data.write(to: projectFile)

    // Load
    let loadedData = try Data(contentsOf: projectFile)
    let loadedProject = try JSONDecoder().decode(VideoProject.self, from: loadedData)

    XCTAssertEqual(project.id, loadedProject.id)
    XCTAssertEqual(project.name, loadedProject.name)

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
}
