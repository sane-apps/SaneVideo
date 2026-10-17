//
//  ProjectEditingTests.swift
//  SaneVideoTests
//
//  Created by SaneVideo Test Suite
//

import XCTest
import AVFoundation
@testable import SaneVideo

// Mock Store to prevent disk I/O during tests
class MockProjectStore: ProjectStoreProtocol, @unchecked Sendable {
    func loadProjects() async throws -> [VideoProject] { return [] }
    func saveProject(_ project: VideoProject) async throws { }
    func deleteProject(_ project: VideoProject) async throws { }
    func recentProjects(limit: Int) async throws -> [VideoProject] { return [] }
    func fileURL(for project: VideoProject) -> URL {
        return URL(fileURLWithPath: "/tmp/\(project.id.uuidString).svproj")
    }
}

@MainActor
final class ProjectEditingTests: XCTestCase {
    var projectState: ProjectState!
    
    override func setUp() async throws {
        // Ensure magnetic timeline is enabled for ripple behavior
        UserDefaults.standard.set(true, forKey: "magneticTimeline")

        // Initialize with Mock Store
        projectState = ProjectState(projectStore: MockProjectStore())
        // Start fresh
        projectState.startNewProject()
    }
    
    // Helper to get total clip count
    var totalClipCount: Int {
        projectState.currentProject?.timeline.tracks.reduce(0) { $0 + $1.clips.count } ?? 0
    }
    
    // Helper to get clips from first track
    var firstTrackClips: [VideoClip] {
        projectState.currentProject?.timeline.tracks.first?.clips ?? []
    }
    
    func testStartNewProject_ClearsTimeline() {
        // 1. Add clips to current project
        let clip = VideoClip(url: URL(fileURLWithPath: "/tmp/fake.mov"), duration: CMTime(seconds: 10, preferredTimescale: 600))
        projectState.addClip(clip)
        XCTAssertEqual(totalClipCount, 1, "Timeline should have 1 clip")
        
        // 2. Start new project
        projectState.startNewProject()
        
        // 3. Verify
        XCTAssertEqual(totalClipCount, 0, "New project should have empty timeline")
    }
    
    func testAddClip_AppendsSequentially() {
        let clip1 = VideoClip(url: URL(fileURLWithPath: "/tmp/1.mov"), duration: CMTime(seconds: 5, preferredTimescale: 600))
        let clip2 = VideoClip(url: URL(fileURLWithPath: "/tmp/2.mov"), duration: CMTime(seconds: 5, preferredTimescale: 600))
        
        projectState.addClip(clip1)
        projectState.addClip(clip2)
        
        let clips = firstTrackClips
        XCTAssertEqual(clips.count, 2)
        XCTAssertEqual(clips[0].startTime.seconds, 0.0)
        XCTAssertEqual(clips[1].startTime.seconds, 5.0, "Second clip should start after first")
    }
    
    func testTrimClip_RipplesTimeline() {
        // Add 2 clips of 10s each
        let clip1 = VideoClip(url: URL(fileURLWithPath: "/tmp/1.mov"), duration: CMTime(seconds: 10, preferredTimescale: 600))
        let clip2 = VideoClip(url: URL(fileURLWithPath: "/tmp/2.mov"), duration: CMTime(seconds: 10, preferredTimescale: 600))
        
        projectState.addClip(clip1)
        projectState.addClip(clip2)
        
        // Clip 2 should start at 10s
        XCTAssertEqual(firstTrackClips[1].startTime.seconds, 10.0)
        
        // Trim Clip 1 to 5s (TrimEnd)
        let newTrimEnd = CMTime(seconds: 5, preferredTimescale: 600)
        projectState.updateClipTrim(clipId: firstTrackClips[0].id, trimStart: nil, trimEnd: newTrimEnd)
        
        // Clip 1 duration is now 5s
        XCTAssertEqual(firstTrackClips[0].effectiveDuration.seconds, 5.0)
        
        // Clip 2 should now start at 5s (Ripple)
        XCTAssertEqual(firstTrackClips[1].startTime.seconds, 5.0, "Second clip should shift left (ripple) after trim")
    }
    
    func testSplitClip() {
        // Add 1 clip of 10s
        let clip = VideoClip(url: URL(fileURLWithPath: "/tmp/1.mov"), duration: CMTime(seconds: 10, preferredTimescale: 600))
        projectState.addClip(clip)
        
        // Split at 5s
        let splitTime = CMTime(seconds: 5, preferredTimescale: 600)
        projectState.splitClip(firstTrackClips[0], atTimelineTime: splitTime)
        
        // Should have 2 clips
        let clips = firstTrackClips
        XCTAssertEqual(clips.count, 2)
        
        // First clip: 0-5s (trimmed end at 5s)
        XCTAssertEqual(clips[0].effectiveDuration.seconds, 5.0)
        XCTAssertEqual(clips[0].trimEnd.seconds, 5.0)
        
        // Second clip: 5-10s (trimmed start at 5s)
        XCTAssertEqual(clips[1].effectiveDuration.seconds, 5.0)
        XCTAssertEqual(clips[1].trimStart.seconds, 5.0)
        XCTAssertEqual(clips[1].startTime.seconds, 5.0)
    }

    func testOpenProjectFileLoadsPreparedProject() throws {
        var preparedProject = VideoProject(name: "Prepared Script")
        preparedProject.updateSpeakerNotes(SpeakerNotes(text: "Opening line", fontSize: 40))

        let fileURL = FileManager.default.temporaryDirectory.appendingPathComponent("\(UUID().uuidString).svproj")
        let data = try JSONEncoder().encode(preparedProject)
        try data.write(to: fileURL)
        defer { try? FileManager.default.removeItem(at: fileURL) }

        try projectState.openProjectFile(at: fileURL)

        XCTAssertEqual(projectState.currentProject?.id, preparedProject.id)
        XCTAssertEqual(projectState.currentProject?.name, "Prepared Script")
        XCTAssertEqual(projectState.currentProject?.speakerNotes.text, "Opening line")
        XCTAssertEqual(projectState.currentProject?.speakerNotes.fontSize, 40)
        XCTAssertEqual(projectState.projects.first?.id, preparedProject.id)
    }

    func testAutomationExportPathFallsBackWhenRequestedDirectoryIsNotWritable() {
        let requestedURL = URL(fileURLWithPath: "/System/Library/Todd Commentary.mp4")
        let fallbackRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)

        let resolved = AutomationExportPathPolicy.resolveOutputURL(
            requestedURL: requestedURL,
            fallbackRoot: fallbackRoot
        )

        XCTAssertEqual(resolved.deletingLastPathComponent(), fallbackRoot)
        XCTAssertEqual(resolved.lastPathComponent, "Todd Commentary.mp4")
    }

    func testPreparedProjectOrExportEnvironmentRequestsEditorBootstrap() throws {
        let suiteName = "ProjectEditingTests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)

        let projectURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("\(UUID().uuidString).svproj")
        let transcriptURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("\(UUID().uuidString).txt")
        let assetURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("\(UUID().uuidString).mp4")
        try Data("{}".utf8).write(to: projectURL)
        try Data("[]".utf8).write(to: transcriptURL)
        try Data("fake video".utf8).write(to: assetURL)
        defer {
            try? FileManager.default.removeItem(at: projectURL)
            try? FileManager.default.removeItem(at: transcriptURL)
            try? FileManager.default.removeItem(at: assetURL)
            defaults.removePersistentDomain(forName: suiteName)
        }

        XCTAssertTrue(
            TestEnvironment.shouldOpenEditor(
                arguments: [],
                userDefaults: defaults,
                environment: ["TEST_PROJECT_PATH": projectURL.path]
            )
        )
        XCTAssertTrue(
            TestEnvironment.shouldOpenEditor(
                arguments: [],
                userDefaults: defaults,
                environment: ["AUTOMATION_EXPORT_PATH": "/tmp/commentary.mp4"]
            )
        )
        XCTAssertTrue(
            TestEnvironment.shouldOpenEditor(
                arguments: [],
                userDefaults: defaults,
                environment: ["SANEVIDEO_OPEN_EDITOR": "1"]
            )
        )
        XCTAssertTrue(
            TestEnvironment.shouldOpenEditor(
                arguments: ["-test_asset_path", assetURL.path],
                userDefaults: defaults,
                environment: [:]
            )
        )
        XCTAssertEqual(
            TestEnvironment.explicitAssetURL(
                arguments: ["--test-asset-path=\(assetURL.path)"],
                environment: [:]
            ),
            assetURL
        )
        XCTAssertEqual(
            TestEnvironment.automationTranscriptURL(
                in: ["AUTOMATION_TRANSCRIPT_PATH": transcriptURL.path]
            ),
            transcriptURL
        )
        XCTAssertEqual(
            TestEnvironment.automationTranscriptURL(
                arguments: ["--automation-transcript-path", transcriptURL.path],
                environment: [:]
            ),
            transcriptURL
        )
    }

    func testApplyTimestampedTranscriptCorrectionsUpdatesMatchingCaptions() throws {
        var clip = VideoClip(
            url: URL(fileURLWithPath: "/tmp/source.mov"),
            duration: CMTime(seconds: 60, preferredTimescale: 600)
        )
        clip.captions = [
            Caption(text: "orig one", startTime: CMTime(seconds: 5, preferredTimescale: 600), endTime: CMTime(seconds: 6, preferredTimescale: 600)),
            Caption(text: "orig two", startTime: CMTime(seconds: 10, preferredTimescale: 600), endTime: CMTime(seconds: 11, preferredTimescale: 600))
        ]
        projectState.addClip(clip)

        let transcriptURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("\(UUID().uuidString).txt")
        try """
        [00:05] Corrected first line.
        [00:10] Corrected second line.
        """.write(to: transcriptURL, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: transcriptURL) }

        try projectState.applyTranscriptCorrections(from: transcriptURL, to: firstTrackClips[0])

        let updatedCaptions = firstTrackClips[0].captions
        XCTAssertEqual(updatedCaptions[0].text, "Corrected first line.")
        XCTAssertEqual(updatedCaptions[1].text, "Corrected second line.")
    }
}
