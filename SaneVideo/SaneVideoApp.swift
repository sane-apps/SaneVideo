//
//  SaneVideoApp.swift
//  SaneVideo
//
//  Created by Mr. Sane on 11/23/25.
//

import AppKit
#if !APP_STORE
    import Sparkle
#endif
import SaneUI
import SwiftUI

@main
struct SaneVideoApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    @State private var appState = ServiceContainer.shared.appState
    @State private var prefs = ServiceContainer.shared.userPreferences
    @State private var licenseService = LicenseService(
        appName: "SaneVideo",
        checkoutURL: LicenseService.directCheckoutURL(appSlug: "sanevideo")
    )
    @AppStorage("hasSeenWelcome") private var hasSeenWelcome = false
    @Environment(\.scenePhase) private var scenePhase

    #if !APP_STORE
        // Sparkle auto-update service (manual check only for launch)
        @State private var updaterService = ServiceContainer.shared.updaterService
    #endif

    var body: some Scene {
        WindowGroup(MainWindowScenePolicy.title, id: MainWindowScenePolicy.sceneID) {
            MainContentView()
                .environment(licenseService)
                .environment(appState)
                .environment(ServiceContainer.shared.errorPresenter)
                .preferredColorScheme(
                    prefs.appTheme == .system ? nil : (prefs.appTheme == .dark ? .dark : .light)
                )
                .background(MainWindowOpenRegistrar())
                .background(MainWindowCaptureView())
                .onAppear {
                    licenseService.checkCachedLicense()
                }
                .onChange(of: scenePhase) { _, newPhase in
                    if newPhase == .background || newPhase == .inactive {
                        appState.saveCurrentState()
                    }
                }
                .onAppear {
                    NSLog("🚀 SaneVideoApp: main window onAppear")
                    setupWindow()

                    // Force .editing mode for automation launches after the window is available.
                    if TestEnvironment.shouldOpenEditor {
                        NSLog("🚀 SaneVideoApp: Forcing .editing mode from onAppear")
                        appState.appMode = .editing
                        Task { await appState.bootstrapEditorForTesting() }
                    }
                }
                .sheet(isPresented: Binding(
                    get: { !hasSeenWelcome },
                    set: { isShowing in
                        if !isShowing {
                            hasSeenWelcome = true
                        }
                    }
                )) {
                    WelcomeGateView(
                        appName: "SaneVideo",
                        appIcon: "play.tv",
                        freeFeatures: [
                            (icon: "film", text: "Edit and trim local videos"),
                            (icon: "camera", text: "AI-powered cleanup & subtitles"),
                            (icon: "bolt", text: "Project templates and export presets")
                        ],
                        proFeatures: [
                            (icon: "checkmark.seal", text: "Optional during public testing"),
                            (icon: "wand.and.rays", text: "Support the app while the workflow hardens"),
                            (icon: "rectangle.on.rectangle.circle", text: "Keep Pro access as paid features land"),
                            (icon: "sparkles", text: "Support Pro for $14.99 once"),
                            (icon: "square.stack.3d.up", text: "One-time unlock, no subscription")
                        ],
                        licenseService: licenseService
                    )
                    .preferredColorScheme(.dark)
                }
        }
        .defaultSize(width: AppConstants.defaultWindowWidth, height: AppConstants.defaultWindowHeight)

        Settings {
            SettingsView()
                .environment(licenseService)
        }

        .commands {
            #if !APP_STORE
                // Sparkle: Check for Updates (after About SaneVideo)
                CommandGroup(after: .appInfo) {
                    Button(String(localized: "menu.app.check_updates", defaultValue: "Check for Updates...")) {
                        updaterService.checkForUpdates()
                    }
                    .disabled(!updaterService.canCheckForUpdates)
                    .accessibilityIdentifier("menu.app.check_updates")
                }
            #endif

            CommandGroup(replacing: .newItem) {
                Button(String(localized: "menu.file.new_recording", defaultValue: "New Recording")) {
                    appState.startNewRecording()
                }
                .keyboardShortcut("n", modifiers: [.command])
                .accessibilityIdentifier("menu.file.new_recording")
            }

            CommandGroup(after: .importExport) {
                Button(String(localized: "menu.file.open_project", defaultValue: "Show Projects")) {
                    NotificationCenter.default.post(
                        name: NSNotification.Name("ShowSidebarProjects"), object: nil
                    )
                }
                .keyboardShortcut("o", modifiers: [.command])
                .accessibilityIdentifier("menu.file.show_projects")

                Button(String(localized: "menu.file.import_video", defaultValue: "Import Video...")) {
                    appState.importVideo()
                }
                .keyboardShortcut("i", modifiers: [.command])
                .accessibilityIdentifier("menu.file.import_video")
            }

            CommandGroup(after: .sidebar) {
                Button(String(localized: "menu.view.toggle_sidebar", defaultValue: "Toggle Sidebar")) {
                    NotificationCenter.default.post(name: NSNotification.Name("ToggleSidebar"), object: nil)
                }
                .keyboardShortcut("s", modifiers: [.command, .option])
                .accessibilityIdentifier("menu.view.toggle_sidebar")

                Button(String(localized: "menu.view.toggle_inspector", defaultValue: "Toggle Inspector")) {
                    NotificationCenter.default.post(name: NSNotification.Name("ToggleInspector"), object: nil)
                }
                .keyboardShortcut("i", modifiers: [.command, .option])
                .accessibilityIdentifier("menu.view.toggle_inspector")
            }
            // NOTE: Up/Down Arrow and D key shortcuts are handled via .onKeyPress() in EditorLayoutView
            // Menu commands with arrow keys don't work (arrows are used for menu navigation)

            // Edit Menu: Magic Fix Batch Operations
            CommandGroup(after: .undoRedo) {
                Divider()

                Button(String(localized: "menu.edit.magic_fix", defaultValue: "Magic Fix Selected Clip")) {
                    NotificationCenter.default.post(name: NSNotification.Name("TriggerMagicFix"), object: nil)
                }
                .keyboardShortcut("m", modifiers: [.command, .shift])
                .accessibilityIdentifier("menu.edit.magic_fix")

                Button(String(localized: "menu.edit.magic_fix_all", defaultValue: "Magic Fix All Clips")) {
                    NotificationCenter.default.post(
                        name: NSNotification.Name("TriggerMagicFixAll"), object: nil
                    )
                }
                .accessibilityIdentifier("menu.edit.magic_fix_all")

                Divider()

                Button(
                    String(
                        localized: "menu.edit.generate_all_captions", defaultValue: "Generate All Captions"
                    )
                ) {
                    NotificationCenter.default.post(
                        name: NSNotification.Name("GenerateAllCaptions"), object: nil
                    )
                }
                .accessibilityIdentifier("menu.edit.generate_all_captions")

                Button(String(localized: "menu.edit.clean_all_audio", defaultValue: "Clean All Audio")) {
                    NotificationCenter.default.post(name: NSNotification.Name("CleanAllAudio"), object: nil)
                }
                .accessibilityIdentifier("menu.edit.clean_all_audio")
            }

            CommandGroup(replacing: .saveItem) {
                Button(String(localized: "menu.file.save_project", defaultValue: "Save Project")) {
                    if let project = appState.projectState.currentProject {
                        appState.projectState.saveProject(project)
                    }
                }
                .keyboardShortcut("s", modifiers: [.command])
                .accessibilityIdentifier("menu.file.save_project")

                Button(String(localized: "menu.file.rename_project", defaultValue: "Rename Project...")) {
                    NotificationCenter.default.post(
                        name: NSNotification.Name("ShowRenameProjectDialog"), object: nil
                    )
                }
                .accessibilityIdentifier("menu.file.rename_project")
            }

            CommandGroup(after: .importExport) {
                Button(String(localized: "menu.file.export_video", defaultValue: "Export Video...")) {
                    appState.showExportSheet = true
                }
                .keyboardShortcut("e", modifiers: [.command])
                .accessibilityIdentifier("menu.file.export_video")

                Button(String(localized: "menu.file.demo_studio", defaultValue: "Demo Studio...")) {
                    appState.openDemoStudio()
                }
                .keyboardShortcut("d", modifiers: [.command, .shift])
                .accessibilityIdentifier("menu.file.demo_studio")

                Button(String(localized: "menu.file.build_commentary_reel", defaultValue: "Build Commentary Reel")) {
                    appState.buildCommentaryReel()
                }
                .keyboardShortcut("b", modifiers: [.command, .option])
                .accessibilityIdentifier("menu.file.build_commentary_reel")

                Button(String(localized: "menu.view.teleprompter", defaultValue: "Toggle Teleprompter")) {
                    appState.toggleTeleprompter()
                }
                .accessibilityIdentifier("menu.view.teleprompter")

                Divider()

                Button(String(localized: "menu.file.export_gif", defaultValue: "Export as GIF...")) {
                    NotificationCenter.default.post(name: NSNotification.Name("ExportAsGIF"), object: nil)
                }
                .keyboardShortcut("g", modifiers: [.command, .shift])
                .accessibilityIdentifier("menu.file.export_gif")

                Button(
                    String(
                        localized: "menu.file.export_transcript", defaultValue: "Export Transcript (PDF)..."
                    )
                ) {
                    NotificationCenter.default.post(
                        name: NSNotification.Name("ExportTranscriptPDF"), object: nil
                    )
                }
                .keyboardShortcut("t", modifiers: [.command, .option])
                .accessibilityIdentifier("menu.file.export_transcript")

                Divider()

                Button(
                    String(localized: "menu.file.generate_thumbnail", defaultValue: "Generate AI Thumbnail")
                ) {
                    NotificationCenter.default.post(
                        name: NSNotification.Name("GenerateThumbnail"), object: nil
                    )
                }
                .keyboardShortcut("t", modifiers: [.command])
                .accessibilityIdentifier("menu.file.generate_thumbnail")

                Button(
                    String(localized: "menu.file.generate_voiceover", defaultValue: "Generate Voiceover")
                ) {
                    NotificationCenter.default.post(
                        name: NSNotification.Name("GenerateVoiceover"), object: nil
                    )
                }
                .accessibilityIdentifier("menu.file.generate_voiceover")

                Button(
                    String(localized: "menu.file.create_shorts", defaultValue: "Create Shorts...")
                ) {
                    NotificationCenter.default.post(
                        name: NSNotification.Name("ShowRepurposingSheet"), object: nil
                    )
                }
                .keyboardShortcut("r", modifiers: [.command, .shift])
                .accessibilityIdentifier("menu.file.create_shorts")

                Divider()

                Button(String(localized: "menu.file.share", defaultValue: "Share...")) {
                    NotificationCenter.default.post(name: NSNotification.Name("ShareProject"), object: nil)
                }
                .keyboardShortcut("s", modifiers: [.command, .shift])
                .accessibilityIdentifier("menu.file.share")
            }

            CommandGroup(replacing: .help) {
                Button(String(localized: "menu.help.shortcuts", defaultValue: "Keyboard Shortcuts")) {
                    NotificationCenter.default.post(
                        name: NSNotification.Name("ShowKeyboardShortcuts"), object: nil
                    )
                }
                .keyboardShortcut("?", modifiers: [.command])
                .accessibilityIdentifier("menu.help.shortcuts")

                Button(String(localized: "menu.help.sane_video_help", defaultValue: "SaneVideo Help")) {
                    NotificationCenter.default.post(
                        name: NSNotification.Name("ShowKeyboardShortcuts"), object: nil
                    )
                }
            }
        }
    }

    private func setupWindow() {
        if let window = NSApplication.shared.windows.first {
            window.titlebarAppearsTransparent = true
            window.backgroundColor = NSColor(white: 0.1, alpha: 1.0)
            window.isOpaque = false
        }
    }
}

enum MainWindowScenePolicy {
    static let sceneID = "main-window"
    static let title = "SaneVideo"
    static let allowsMultipleWindows = false
}

enum MainWindowReopenPolicy {
    static func shouldShowMainWindow(hasVisibleWindows: Bool) -> Bool {
        !hasVisibleWindows
    }
}

@MainActor
final class MainWindowActionStorage {
    static let shared = MainWindowActionStorage()

    var openWindow: ((String) -> Void)?
    weak var mainWindow: NSWindow?

    func capture(_ action: OpenWindowAction) {
        openWindow = { id in
            action(id: id)
        }
    }

    func captureMainWindow(_ window: NSWindow?) {
        guard let window, window.canBecomeMain, !window.isSheet else { return }
        mainWindow = window
    }

    func showMainWindow() {
        let window = mainWindow ?? NSApp.windows.first(where: {
            $0.canBecomeMain &&
                $0.contentView != nil &&
                ($0.identifier?.rawValue.contains(MainWindowScenePolicy.sceneID) == true ||
                    $0.title.contains(MainWindowScenePolicy.title) ||
                    $0.title.isEmpty)
        })

        if let window {
            if window.isMiniaturized {
                window.deminiaturize(nil)
            }
            window.makeKeyAndOrderFront(nil)
            mainWindow = window
        } else {
            openWindow?(MainWindowScenePolicy.sceneID)
        }

        NSApp.activate(ignoringOtherApps: true)
    }
}

private struct MainWindowOpenRegistrar: View {
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        Color.clear
            .frame(width: 0, height: 0)
            .allowsHitTesting(false)
            .onAppear {
                MainWindowActionStorage.shared.capture(openWindow)
                ServiceContainer.shared.appState.windowManager.registerMainWindowOpener {
                    openWindow(id: MainWindowScenePolicy.sceneID)
                }
            }
    }
}

private struct MainWindowCaptureView: NSViewRepresentable {
    func makeNSView(context _: Context) -> NSView {
        let view = NSView()
        DispatchQueue.main.async {
            MainWindowActionStorage.shared.captureMainWindow(view.window)
        }
        return view
    }

    func updateNSView(_ nsView: NSView, context _: Context) {
        DispatchQueue.main.async {
            MainWindowActionStorage.shared.captureMainWindow(nsView.window)
        }
    }
}

enum AppLifecyclePolicy {
    static func shouldTerminateAfterLastWindowClosed(
        isRecording: Bool,
        isExporting: Bool,
        isScreenSharing: Bool,
        isTogglingScreenShare: Bool,
        isTesting: Bool = false
    ) -> Bool {
        !isTesting && !isRecording && !isExporting && !isScreenSharing && !isTogglingScreenShare
    }
}

// MARK: - App Delegate

@MainActor
class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_: Notification) {
        // Initialize global hotkey manager
        #if !APP_STORE
            ServiceContainer.shared.globalHotkeyManager.start()
        #endif

        // Initialize LogManager to capture early logs
        _ = ServiceContainer.shared.logManager

        // Initialize MetricKit crash and performance monitoring
        ServiceContainer.shared.crashReporter.start()

        // Initialize memory pressure handling
        Task { @MainActor in
            _ = ServiceContainer.shared.memoryManager // Initialize to start memory pressure observer
        }

        // Clean up orphaned temp files from previous crash/incomplete sessions
        Task.detached(priority: .utility) {
            await Self.cleanupOrphanedTempFiles()
        }

        // NOTE: Apple Speech Recognition is used for captions (no model download needed)
        // Camera is NOT started on app launch for privacy.
        // It will start automatically when user clicks Record or toggles Camera on.
    }

    /// Clean up orphaned temp files that may have been left from crashed sessions
    private static func cleanupOrphanedTempFiles() async {
        let fileManager = FileManager.default

        // 1. Clean up EnhancedAudio temp directory
        let enhancedAudioDir = fileManager.temporaryDirectory.appendingPathComponent("EnhancedAudio")
        if fileManager.fileExists(atPath: enhancedAudioDir.path) {
            do {
                let contents = try fileManager.contentsOfDirectory(at: enhancedAudioDir, includingPropertiesForKeys: [.creationDateKey])
                let cutoffDate = Date().addingTimeInterval(-24 * 60 * 60) // 24 hours ago

                for file in contents {
                    if let attrs = try? file.resourceValues(forKeys: [.creationDateKey]),
                       let created = attrs.creationDate,
                       created < cutoffDate {
                        try? fileManager.removeItem(at: file)
                        AppLogger.general.info("Cleaned up orphaned temp file: \(file.lastPathComponent)")
                    }
                }
            } catch {
                AppLogger.general.warning("Failed to clean EnhancedAudio temp dir: \(error.localizedDescription)")
            }
        }

        // 2. Clean up orphaned recordings (incomplete MP4s from crashed sessions)
        guard let moviesDir = fileManager.urls(for: .moviesDirectory, in: .userDomainMask).first else { return }
        let recordingsDir = moviesDir.appendingPathComponent("SaneVideo/Recordings")

        if fileManager.fileExists(atPath: recordingsDir.path) {
            do {
                let contents = try fileManager.contentsOfDirectory(at: recordingsDir, includingPropertiesForKeys: [.creationDateKey, .fileSizeKey])
                let cutoffDate = Date().addingTimeInterval(-24 * 60 * 60) // 24 hours ago

                for file in contents where file.pathExtension.lowercased() == "mp4" {
                    if let attrs = try? file.resourceValues(forKeys: [.creationDateKey, .fileSizeKey]),
                       let created = attrs.creationDate,
                       let size = attrs.fileSize,
                       created < cutoffDate,
                       size < 1024 * 1024 { // Less than 1MB = likely incomplete/corrupt
                        try? fileManager.removeItem(at: file)
                        AppLogger.general.info("Cleaned up orphaned recording: \(file.lastPathComponent)")
                    }
                }
            } catch {
                AppLogger.general.warning("Failed to clean recordings dir: \(error.localizedDescription)")
            }
        }

        // 3. Clean up WhisperKit temp files
        let whisperTempDir = fileManager.temporaryDirectory.appendingPathComponent("whisperkit_temp")
        if fileManager.fileExists(atPath: whisperTempDir.path) {
            do {
                let contents = try fileManager.contentsOfDirectory(at: whisperTempDir, includingPropertiesForKeys: [.creationDateKey])
                let cutoffDate = Date().addingTimeInterval(-24 * 60 * 60)

                for file in contents {
                    if let attrs = try? file.resourceValues(forKeys: [.creationDateKey]),
                       let created = attrs.creationDate,
                       created < cutoffDate {
                        try? fileManager.removeItem(at: file)
                        AppLogger.general.info("Cleaned up WhisperKit temp file: \(file.lastPathComponent)")
                    }
                }
            } catch {
                AppLogger.general.warning("Failed to clean WhisperKit temp dir: \(error.localizedDescription)")
            }
        }
    }

    func applicationShouldTerminateAfterLastWindowClosed(_: NSApplication) -> Bool {
        return AppLifecyclePolicy.shouldTerminateAfterLastWindowClosed(
            isRecording: ServiceContainer.shared.appState.recordingState.isRecording,
            isExporting: ServiceContainer.shared.exportService.isExporting,
            isScreenSharing: ServiceContainer.shared.appState.windowManager.isScreenSharing,
            isTogglingScreenShare: ServiceContainer.shared.appState.windowManager.isTogglingScreenShare,
            isTesting: TestEnvironment.isTesting
        )
    }

    func applicationShouldHandleReopen(_: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if MainWindowReopenPolicy.shouldShowMainWindow(hasVisibleWindows: flag) {
            MainWindowActionStorage.shared.showMainWindow()
            ServiceContainer.shared.appState.windowManager.restoreMainWindow()
        }
        return true
    }

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        if ServiceContainer.shared.appState.recordingState.isRecording {
            // If recording, try to stop safely first
            ServiceContainer.shared.appState.recordingState.stopRecording { _ in
                // CRITICAL: Await cleanup on MainActor to ensure moov atom is written
                Task { @MainActor in
                    ServiceContainer.shared.appState.windowManager.cleanupAllWindows()
                    ServiceContainer.shared.appState.saveCurrentState()
                    sender.reply(toApplicationShouldTerminate: true)
                }
            }
            return .terminateLater
        }

        // RELIABILITY FIX: Check for active exports and cancel gracefully
        if ServiceContainer.shared.exportService.isExporting {
            AppLogger.general.warning("App terminating during active export - cancelling export")
            ServiceContainer.shared.exportService.cancelExport()
            // Give export a moment to cleanup before terminating
            Task { @MainActor in
                try? await Task.sleep(nanoseconds: 500_000_000) // 0.5 second for cleanup
                ServiceContainer.shared.appState.windowManager.cleanupAllWindows()
                ServiceContainer.shared.appState.saveCurrentState()
                sender.reply(toApplicationShouldTerminate: true)
            }
            return .terminateLater
        }

        // CRITICAL FIX: Close all windows before quitting
        Task { @MainActor in
            ServiceContainer.shared.appState.windowManager.cleanupAllWindows()
            ServiceContainer.shared.appState.saveCurrentState()
        }
        return .terminateNow
    }
}
