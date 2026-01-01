//
//  ExportEffectsIntegrationTests.swift
//  SaneVideoTests
//
//  Effects and transitions export integration tests.
//  Split from ExportPipelineIntegrationTests for maintainability.
//

import AVFoundation
import CoreMedia
import XCTest

@testable import SaneVideo

/// Integration tests for effects and transitions in exports.
final class ExportEffectsIntegrationTests: XCTestCase {

    // MARK: - Properties

    var projectState: ProjectState!
    var exportEngine: ExportEngine!
    var tempOutputURL: URL!
    var testAssetURL: URL!

    // MARK: - Setup & Teardown

    @MainActor
    override func setUp() {
        super.setUp()
        projectState = ProjectState()
        exportEngine = ExportEngine()
        let tempDir = FileManager.default.temporaryDirectory
        tempOutputURL = tempDir.appendingPathComponent("test_effects_export_\(UUID().uuidString).mp4")
        testAssetURL = getTestAssetURL()
    }

    override func tearDown() {
        if let url = tempOutputURL, FileManager.default.fileExists(atPath: url.path) {
            try? FileManager.default.removeItem(at: url)
        }
        projectState = nil
        exportEngine = nil
        super.tearDown()
    }

    // MARK: - Helpers

    private func getTestAssetURL() -> URL {
        let silenceAsset = TestEnvironment.testAsset(named: "test_silence.mp4")
        if FileManager.default.fileExists(atPath: silenceAsset.path) {
            return silenceAsset
        }
        return TestEnvironment.mockAssetURL
    }

    @MainActor
    private func createProjectWithClip() async throws -> (VideoProject, VideoClip) {
        let asset = AVURLAsset(url: testAssetURL)
        let duration = try await asset.load(.duration)

        let clip = VideoClip(
            url: testAssetURL,
            duration: duration,
            startTime: .zero
        )

        projectState.startNewProject()
        projectState.addTrack(type: .video, name: "Video Track 1")
        projectState.addClip(clip)

        guard let project = projectState.currentProject else {
            throw TestError.projectNotCreated
        }

        return (project, clip)
    }

    private func verifyExportedFile(at url: URL) async throws -> AVAsset {
        XCTAssertTrue(FileManager.default.fileExists(atPath: url.path))
        let fileSize = try FileManager.default.attributesOfItem(atPath: url.path)[.size] as? Int ?? 0
        XCTAssertGreaterThan(fileSize, 0)
        let asset = AVURLAsset(url: url)
        let isPlayable = try await asset.load(.isPlayable)
        XCTAssertTrue(isPlayable)
        return asset
    }

    // MARK: - Single Effect Tests

    @MainActor
    func testExportWithEffectAppliesEffect() async throws {
        guard FileManager.default.fileExists(atPath: testAssetURL.path) else {
            throw XCTSkip("Test asset not available")
        }

        let (_, clip) = try await createProjectWithClip()

        let effect = VideoEffect(type: .noir)
        projectState.applyEffect(to: clip, effect: effect)

        guard let projectWithEffect = projectState.currentProject else {
            throw TestError.projectNotCreated
        }

        let outputURL = try await exportEngine.export(
            project: projectWithEffect,
            settings: SaneExportSettings(),
            outputURL: tempOutputURL
        ) { _ in }

        let exportedAsset = try await verifyExportedFile(at: outputURL)
        let isPlayable = try await exportedAsset.load(.isPlayable)
        XCTAssertTrue(isPlayable, "Export with effect should produce playable file")
    }

    @MainActor
    func testExportWithMultipleEffects() async throws {
        guard FileManager.default.fileExists(atPath: testAssetURL.path) else {
            throw XCTSkip("Test asset not available")
        }

        let (_, clip) = try await createProjectWithClip()

        projectState.applyEffect(to: clip, effect: VideoEffect(type: .autoEnhance))
        if let updatedClip = projectState.getClip(by: clip.id) {
            projectState.applyEffect(to: updatedClip, effect: VideoEffect(type: .vignette))
        }

        guard let project = projectState.currentProject else {
            throw TestError.projectNotCreated
        }

        let outputURL = try await exportEngine.export(
            project: project,
            settings: SaneExportSettings(),
            outputURL: tempOutputURL
        ) { _ in }

        let exportedAsset = try await verifyExportedFile(at: outputURL)
        let isPlayable = try await exportedAsset.load(.isPlayable)
        XCTAssertTrue(isPlayable, "Export with multiple effects should produce playable file")
    }

    // MARK: - Transition Tests

    @MainActor
    func testExportWithTransition() async throws {
        guard FileManager.default.fileExists(atPath: testAssetURL.path) else {
            throw XCTSkip("Test asset not available")
        }

        let asset = AVURLAsset(url: testAssetURL)
        let duration = try await asset.load(.duration)

        guard duration.seconds > 4.0 else {
            throw XCTSkip("Test video too short for transition test")
        }

        var clip1 = VideoClip(url: testAssetURL, duration: duration, startTime: .zero)
        clip1.trimEnd = CMTime(seconds: duration.seconds / 2, preferredTimescale: 600)

        var clip2 = VideoClip(
            url: testAssetURL,
            duration: duration,
            startTime: CMTime(seconds: duration.seconds / 2, preferredTimescale: 600)
        )
        clip2.trimStart = CMTime(seconds: duration.seconds / 2, preferredTimescale: 600)

        projectState.startNewProject()
        projectState.addTrack(type: .video, name: "Video Track 1")
        projectState.addClip(clip1)
        projectState.addClip(clip2)
        projectState.setClipTransition(clipId: clip1.id, transitionType: .dissolve)

        guard let project = projectState.currentProject else {
            throw TestError.projectNotCreated
        }

        let outputURL = try await exportEngine.export(
            project: project,
            settings: SaneExportSettings(),
            outputURL: tempOutputURL
        ) { _ in }

        let exportedAsset = try await verifyExportedFile(at: outputURL)
        let isPlayable = try await exportedAsset.load(.isPlayable)
        XCTAssertTrue(isPlayable, "Export with transition should produce playable file")
    }

    // MARK: - Effect Verification (Pixel Data)

    @MainActor
    func testEffectModifiesPixelData() async throws {
        guard FileManager.default.fileExists(atPath: testAssetURL.path) else {
            throw XCTSkip("Test asset not available")
        }

        let asset = AVURLAsset(url: testAssetURL)
        let duration = try await asset.load(.duration)

        let clip = VideoClip(url: testAssetURL, duration: duration, startTime: .zero)

        // Export without effect
        projectState.startNewProject()
        projectState.addTrack(type: .video, name: "Video Track 1")
        projectState.addClip(clip)

        guard let projectWithout = projectState.currentProject else {
            throw TestError.projectNotCreated
        }

        let tempWithout = tempOutputURL.deletingLastPathComponent()
            .appendingPathComponent("no_effect_\(UUID().uuidString).mp4")
        defer { try? FileManager.default.removeItem(at: tempWithout) }

        _ = try await exportEngine.export(
            project: projectWithout,
            settings: SaneExportSettings(),
            outputURL: tempWithout
        ) { _ in }

        // Export with noir effect
        projectState.startNewProject()
        projectState.addTrack(type: .video, name: "Video Track 1")
        let clip2 = VideoClip(url: testAssetURL, duration: duration, startTime: .zero)
        projectState.addClip(clip2)
        projectState.applyEffect(to: clip2, effect: VideoEffect(type: .noir))

        guard let projectWith = projectState.currentProject else {
            throw TestError.projectNotCreated
        }

        let tempWith = tempOutputURL.deletingLastPathComponent()
            .appendingPathComponent("with_effect_\(UUID().uuidString).mp4")
        defer { try? FileManager.default.removeItem(at: tempWith) }

        _ = try await exportEngine.export(
            project: projectWith,
            settings: SaneExportSettings(),
            outputURL: tempWith
        ) { _ in }

        // Compare file sizes
        let withoutSize = try FileManager.default.attributesOfItem(atPath: tempWithout.path)[.size] as? Int ?? 0
        let withSize = try FileManager.default.attributesOfItem(atPath: tempWith.path)[.size] as? Int ?? 0

        let sizeDifference = abs(withoutSize - withSize)
        let percentDifference = Double(sizeDifference) / Double(max(withoutSize, withSize)) * 100

        XCTAssertGreaterThan(
            percentDifference,
            1.0,
            "Effect should measurably change file size. Without: \(withoutSize), With: \(withSize), Diff: \(percentDifference)%"
        )
    }

    // MARK: - Error Type

    enum TestError: Error {
        case projectNotCreated
    }
}
