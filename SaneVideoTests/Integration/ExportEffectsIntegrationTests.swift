//
//  ExportEffectsIntegrationTests.swift
//  SaneVideoTests
//
//  Effects and transitions export integration tests.
//  Split from ExportPipelineIntegrationTests for maintainability.
//

import AVFoundation
import CoreMedia
import CoreGraphics
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

    private func effectComparisonAssetURL() -> URL {
        let candidates = [
            "IMG_6091.MOV",
            "test_video.mp4",
            "test_silence.mp4"
        ]

        for candidate in candidates {
            let url = TestEnvironment.testAsset(named: candidate)
            if FileManager.default.fileExists(atPath: url.path) {
                return url
            }
        }

        return testAssetURL
    }

    private func pixelBufferForFrame(at time: CMTime, assetURL: URL) throws -> [UInt8] {
        let asset = AVURLAsset(url: assetURL)
        let generator = AVAssetImageGenerator(asset: asset)
        generator.appliesPreferredTrackTransform = true
        generator.requestedTimeToleranceBefore = .zero
        generator.requestedTimeToleranceAfter = .zero

        let cgImage = try generator.copyCGImage(at: time, actualTime: nil)
        let width = 32
        let height = 32
        let bytesPerRow = width * 4
        var pixels = [UInt8](repeating: 0, count: height * bytesPerRow)

        guard let context = CGContext(
            data: &pixels,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: bytesPerRow,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else {
            XCTFail("Failed to create bitmap context for frame comparison")
            return []
        }

        context.draw(cgImage, in: CGRect(x: 0, y: 0, width: width, height: height))
        return pixels
    }

    private func meanAbsolutePixelDifference(_ lhs: [UInt8], _ rhs: [UInt8]) -> Double {
        guard lhs.count == rhs.count, !lhs.isEmpty else { return 0 }

        let totalDifference = zip(lhs, rhs).reduce(0.0) { partialResult, pair in
            partialResult + abs(Double(pair.0) - Double(pair.1))
        }

        return totalDifference / Double(lhs.count) / 255.0
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
        let comparisonAssetURL = effectComparisonAssetURL()
        guard FileManager.default.fileExists(atPath: comparisonAssetURL.path) else {
            throw XCTSkip("Test asset not available")
        }

        let asset = AVURLAsset(url: comparisonAssetURL)
        let duration = try await asset.load(.duration)
        let trimmedDuration = min(duration.seconds, 2.0)
        let trimEnd = CMTime(seconds: trimmedDuration, preferredTimescale: 600)

        var clip = VideoClip(url: comparisonAssetURL, duration: duration, startTime: .zero)
        clip.trimEnd = trimEnd

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

        let comparisonTime = CMTime(seconds: min(0.5, max(trimmedDuration / 2, 0.1)), preferredTimescale: 600)
        let withoutPixels = try pixelBufferForFrame(at: comparisonTime, assetURL: tempWithout)
        let withPixels = try pixelBufferForFrame(at: comparisonTime, assetURL: tempWith)
        let normalizedDifference = meanAbsolutePixelDifference(withoutPixels, withPixels)

        XCTAssertGreaterThan(
            normalizedDifference,
            0.01,
            "Effect should measurably change rendered frame pixels. Normalized diff: \(normalizedDifference)"
        )
    }

    // MARK: - Error Type

    enum TestError: Error {
        case projectNotCreated
    }
}
