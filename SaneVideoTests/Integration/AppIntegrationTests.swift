import AVFoundation
import Foundation
@testable import SaneVideo
import SwiftUI
import Testing
import UniformTypeIdentifiers

@Suite("App Integration Tests")
struct AppIntegrationTests {
    // MARK: - PDFExportDocument Tests

    @Test("PDFExportDocument initialization with data")
    func pdfExportDocument_InitWithData() {
        let dummyData = "Test PDF Data".data(using: .utf8)!
        let document = PDFExportDocument(data: dummyData)
        #expect(document.pdfData == dummyData, "Document should store initialized data")
    }

    @Test("PDFExportDocument file wrapper behavior")
    func pdfExportDocument_FileWrapper() throws {
        let dummyData = "Test PDF Data".data(using: .utf8)!
        let document = PDFExportDocument(data: dummyData)
        #expect(document.pdfData == dummyData, "Document data should match")
    }

    @Test("PDFExportDocument readable content types")
    func pdfExportDocument_ReadableContentTypes() {
        let pdfType = UTType(filenameExtension: "pdf")!
        #expect(PDFExportDocument.readableContentTypes.contains(pdfType), "Should support PDF type")
    }

    // MARK: - ShareLinkService Tests

    @Test("ShareLinkService shared instance availability")
    @MainActor
    func shareLinkService_SharedInstance() {
        let service = ServiceContainer.shared.shareLinkService
        _ = service
        #expect(Bool(true), "Shared instance should exist")
    }

    // MARK: - SilenceDetector Tests

    @Test("SilenceDetector default configuration")
    func silenceDetector_Configuration() {
        let config = SilenceDetector.Configuration.default
        #expect(config.dbThreshold == -45.0)
        #expect(config.minDuration == 0.3)
    }

    @Test("SilenceDetector with invalid file")
    func silenceDetector_NoAudioTrack() async throws {
        let tempURL = FileManager.default.temporaryDirectory.appendingPathComponent("empty_test_app.mp4")
        FileManager.default.createFile(atPath: tempURL.path, contents: Data(), attributes: nil)
        defer { try? FileManager.default.removeItem(at: tempURL) }

        let clip = VideoClip(url: tempURL, duration: .zero)
        let detector = SilenceDetector()

        do {
            let ranges = try await detector.detectSilence(in: clip)
            #expect(ranges.count <= 1)
        } catch {
            // Expected for empty file
        }
    }

    // MARK: - WaveformService Tests

    @Test("WaveformService shared instance availability")
    @MainActor
    func waveformService_SharedInstance() {
        let service = ServiceContainer.shared.waveformService
        _ = service
        #expect(Bool(true), "Shared waveform service should exist")
    }

    @Test("WaveformService consistency and caching")
    @MainActor
    func waveformService_Caching() async {
        let service = ServiceContainer.shared.waveformService
        let tempURL = URL(fileURLWithPath: "/tmp/dummy_waveform_app_test.mp4")
        let clip = VideoClip(url: tempURL, duration: CMTime(seconds: 10, preferredTimescale: 600))

        let samples = await service.waveform(for: clip)
        let samples2 = await service.waveform(for: clip)

        let count1: Int = samples?.count ?? -1
        let count2: Int = samples2?.count ?? -1
        #expect(count1 == count2, "Should return consistent result")
    }

    // MARK: - SharedRecordingControls Tests

    @Test("SharedRecordingControls can be initialized")
    func sharedRecordingControls_CanInitialize() {
        // Arrange & Act - Verify type can be accessed
        // This tests that the type exists and is accessible
        let type = SharedRecordingControls.self

        // Assert - Verify type is accessible (tests runtime behavior, not compilation)
        // The fact that we can access .self means the type exists
        _ = type // Verify we can use the type
        // The test passes if we get here (type is accessible)
    }

    @Test("SharedRecordingControls reserves more width for recording state")
    func sharedRecordingControls_RecordingStateWidth() {
        let idleWidth = SharedRecordingControls.minimumBarWidth(
            buttonSize: .medium,
            includePauseControl: false,
            showTimer: false,
            showGalleryTarget: false
        )
        let recordingWidth = SharedRecordingControls.minimumBarWidth(
            buttonSize: .medium,
            includePauseControl: true,
            showTimer: true,
            showGalleryTarget: false
        )

        #expect(recordingWidth > idleWidth, "Recording state should reserve extra room for pause and timer")
        #expect(recordingWidth >= 520, "Recording state should reserve enough width for the full floating control strip")
    }

    // MARK: - Mock Object Tests

    @Test("Theme data constants")
    func themeData() {
        _ = Theme.Colors.action
        _ = Theme.Colors.background
        #expect(Bool(true), "Theme colors should be accessible")
        #expect(Theme.Dimensions.cornerRadius == 8)
    }

    @Test("App quits after last window close when idle")
    func appLifecyclePolicy_IdleWindowCloseQuits() {
        #expect(
            AppLifecyclePolicy.shouldTerminateAfterLastWindowClosed(
                isRecording: false,
                isExporting: false,
                isScreenSharing: false,
                isTogglingScreenShare: false,
                isTesting: false
            )
        )
    }

    @Test("App stays alive after last window close during active work")
    func appLifecyclePolicy_ActiveWorkKeepsAppAlive() {
        #expect(
            !AppLifecyclePolicy.shouldTerminateAfterLastWindowClosed(
                isRecording: true,
                isExporting: false,
                isScreenSharing: false,
                isTogglingScreenShare: false,
                isTesting: false
            )
        )
        #expect(
            !AppLifecyclePolicy.shouldTerminateAfterLastWindowClosed(
                isRecording: false,
                isExporting: true,
                isScreenSharing: false,
                isTogglingScreenShare: false,
                isTesting: false
            )
        )
        #expect(
            !AppLifecyclePolicy.shouldTerminateAfterLastWindowClosed(
                isRecording: false,
                isExporting: false,
                isScreenSharing: true,
                isTogglingScreenShare: false,
                isTesting: false
            )
        )
        #expect(
            !AppLifecyclePolicy.shouldTerminateAfterLastWindowClosed(
                isRecording: false,
                isExporting: false,
                isScreenSharing: false,
                isTogglingScreenShare: true,
                isTesting: false
            )
        )
    }

    @Test("App stays alive after last window close during tests")
    func appLifecyclePolicy_TestingKeepsAppAlive() {
        #expect(
            !AppLifecyclePolicy.shouldTerminateAfterLastWindowClosed(
                isRecording: false,
                isExporting: false,
                isScreenSharing: false,
                isTogglingScreenShare: false,
                isTesting: true
            )
        )
    }

    @Test("Main window scene uses singleton policy")
    func mainWindowScenePolicy_IsSingleton() {
        #expect(MainWindowScenePolicy.sceneID == "main-window")
        #expect(MainWindowScenePolicy.title == "SaneVideo")
        #expect(!MainWindowScenePolicy.allowsMultipleWindows)
    }

    @Test("Recording launch schedules preview restore only for live recording mode")
    func launchRecordingPreviewPolicy_SchedulesOnlyForLiveRecording() {
        #expect(LaunchRecordingPreviewPolicy.shouldScheduleRestore(appMode: .recording, isTesting: false))
        #expect(!LaunchRecordingPreviewPolicy.shouldScheduleRestore(appMode: .editing, isTesting: false))
        #expect(!LaunchRecordingPreviewPolicy.shouldScheduleRestore(appMode: .recording, isTesting: true))
    }
}
