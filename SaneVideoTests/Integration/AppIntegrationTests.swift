import AVFoundation
import Foundation
@testable import SaneVideo
import Testing

@Suite("App Integration Tests")
struct AppIntegrationTests {
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

    @Test(
        "App stays alive after the last window closes while recording, exporting or under test",
        arguments: [(true, false, false), (false, true, false), (false, false, true)]
    )
    func appLifecyclePolicy_ActiveWorkKeepsAppAlive(isRecording: Bool, isExporting: Bool, isTesting: Bool) {
        #expect(
            !AppLifecyclePolicy.shouldTerminateAfterLastWindowClosed(
                isRecording: isRecording,
                isExporting: isExporting,
                isTesting: isTesting
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
