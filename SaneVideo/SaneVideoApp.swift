//
//  SaneVideoApp.swift
//  SaneVideo
//
//  Created by Stephan Joseph on 11/23/25.
//

import AppKit
import Sparkle
import SwiftUI

@main
struct SaneVideoApp: App {
  @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
  @State private var appState = ServiceContainer.shared.appState
  @State private var prefs = ServiceContainer.shared.userPreferences
  @Environment(\.scenePhase) private var scenePhase

  // Sparkle auto-update service (manual check only for launch)
  @State private var updaterService = UpdaterService()

  var body: some Scene {
    WindowGroup {
      MainContentView()
        .environment(appState)
        .environment(ServiceContainer.shared.errorPresenter)
        .preferredColorScheme(
          prefs.appTheme == .system ? nil : (prefs.appTheme == .dark ? .dark : .light)
        )
        .onChange(of: scenePhase) { _, newPhase in
          if newPhase == .background || newPhase == .inactive {
            appState.saveCurrentState()
          }
        }
        .onAppear {
          NSLog("🚀 SaneVideoApp: WindowGroup onAppear")
          setupWindow()

          // CRITICAL FIX: Force .editing mode if argument is present (handling init race conditions)
          let args = ProcessInfo.processInfo.arguments
          if args.contains("-open_editor") || UserDefaults.standard.bool(forKey: "open_editor") {
            NSLog("🚀 SaneVideoApp: Forcing .editing mode from onAppear")
            appState.appMode = .editing
            Task { await appState.bootstrapEditorForTesting() }
          }
        }
    }
    .defaultSize(width: AppConstants.defaultWindowWidth, height: AppConstants.defaultWindowHeight)

    Settings {
      SettingsView()
    }

    .commands {
      // Sparkle: Check for Updates (after About SaneVideo)
      CommandGroup(after: .appInfo) {
        Button(String(localized: "menu.app.check_updates", defaultValue: "Check for Updates...")) {
          updaterService.checkForUpdates()
        }
        .disabled(!updaterService.canCheckForUpdates)
        .accessibilityIdentifier("menu.app.check_updates")
      }

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
            name: NSNotification.Name("ShowSidebarProjects"), object: nil)
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
            name: NSNotification.Name("TriggerMagicFixAll"), object: nil)
        }
        .accessibilityIdentifier("menu.edit.magic_fix_all")

        Divider()

        Button(
          String(
            localized: "menu.edit.generate_all_captions", defaultValue: "Generate All Captions")
        ) {
          NotificationCenter.default.post(
            name: NSNotification.Name("GenerateAllCaptions"), object: nil)
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
            name: NSNotification.Name("ShowRenameProjectDialog"), object: nil)
        }
        .accessibilityIdentifier("menu.file.rename_project")
      }

      CommandGroup(after: .toolbar) {
        Button(String(localized: "menu.file.export_video", defaultValue: "Export Video...")) {
          appState.showExportSheet = true
        }
        .keyboardShortcut("e", modifiers: [.command])
        .accessibilityIdentifier("menu.file.export_video")

        Divider()

        Button(String(localized: "menu.file.export_gif", defaultValue: "Export as GIF...")) {
          NotificationCenter.default.post(name: NSNotification.Name("ExportAsGIF"), object: nil)
        }
        .keyboardShortcut("g", modifiers: [.command, .shift])
        .accessibilityIdentifier("menu.file.export_gif")

        Button(
          String(
            localized: "menu.file.export_transcript", defaultValue: "Export Transcript (PDF)...")
        ) {
          NotificationCenter.default.post(
            name: NSNotification.Name("ExportTranscriptPDF"), object: nil)
        }
        .keyboardShortcut("t", modifiers: [.command, .option])
        .accessibilityIdentifier("menu.file.export_transcript")

        Divider()

        Button(
          String(localized: "menu.file.generate_thumbnail", defaultValue: "Generate AI Thumbnail")
        ) {
          NotificationCenter.default.post(
            name: NSNotification.Name("GenerateThumbnail"), object: nil)
        }
        .keyboardShortcut("t", modifiers: [.command])
        .accessibilityIdentifier("menu.file.generate_thumbnail")

        Button(
          String(localized: "menu.file.generate_voiceover", defaultValue: "Generate Voiceover")
        ) {
          NotificationCenter.default.post(
            name: NSNotification.Name("GenerateVoiceover"), object: nil)
        }
        .accessibilityIdentifier("menu.file.generate_voiceover")

        Button(
          String(localized: "menu.file.create_shorts", defaultValue: "Create Shorts...")
        ) {
          NotificationCenter.default.post(
            name: NSNotification.Name("ShowRepurposingSheet"), object: nil)
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
            name: NSNotification.Name("ShowKeyboardShortcuts"), object: nil)
        }
        .keyboardShortcut("?", modifiers: [.command])
        .accessibilityIdentifier("menu.help.shortcuts")

        Button(String(localized: "menu.help.sane_video_help", defaultValue: "SaneVideo Help")) {
          if let url = URL(string: "https://www.sanevideo.app/help") {
            NSWorkspace.shared.open(url)
          }
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

// MARK: - App Delegate for Menu Bar

@MainActor
class AppDelegate: NSObject, NSApplicationDelegate {
  var statusItem: NSStatusItem?

  deinit {
    NotificationCenter.default.removeObserver(self)
  }

  func applicationDidFinishLaunching(_: Notification) {
    setupMenuBar()

    // Initialize global hotkey manager
    ServiceContainer.shared.globalHotkeyManager.start()

    // Initialize LogManager to capture early logs
    _ = ServiceContainer.shared.logManager

    // Initialize MetricKit crash and performance monitoring
    ServiceContainer.shared.crashReporter.start()

    // Initialize memory pressure handling
    Task { @MainActor in
      _ = ServiceContainer.shared.memoryManager  // Initialize to start memory pressure observer
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

  private func setupMenuBar() {
    statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)

    if statusItem?.button != nil {
      Task { @MainActor in
        self.updateMenuBarIcon(isRecording: false)
      }
    }

    let menu = NSMenu()
    menu.addItem(
      NSMenuItem(title: "New Recording", action: #selector(newRecording), keyEquivalent: ""))
    menu.addItem(NSMenuItem(title: "Show Window", action: #selector(showWindow), keyEquivalent: ""))
    menu.addItem(NSMenuItem.separator())
    menu.addItem(
      NSMenuItem(
        title: "Quit SaneVideo",
        action: #selector(NSApplication.terminate(_:)),
        keyEquivalent: "q"
      ))

    statusItem?.menu = menu

    // Observe recording state
    NotificationCenter.default.addObserver(
      self,
      selector: #selector(recordingStateChanged),
      name: NSNotification.Name("RecordingStateChanged"),
      object: nil
    )
  }

  @objc private func recordingStateChanged(_ notification: Notification) {
    if let isRecording = notification.userInfo?["isRecording"] as? Bool {
      Task { @MainActor in
        self.updateMenuBarIcon(isRecording: isRecording)
      }
    }
  }

  @MainActor
  private func updateMenuBarIcon(isRecording: Bool) {
    guard let button = statusItem?.button else { return }

    if isRecording {
      // Red dot icon (static, no pulsing)
      let image = NSImage(
        systemSymbolName: "record.circle.fill", accessibilityDescription: "Recording")
      image?.isTemplate = false  // Keep original color (red)
      button.image = image
      button.imagePosition = .imageOnly

      // Remove any existing animation
      button.layer?.removeAnimation(forKey: "pulse")
    } else {
      // Black camera icon
      let image = NSImage(systemSymbolName: "video.fill", accessibilityDescription: "SaneVideo")
      image?.isTemplate = true
      button.image = image
      button.layer?.removeAnimation(forKey: "pulse")
    }
  }

  @MainActor
  @objc private func newRecording() {
    ServiceContainer.shared.appState.startNewRecording()
    showWindow()
  }

  @MainActor
  @objc private func showWindow() {
    NSApp.activate(ignoringOtherApps: true)
    NSApp.windows.first?.makeKeyAndOrderFront(nil)
  }

  private func setupGlobalHotkey() {
    // Global hotkey handling is now centralized in GlobalHotkeyManager
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
        try? await Task.sleep(nanoseconds: 500_000_000)  // 0.5 second for cleanup
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
