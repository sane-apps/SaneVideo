//
//  SaneVideoApp.swift
//  SaneVideo
//
//  Created by Stephan Joseph on 11/23/25.
//

import AppKit
import SwiftUI

@main
struct SaneVideoApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    @State private var appState = ServiceContainer.shared.appState
    @State private var prefs = ServiceContainer.shared.userPreferences

    var body: some Scene {
        WindowGroup {
            MainContentView()
                .environment(appState)
                .environment(ServiceContainer.shared.errorPresenter)
                .preferredColorScheme(prefs.appTheme == .system ? nil : (prefs.appTheme == .dark ? .dark : .light))
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
            CommandGroup(replacing: .newItem) {
                Button(String(localized: "menu.file.new_recording", defaultValue: "New Recording")) {
                    appState.startNewRecording()
                }
                .keyboardShortcut("n", modifiers: [.command])
                .accessibilityIdentifier("menu.file.new_recording")
            }

            CommandGroup(after: .importExport) {
                Button(String(localized: "menu.file.open_project", defaultValue: "Open Project...")) {
                    NotificationCenter.default.post(name: NSNotification.Name("ShowProjectBrowser"), object: nil)
                }
                .keyboardShortcut("o", modifiers: [.command])
                .accessibilityIdentifier("menu.file.open_project")
                
                Button(String(localized: "menu.file.import_video", defaultValue: "Import Video...")) {
                    appState.importVideo()
                }
                .keyboardShortcut("i", modifiers: [.command])
                .accessibilityIdentifier("menu.file.import_video")
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
                    NotificationCenter.default.post(name: NSNotification.Name("ShowRenameProjectDialog"), object: nil)
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
                
                Button(String(localized: "menu.file.export_transcript", defaultValue: "Export Transcript (PDF)...")) {
                    NotificationCenter.default.post(name: NSNotification.Name("ExportTranscriptPDF"), object: nil)
                }
                .accessibilityIdentifier("menu.file.export_transcript")
                
                Divider()
                
                Button(String(localized: "menu.file.generate_thumbnail", defaultValue: "Generate AI Thumbnail")) {
                    NotificationCenter.default.post(name: NSNotification.Name("GenerateThumbnail"), object: nil)
                }
                .accessibilityIdentifier("menu.file.generate_thumbnail")
                
                Button(String(localized: "menu.file.generate_voiceover", defaultValue: "Generate Voiceover")) {
                    NotificationCenter.default.post(name: NSNotification.Name("GenerateVoiceover"), object: nil)
                }
                .accessibilityIdentifier("menu.file.generate_voiceover")
                
                Divider()
                
                Button(String(localized: "menu.file.share", defaultValue: "Share...")) {
                    NotificationCenter.default.post(name: NSNotification.Name("ShareProject"), object: nil)
                }
                .keyboardShortcut("s", modifiers: [.command, .shift])
                .accessibilityIdentifier("menu.file.share")
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
    // Removed eager initialization: let hotkeyManager = ServiceContainer.shared.globalHotkeyManager

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
            _ = ServiceContainer.shared.memoryManager // Initialize to start memory pressure observer
        }

        // NOTE: Apple Speech Recognition is used for captions (no model download needed)
        // Camera is NOT started on app launch for privacy.
        // It will start automatically when user clicks Record or toggles Camera on.
    }

    private func setupMenuBar() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)

        if statusItem?.button != nil {
            Task { @MainActor in
                self.updateMenuBarIcon(isRecording: false)
            }
        }

        let menu = NSMenu()
        menu.addItem(NSMenuItem(title: "New Recording", action: #selector(newRecording), keyEquivalent: ""))
        menu.addItem(NSMenuItem(title: "Show Window", action: #selector(showWindow), keyEquivalent: ""))
        menu.addItem(NSMenuItem.separator())
        menu.addItem(NSMenuItem(
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
            let image = NSImage(systemSymbolName: "record.circle.fill", accessibilityDescription: "Recording")
            image?.isTemplate = false // Keep original color (red)
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
        if ServiceContainer.shared.appState.isRecording {
            // If recording, try to stop safely first
            ServiceContainer.shared.appState.recordingState.stopRecording { _ in
                // Give it a moment to finish writing
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                    sender.reply(toApplicationShouldTerminate: true)
                }
            }
            return .terminateLater
        }
        return .terminateNow
    }
}
