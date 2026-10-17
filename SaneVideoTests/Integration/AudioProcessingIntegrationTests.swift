// Audio features run against the real fixture clip (Tests/Assets/test_video.mp4, 5 s with a tone).
// Silence detection on real audio lives in SilenceDetectorTests.

import AVFoundation
import CoreMedia
@testable import SaneVideo
import Testing

@Suite("Audio Processing Integration")
struct AudioProcessingIntegrationTests {
    private var assetURL: URL {
        TestEnvironment.mockAssetURL
    }

    @Test("Voice isolation loads its audio unit")
    @MainActor
    func voiceIsolationServiceInitializes() async {
        let service = VoiceIsolationService()

        await service.prepareIsolationUnit()

        #expect(service.isReady)
        #expect(service.getAudioUnit() != nil)
    }

    @Test("Waveform of a clip with sound is non-empty and normalized to 0...1")
    func waveformServiceGeneratesData() async throws {
        let asset = AVURLAsset(url: assetURL)
        let duration = try await asset.load(.duration)
        let clip = VideoClip(url: assetURL, duration: duration, startTime: .zero)

        let waveform = try #require(await WaveformService().waveform(for: clip))

        #expect(!waveform.isEmpty)
        #expect(waveform.allSatisfy { (0.0 ... 1.0).contains($0) })
        #expect(waveform.contains { $0 > 0 })
    }

    @Test("Export with noise gating enabled produces a playable file")
    @MainActor
    func exportWithGatingEnabled() async throws {
        let asset = AVURLAsset(url: assetURL)
        let duration = try await asset.load(.duration)
        var clip = VideoClip(url: assetURL, duration: duration, startTime: .zero)
        clip.isGatingEnabled = true

        let projectState = ProjectState(projectStore: MockProjectStore())
        projectState.startNewProject()
        projectState.addClip(clip)
        let project = try #require(projectState.currentProject)

        let outputURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("gating_test_\(UUID().uuidString).mp4")
        defer { try? FileManager.default.removeItem(at: outputURL) }

        let exported = try await ExportEngine().export(
            project: project,
            settings: SaneExportSettings(),
            outputURL: outputURL
        ) { _ in }

        let exportedAsset = AVURLAsset(url: exported)
        #expect(try await exportedAsset.load(.isPlayable))
        let exportedDuration = try await exportedAsset.load(.duration).seconds
        #expect(abs(exportedDuration - duration.seconds) < 0.2)
    }
}
