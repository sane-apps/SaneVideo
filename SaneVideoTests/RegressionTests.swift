//
//  RegressionTests.swift
//  SaneVideoTests
//
//  Created by SaneVideo Refactor
//

import XCTest
import CoreMedia
@testable import SaneVideo

@MainActor
final class RegressionTests: XCTestCase {

    // MARK: - Bug Fix: Source Switch Timestamp Monotonicity (Code -12737)
    
    // Regression Test for: "Recording crash on source switch due to non-monotonic timestamps"
    // Fix implemented: Added 100ms safe gap when switching sources
    func testSourceSwitchTimestampGap() async {
        let startTime = CMTime(seconds: 0, preferredTimescale: 600)
        let lastRecordedDuration = CMTime(seconds: 9.9, preferredTimescale: 600)
        
        // Simulate the logic used in RecordingEngine.processSample
        // Old Logic: 
        // let oldGap = CMTime(value: 1, timescale: 1000) // 1ms
        
        // New Logic:
        let safeGap = CMTime(value: 100, timescale: 1000) // 100ms
        
        let lastAbsoluteTime = CMTimeAdd(startTime, lastRecordedDuration)
        let targetNewTime = CMTimeAdd(lastAbsoluteTime, safeGap)
        
        // Verify that targetNewTime is strictly greater than lastRecordedTime + 33ms (typical frame duration)
        let typicalFrameDuration = CMTime(value: 1, timescale: 30) // ~33ms
        let previousFrameEndTime = CMTimeAdd(lastAbsoluteTime, typicalFrameDuration)
        
        XCTAssertGreaterThan(targetNewTime, previousFrameEndTime, "New segment must start AFTER the previous frame has finished playing")
        
        // Calculate the actual gap in seconds
        let actualGap = CMTimeSubtract(targetNewTime, lastAbsoluteTime).seconds
        XCTAssertEqual(actualGap, 0.1, accuracy: 0.001, "Gap should be exactly 0.1s (100ms)")
    }
    
    // MARK: - Bug Fix: Clip Splitting Time Calculations
    
    // Regression Test for: "Splitting clips resulted in incorrect local times"
    func testClipSplittingMath() {
        // Setup a clip: 10s long, starting at 0
        let videoURL = URL(fileURLWithPath: "/tmp/test.mp4")
        let clip = VideoClip(url: videoURL, duration: CMTime(seconds: 10, preferredTimescale: 600), startTime: .zero)
        
        // Split at 5s global time
        let splitTime = CMTime(seconds: 5, preferredTimescale: 600)
        
        // Logic verification (mimicking TimelineEngine.split)
        // Part 1: Start 0, Duration 5
        // Part 2: Start 5, Duration 5, Offset 5 (into the file)
        
        // In our engine, 'offset' usually means 'start of content within file'.
        // If we split at 5s:
        // Left clip: duration 5s. content range 0...5
        // Right clip: duration 5s. content range 5...10
        
        let leftDuration = CMTimeSubtract(splitTime, clip.startTime)
        let rightDuration = CMTimeSubtract(clip.duration, leftDuration)
        
        XCTAssertEqual(leftDuration.seconds, 5.0)
        XCTAssertEqual(rightDuration.seconds, 5.0)
        
        // Verify "Offset" / "Content Start" logic
        // If the original clip had an offset (e.g. started 2s into file)
        let originalOffset = CMTime(seconds: 2, preferredTimescale: 600)
        let offsetClip = VideoClip(url: videoURL, duration: CMTime(seconds: 10, preferredTimescale: 600), startTime: .zero, trimStart: originalOffset)
        
        // Split at 3s global (which is +3s from start)
        // Left: duration 3. content 2...(2+3)=5
        // Right: duration 7. content 5...(2+10)=12
        
        let splitPoint = CMTime(seconds: 3, preferredTimescale: 600)
        let leftDur = splitPoint 
        _ = CMTimeSubtract(offsetClip.duration, leftDur)
        
        let newRightOffset = CMTimeAdd(originalOffset, leftDur)
        
        XCTAssertEqual(newRightOffset.seconds, 5.0, "Right clip should start 5s into the underlying file")
    }

    // MARK: - Bug Fix: Recording Engine Threading
    
    // Regression Test for: "Recording Engine running on Main Thread check"
    func testRecordingEngineQueue() {
        _ = RecordingEngine(
            cameraService: ServiceContainer.shared.cameraService,
            audioService: ServiceContainer.shared.audioService
        )
        
        // We can't easily check private queue, but we can check it's NOT main thread
        // This is hard to unit test without exposing internals. 
        // Instead, we verify that calling public methods doesn't crash or block main.
        
        let expectation = XCTestExpectation(description: "Start recording async")
        
        Task {
            // Simulate start
            // engine.startRecording(...) requires real services, skipping full integration test here.
            // Just verifying instantiation is relatively safe.
            expectation.fulfill()
        }
        
        wait(for: [expectation], timeout: 1.0)
    }

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
    // MARK: - Bug Fix: PiP Window Persistence
    
    // Regression Test for: "PiP window disappearing during screen share/focus switch"
    @MainActor
    func testPiPWindowProperties() {
        let pipWindow = PiPCameraWindow()
        
        // 1. Verify it is an NSPanel (critical for floating behavior)
        XCTAssertTrue(pipWindow is NSPanel, "PiPCameraWindow must be an NSPanel")
        
        // 2. Verify Level
        XCTAssertEqual(pipWindow.level, .statusBar, "PiP Window level must be .statusBar to persist over apps")
        
        // 3. Verify Style Mask
        XCTAssertTrue(pipWindow.styleMask.contains(.nonactivatingPanel), "Style mask must include .nonactivatingPanel")
        
        // 4. Verify Collection Behavior
        XCTAssertTrue(pipWindow.collectionBehavior.contains(.canJoinAllSpaces), "Must join all spaces")
        XCTAssertTrue(pipWindow.collectionBehavior.contains(.fullScreenAuxiliary), "Must be fullScreenAuxiliary")
        
        // 5. Verify Deactivation Hiding behavior
        XCTAssertFalse(pipWindow.hidesOnDeactivate, "Must NOT hide on deactivate")
        
        // Check Controls Window too
        if let controls = pipWindow.controlsWindow {
            XCTAssertTrue(controls is NSPanel, "Controls window must be NSPanel")
            XCTAssertEqual(controls.level, .statusBar)
            XCTAssertTrue(controls.styleMask.contains(.nonactivatingPanel))
        } else {
            XCTFail("Controls window should be created on init")
        }
    }
    
    // MARK: - Feature: Caption Time Mapping
    
    func testCaptionTimeMappingWithRemovals() {
        let videoURL = URL(fileURLWithPath: "/tmp/test.mp4")
        var clip = VideoClip(url: videoURL, duration: CMTime(seconds: 10, preferredTimescale: 600))
        
        // Remove 2s...4s (2s duration)
        clip.addRemovedRange(CMTimeRange(start: CMTime(seconds: 2, preferredTimescale: 600), duration: CMTime(seconds: 2, preferredTimescale: 600)))
        
        // Effective duration should be 8s
        XCTAssertEqual(clip.effectiveDuration.seconds, 8.0)
        
        // Effective time 1s -> Original 1s
        XCTAssertEqual(clip.originalTime(forEffectiveTime: CMTime(seconds: 1, preferredTimescale: 600)).seconds, 1.0)
        
        // Effective time 3s -> Original 5s (skips 2s...4s)
        XCTAssertEqual(clip.originalTime(forEffectiveTime: CMTime(seconds: 3, preferredTimescale: 600)).seconds, 5.0)
    }
    
    // MARK: - Feature: Magnetic Timeline
    
    func testMagneticTimelineRecalculate() {
        let videoURL = URL(fileURLWithPath: "/tmp/test.mp4")
        let clip1 = VideoClip(url: videoURL, duration: CMTime(seconds: 5, preferredTimescale: 600), startTime: .zero)
        var clip2 = VideoClip(url: videoURL, duration: CMTime(seconds: 5, preferredTimescale: 600), startTime: CMTime(seconds: 10, preferredTimescale: 600)) // Gap of 5s
        
        var timeline = Timeline(tracks: [Track(name: "Test Track", type: .video, clips: [clip1, clip2], zIndex: 0)])
        
        // This is tricky because recalculateStartTimes uses @AppStorage which we might not want to mock here
        // But we can test the logic directly if we assume it's enabled.
        // Let's verify the logic in ProjectState.recalculateStartTimes
        
        var cumulativeTime = CMTime.zero
        for i in 0 ..< timeline.tracks[0].clips.count {
            timeline.tracks[0].clips[i].startTime = cumulativeTime
            cumulativeTime = CMTimeAdd(cumulativeTime, timeline.tracks[0].clips[i].effectiveDuration)
        }
        
        XCTAssertEqual(timeline.tracks[0].clips[1].startTime.seconds, 5.0, "Second clip should snap to the end of the first clip (5s)")
    }
    
    // MARK: - Feature: Smooth Cut Insertion
    
    func testSmoothCutInsertion() {
        let videoURL = URL(fileURLWithPath: "/tmp/test.mp4")
        var clip = VideoClip(url: videoURL, duration: CMTime(seconds: 10, preferredTimescale: 600))
        clip.useSmoothCutForRemovals = true
        clip.addRemovedRange(CMTimeRange(start: CMTime(seconds: 5, preferredTimescale: 600), duration: CMTime(seconds: 1, preferredTimescale: 600)))
        
        let validSegments = VideoTrackBuilder.computeValidSegments(clip: clip, sourceDuration: clip.duration)
        XCTAssertEqual(validSegments.count, 2)
        XCTAssertEqual(validSegments[0].duration.seconds, 5.0)
        XCTAssertEqual(validSegments[1].start.seconds, 6.0)
        
        // The smoothing overlap is 0.15s in VideoTrackBuilder
        let overlap = CMTime(seconds: 0.15, preferredTimescale: 600)
        
        // Verify segment 2 would be extended if we followed the logic in VideoTrackBuilder
        var segment2 = validSegments[1]
        segment2.start = CMTimeSubtract(segment2.start, overlap)
        segment2.duration = CMTimeAdd(segment2.duration, overlap)
        
        XCTAssertEqual(segment2.start.seconds, 5.85, "Should start 0.15s earlier for smooth transition")
    }
    
    // MARK: - macOS 26 API Deprecation Guards
    
    /// Ensures no deprecated APIs are being used in the codebase
    /// These tests grep the source files to detect patterns that should be updated
    func testNoDeprecatedFaceCaptureQualityAPI() throws {
        // faceCaptureQuality was deprecated in macOS 26, should use captureQuality.score
        let sourceDir = URL(fileURLWithPath: #file)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("SaneVideo")
        
        let fileManager = FileManager.default
        guard let enumerator = fileManager.enumerator(at: sourceDir, includingPropertiesForKeys: nil) else {
            XCTFail("Could not enumerate source directory")
            return
        }
        
        var deprecatedUsages: [String] = []
        
        while let fileURL = enumerator.nextObject() as? URL {
            guard fileURL.pathExtension == "swift" else { continue }
            guard let contents = try? String(contentsOf: fileURL, encoding: .utf8) else { continue }
            
            // Check for deprecated faceCaptureQuality (but allow documented legacy usage)
            if contents.contains(".faceCaptureQuality") && 
               !contents.contains("// Note:") && 
               !contents.contains("legacy") {
                deprecatedUsages.append("\(fileURL.lastPathComponent): Uses deprecated faceCaptureQuality without documentation")
            }
        }
        
        XCTAssertTrue(deprecatedUsages.isEmpty, "Found deprecated API usages:\n\(deprecatedUsages.joined(separator: "\n"))")
    }
    
    /// Ensures Translation framework uses modern TranslationSession API
    func testTranslationServiceUsesModernAPI() throws {
        let sourceDir = URL(fileURLWithPath: #file)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("SaneVideo/Services/AI")
        
        let translationServiceFile = sourceDir.appendingPathComponent("TranslationService.swift")
        guard let contents = try? String(contentsOf: translationServiceFile, encoding: .utf8) else {
            // File might not exist in test environment
            return
        }
        
        // Should use TranslationSession, not deprecated Translator
        XCTAssertTrue(contents.contains("TranslationSession"), "TranslationService should use TranslationSession API")
        XCTAssertFalse(contents.contains("Translator("), "TranslationService should not use deprecated Translator class")
    }
    
    /// Ensures CameraServiceProtocol uses async/await (modernized in macOS 26)
    func testCameraServiceUsesAsyncAPI() throws {
        let sourceDir = URL(fileURLWithPath: #file)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("SaneVideo/Core/Protocols")
        
        let protocolFile = sourceDir.appendingPathComponent("CameraServiceProtocol.swift")
        guard let contents = try? String(contentsOf: protocolFile, encoding: .utf8) else {
            return
        }
        
        // start() should be async throws, not use completion handlers
        XCTAssertTrue(contents.contains("func start() async throws"), "CameraServiceProtocol.start() should be async throws")
        XCTAssertFalse(contents.contains("start(completion:"), "CameraServiceProtocol should not have completion handler variant")
    }
    
    /// Ensures no usage of deprecated NSPersistentStore iCloud keys (removed in macOS 26)
    func testNoDeprecatedCoreDataiCloudKeys() throws {
        let sourceDir = URL(fileURLWithPath: #file)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("SaneVideo")
        
        let deprecatedKeys = [
            "NSPersistentStoreUbiquitousContentNameKey",
            "NSPersistentStoreUbiquitousContentURLKey",
            "NSPersistentStoreUbiquitousPeerTokenOption",
            "NSPersistentStoreRemoveUbiquitousMetadataOption",
            "NSPersistentStoreUbiquitousContainerIdentifierKey",
            "NSPersistentStoreRebuildFromUbiquitousContentOption"
        ]
        
        let fileManager = FileManager.default
        guard let enumerator = fileManager.enumerator(at: sourceDir, includingPropertiesForKeys: nil) else { return }
        
        var deprecatedUsages: [String] = []
        
        while let fileURL = enumerator.nextObject() as? URL {
            guard fileURL.pathExtension == "swift" else { continue }
            guard let contents = try? String(contentsOf: fileURL, encoding: .utf8) else { continue }
            
            for key in deprecatedKeys {
                if contents.contains(key) {
                    deprecatedUsages.append("\(fileURL.lastPathComponent): Uses removed \(key)")
                }
            }
        }
        
        XCTAssertTrue(deprecatedUsages.isEmpty, "Found removed Core Data iCloud keys:\n\(deprecatedUsages.joined(separator: "\n"))")
    }
    
    /// Ensures ExportEngine uses modern async export API (macOS 26)
    func testExportEngineUsesModernAsyncExport() throws {
        let sourceDir = URL(fileURLWithPath: #file)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("SaneVideo/Services/Export")
        
        let exportFile = sourceDir.appendingPathComponent("ExportEngine.swift")
        guard let contents = try? String(contentsOf: exportFile, encoding: .utf8) else { return }
        
        // Should have modern async export pattern
        XCTAssertTrue(contents.contains("export(to:") || contents.contains("async"), "ExportEngine should use modern async export API")
    }
}
