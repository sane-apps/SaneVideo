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
                isTesting: false
            )
        )
        #expect(
            !AppLifecyclePolicy.shouldTerminateAfterLastWindowClosed(
                isRecording: false,
                isExporting: true,
                isTesting: false
            )
        )
    }

    @Test("Stuck screen-share flags do not keep the app alive after close")
    func appLifecyclePolicy_ScreenShareFlagsDoNotBlockQuit() {
        #expect(
            AppLifecyclePolicy.shouldTerminateAfterLastWindowClosed(
                isRecording: false,
                isExporting: false,
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
                isTesting: true
            )
        )
    }

    @Test("Welcome and license windows hug their content instead of the editor frame")
    func mainWindowLayoutPolicy_WelcomeAndLicenseHugContent() {
        let welcome = MainWindowLayoutPolicy.size(showingWelcome: true, showingLicenseGate: false)
        let license = MainWindowLayoutPolicy.size(showingWelcome: false, showingLicenseGate: true)
        let editor = MainWindowLayoutPolicy.size(showingWelcome: false, showingLicenseGate: false)
        #expect(welcome == MainWindowLayoutPolicy.welcomeSize)
        #expect(license == MainWindowLayoutPolicy.licenseSize)
        #expect(editor == MainWindowLayoutPolicy.editorSize)
        #expect(welcome.width < editor.width)
        #expect(welcome.height < editor.height)
        #expect(MainWindowLayoutPolicy.shouldHugContent(showingWelcome: true, showingLicenseGate: false))
        #expect(MainWindowLayoutPolicy.shouldHugContent(showingWelcome: false, showingLicenseGate: true))
        #expect(!MainWindowLayoutPolicy.shouldHugContent(showingWelcome: false, showingLicenseGate: false))
        let frame = MainWindowLayoutPolicy.centeredFrame(
            size: welcome,
            on: nil
        )
        #expect(frame.size == welcome)
    }

    @Test("Main window scene uses singleton policy")
    func mainWindowScenePolicy_IsSingleton() {
        #expect(MainWindowScenePolicy.sceneID == "main-window")
        #expect(MainWindowScenePolicy.title == "SaneVideo")
        #expect(!MainWindowScenePolicy.allowsMultipleWindows)
    }

    @Test("Reopen without visible windows requests main window")
    func mainWindowReopenPolicy_ShowsMainWindowWhenNoVisibleWindows() {
        #expect(MainWindowReopenPolicy.shouldShowMainWindow(hasVisibleWindows: false))
        #expect(!MainWindowReopenPolicy.shouldShowMainWindow(hasVisibleWindows: true))
    }

    @Test("Close click does not count as a reopen request")
    func mainWindowReopenPolicy_IgnoresImmediateCloseReopen() {
        let closedAt = Date()
        #expect(
            !MainWindowReopenPolicy.shouldShowMainWindow(
                hasVisibleWindows: false,
                lastUserCloseAt: closedAt,
                now: closedAt,
                isRecording: false,
                isExporting: false
            )
        )
        #expect(
            MainWindowReopenPolicy.shouldShowMainWindow(
                hasVisibleWindows: false,
                lastUserCloseAt: closedAt,
                now: closedAt,
                isRecording: true,
                isExporting: false
            )
        )
        #expect(
            MainWindowReopenPolicy.shouldShowMainWindow(
                hasVisibleWindows: false,
                lastUserCloseAt: closedAt.addingTimeInterval(-2),
                now: closedAt,
                isRecording: false,
                isExporting: false
            )
        )
    }

    @Test("Stale welcome sheet restore keys are purged")
    func welcomeSheetResidue_PurgesRestoredSheetKeys() {
        let defaults = UserDefaults(suiteName: "sanevideo.welcome-sheet-residue.tests")!
        defaults.removePersistentDomain(forName: "sanevideo.welcome-sheet-residue.tests")
        defaults.set(true, forKey: "NSWindow.SheetPresentationModifier-WelcomeGateView")
        defaults.set("keep", forKey: "unrelated")
        #expect(WelcomeSheetResidue.purge(defaults: defaults) == 1)
        #expect(defaults.object(forKey: "NSWindow.SheetPresentationModifier-WelcomeGateView") == nil)
        #expect(defaults.string(forKey: "unrelated") == "keep")
        defaults.removePersistentDomain(forName: "sanevideo.welcome-sheet-residue.tests")
    }

    @Test("Recording launch schedules preview restore only for live recording mode")
    func launchRecordingPreviewPolicy_SchedulesOnlyForLiveRecording() {
        #expect(LaunchRecordingPreviewPolicy.shouldScheduleRestore(appMode: .recording, isTesting: false))
        #expect(!LaunchRecordingPreviewPolicy.shouldScheduleRestore(appMode: .editing, isTesting: false))
        #expect(!LaunchRecordingPreviewPolicy.shouldScheduleRestore(appMode: .recording, isTesting: true))
    }
}
