//
//  GlobalSheetModifier.swift
//  SaneVideo
//
//  Created by SaneVideo Refactor
//

import SwiftUI

struct GlobalSheetModifier: ViewModifier {
    @Environment(AppState.self) var appState

    // Local state for sheets
    @State private var showLogs = false
    @State private var showOnboarding = !UserDefaults.standard.bool(forKey: "hasCompletedOnboarding")
    @State private var showingProjectBrowser = false
    @State private var showShortcuts = false
    @State private var showTemplateBrowser = false
    @State private var showRepurposing = false
    @State private var repurposingClip: VideoClip?

    // Rename Alert State
    @State private var showingRenameAlert = false
    @State private var newProjectName = ""

    private var isTesting: Bool {
        ProcessInfo.processInfo.arguments.contains("-uitesting") ||
        ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil
    }

    func body(content: Content) -> some View {
        @Bindable var appState = appState
        return content
            // 1. File Import
            .sheet(isPresented: $appState.showingImportPicker) {
                FileImporterView()
            }
            // 3. Onboarding
            .sheet(isPresented: .init(
                get: { showOnboarding && !isTesting },
                set: { showOnboarding = $0 }
            )) {
                OnboardingView(isPresented: $showOnboarding)
            }
            .sheet(isPresented: $showingProjectBrowser) {
                ProjectBrowserView()
            }
            // 4. Keyboard Shortcuts
            .sheet(isPresented: $showShortcuts) {
                KeyboardShortcutsSheet()
            }
            // 5. Template Browser
            .sheet(isPresented: $showTemplateBrowser) {
                TemplateBrowserSheet()
            }
            // 6. Repurposing Sheet
            .sheet(isPresented: $showRepurposing) {
                RepurposingSheet(sourceClip: repurposingClip)
            }

            // 6. Rename Project Alert
            .alert(String(localized: "global.rename.title", defaultValue: "Rename Project"), isPresented: $showingRenameAlert) {
                TextField(String(localized: "global.rename.placeholder", defaultValue: "Project Name"), text: $newProjectName)
                    .accessibilityIdentifier("global.rename_field")
                Button(String(localized: "global.action.rename", defaultValue: "Rename")) {
                    appState.projectState.renameProject(newProjectName)
                }
                .accessibilityIdentifier("global.rename_submit")
                Button(String(localized: "global.action.cancel", defaultValue: "Cancel"), role: .cancel) {}
            } message: {
                Text(String(localized: "global.rename.message", defaultValue: "Enter a new name for this project."))
            }
            // 7. Hidden Shortcut for Logs
            .background {
                Button("") { showLogs = true }
                    .keyboardShortcut("l", modifiers: .command)
                    .opacity(0)
                    .accessibilityIdentifier("global.show_logs")
            }
            // 8. Event Listeners
            .onReceive(NotificationCenter.default.publisher(for: NSNotification.Name("ShowRenameProjectDialog"))) { _ in
                if let currentName = appState.projectState.currentProject?.name {
                    newProjectName = currentName
                    showingRenameAlert = true
                }
            }
            .onReceive(NotificationCenter.default.publisher(for: NSNotification.Name("ShowProjectBrowser"))) { _ in
                showingProjectBrowser = true
            }
            .onReceive(NotificationCenter.default.publisher(for: NSNotification.Name("ShowKeyboardShortcuts"))) { _ in
                showShortcuts = true
            }
            .onReceive(NotificationCenter.default.publisher(for: NSNotification.Name("ShowTemplateBrowser"))) { _ in
                showTemplateBrowser = true
            }
            .onReceive(NotificationCenter.default.publisher(for: NSNotification.Name("ShowRepurposingSheet"))) { notification in
                if let clip = notification.object as? VideoClip {
                    repurposingClip = clip
                } else if let project = appState.currentProject,
                          let firstClip = project.timeline.tracks.flatMap({ $0.clips }).first {
                    repurposingClip = firstClip
                }
                showRepurposing = true
            }
            // 9. Share Project
            .onReceive(NotificationCenter.default.publisher(for: NSNotification.Name("ShareProject"))) { _ in
                if let project = appState.projectState.currentProject {
                    let url = appState.projectState.getProjectFileURL(project)
                    // Use standard system share sheet for the project file
                    ServiceContainer.shared.shareLinkService.shareFile(at: url, from: nil)
                }
            }
    }
}

extension View {
    func withGlobalSheets() -> some View {
        modifier(GlobalSheetModifier())
    }
}
