import SwiftUI

struct GlobalSheetModifier: ViewModifier {
    @Environment(AppState.self) var appState

    @State private var showLogs = false
    @State private var showShortcuts = false
    @State private var repurposingClip: VideoClip?

    @State private var showingRenameAlert = false
    @State private var newProjectName = ""

    func body(content: Content) -> some View {
        @Bindable var appState = appState
        return content
            .sheet(isPresented: $appState.showingImportPicker) {
                FileImporterView()
            }
            .sheet(isPresented: $showShortcuts) {
                KeyboardShortcutsSheet()
            }
            .sheet(item: $repurposingClip) { clip in
                RepurposingSheet(sourceClip: clip)
                    .onAppear {
                        AppLogger.uiLog.info("🎨 GlobalSheetModifier: Repurposing (Shorts) sheet appeared")
                    }
            }

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
            // Hidden button that provides the logs shortcut.
            .background {
                Button("") { appState.performProjectCommand { showLogs = true } }
                    .disabled(!appState.projectCommandsEnabled)
                    .keyboardShortcut("l", modifiers: .command)
                    .opacity(0)
                    .accessibilityIdentifier("global.show_logs")
            }
            .onReceive(NotificationCenter.default.publisher(for: NSNotification.Name("ShowRenameProjectDialog"))) { _ in
                appState.performProjectCommand {
                    if let currentName = appState.projectState.currentProject?.name {
                        newProjectName = currentName
                        showingRenameAlert = true
                    }
                }
            }
            .onReceive(NotificationCenter.default.publisher(for: NSNotification.Name("ShowKeyboardShortcuts"))) { _ in
                appState.performProjectCommand {
                    showShortcuts = true
                }
            }
            .onReceive(NotificationCenter.default.publisher(for: NSNotification.Name("ShowRepurposingSheet"))) { notification in
                appState.performProjectCommand {
                    if let clip = notification.object as? VideoClip {
                        repurposingClip = clip
                    } else if let project = appState.currentProject {
                        // Shorts come from the main recording: the longest clip.
                        repurposingClip = project.timeline.tracks.flatMap(\.clips)
                            .max { $0.effectiveDuration.seconds < $1.effectiveDuration.seconds }
                    }
                }
            }
            .onReceive(NotificationCenter.default.publisher(for: NSNotification.Name("ShareProject"))) { _ in
                appState.performProjectCommand {
                    if let project = appState.projectState.currentProject {
                        let url = appState.projectState.getProjectFileURL(project)
                        ServiceContainer.shared.shareLinkService.shareFile(at: url, from: nil)
                    }
                }
            }
            .onReceive(NotificationCenter.default.publisher(for: NSNotification.Name("RenameProject"))) { notification in
                appState.performProjectCommand {
                    if let projectId = notification.object as? UUID,
                       let project = appState.projectState.projects.first(where: { $0.id == projectId }) {
                        // Switch to this project first, then show rename dialog
                        appState.projectState.openProject(project)
                        newProjectName = project.name
                        showingRenameAlert = true
                    }
                }
            }
            .onReceive(NotificationCenter.default.publisher(for: NSNotification.Name("DuplicateProject"))) { notification in
                appState.performProjectCommand {
                    if let projectId = notification.object as? UUID,
                       let project = appState.projectState.projects.first(where: { $0.id == projectId }) {
                        appState.projectState.duplicateProject(project)
                        ServiceContainer.shared.toastManager.show("Project duplicated")
                    }
                }
            }
            .onReceive(NotificationCenter.default.publisher(for: NSNotification.Name("DeleteProject"))) { notification in
                appState.performProjectCommand {
                    if let projectId = notification.object as? UUID,
                       let project = appState.projectState.projects.first(where: { $0.id == projectId }) {
                        appState.projectState.deleteProject(project)
                        ServiceContainer.shared.toastManager.show("Project deleted", type: .info)
                    }
                }
            }
    }
}

extension View {
    func withGlobalSheets() -> some View {
        modifier(GlobalSheetModifier())
    }
}
