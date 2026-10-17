// Effects and transitions export integration tests.
// Split from ExportPipelineIntegrationTests for maintainability.

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
            settings: SaneExportSettings(resolution: .hd1080),
            outputURL: tempOutputURL
        ) { _ in }

        let exportedAsset = try await verifyExportedFile(at: outputURL)
        let exportedDuration = try await exportedAsset.load(.duration)
        // Both halves must render: longer than one clip, no longer than the source.
        XCTAssertGreaterThan(exportedDuration.seconds, duration.seconds / 2 + 0.1)
        XCTAssertLessThanOrEqual(exportedDuration.seconds, duration.seconds + 0.1)
    }

    // MARK: - Effect Verification (Pixel Data)

    /// Exports the first two seconds of the comparison asset with the given effects applied
    /// and returns a 32x32 RGBA thumbnail of the frame at 0.5 s.
    @MainActor
    private func exportedFrame(assetURL: URL, effects: [VideoEffectType]) async throws -> [UInt8] {
        let asset = AVURLAsset(url: assetURL)
        let duration = try await asset.load(.duration)
        var clip = VideoClip(url: assetURL, duration: duration, startTime: .zero)
        clip.trimEnd = CMTime(seconds: min(duration.seconds, 2.0), preferredTimescale: 600)

        projectState.startNewProject()
        projectState.addTrack(type: .video, name: "Video Track 1")
        projectState.addClip(clip)
        for effectType in effects {
            guard let current = projectState.getClip(by: clip.id) else {
                throw TestError.projectNotCreated
            }
            projectState.applyEffect(to: current, effect: VideoEffect(type: effectType))
        }

        guard let project = projectState.currentProject else {
            throw TestError.projectNotCreated
        }

        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("effect_\(UUID().uuidString).mp4")
        defer { try? FileManager.default.removeItem(at: url) }

        _ = try await exportEngine.export(
            project: project,
            settings: SaneExportSettings(resolution: .hd1080),
            outputURL: url
        ) { _ in }

        let comparisonTime = CMTime(seconds: 0.5, preferredTimescale: 600)
        return try pixelBufferForFrame(at: comparisonTime, assetURL: url)
    }

    /// Covers both a single effect (noir) and a stacked pair (auto-enhance + vignette):
    /// each must change rendered pixels compared with the same clip exported without effects.
    @MainActor
    func testEffectsModifyPixelData() async throws {
        let comparisonAssetURL = effectComparisonAssetURL()
        guard FileManager.default.fileExists(atPath: comparisonAssetURL.path) else {
            throw XCTSkip("Test asset not available")
        }

        let plain = try await exportedFrame(assetURL: comparisonAssetURL, effects: [])
        let cases: [[VideoEffectType]] = [[.noir], [.autoEnhance, .vignette]]

        for effects in cases {
            let withEffects = try await exportedFrame(assetURL: comparisonAssetURL, effects: effects)
            let difference = meanAbsolutePixelDifference(plain, withEffects)
            XCTAssertGreaterThan(
                difference,
                0.01,
                "Effects \(effects.map(\.rawValue)) should measurably change rendered pixels. Normalized diff: \(difference)"
            )
        }
    }

    // MARK: - Error Type

    enum TestError: Error {
        case projectNotCreated
    }
}
