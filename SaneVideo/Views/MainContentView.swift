import AVKit
import Combine
import SaneUI
import SwiftUI
import UniformTypeIdentifiers

struct MainContentView: View {
    @Environment(AppState.self) var appState
    @Environment(ErrorPresenter.self) var errorPresenter
    @Environment(\.undoManager) var undoManager
    @State private var selectedClip: VideoClip?
    @State private var showVoiceoverSheet = false
    @State private var showThumbnailSheet = false
    @State private var showGIFSheet = false
    @State private var showTranscriptSheet = false
    @State private var showLogs = false
    @State private var isDraggingFile = false

    private var isTesting: Bool {
        ProcessInfo.processInfo.arguments.contains("-uitesting")
            || ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil
    }

    var body: some View {
        @Bindable var appState = appState
        @Bindable var errorPresenter = errorPresenter

        return
            mainContent
                .background(SaneVideoAmbientBackground())
                .overlay(alignment: .top) {
                    MagicOverlayView()
                }
                .overlay(alignment: .bottomTrailing) {
                    SaneStickyDonateButton(url: OpenSourceRelease.donationURL)
                        .padding(16)
                }
                .overlay {
                    if appState.showQuickAccessOverlay,
                       let url = appState.quickAccessRecordingURL {
                        QuickAccessOverlay(
                            recordingURL: url,
                            thumbnail: appState.quickAccessThumbnail,
                            onEdit: {
                                appState.handleQuickAccessEdit()
                            },
                            onSave: {
                                appState.handleQuickAccessSave()
                            },
                            onShare: {
                                appState.handleQuickAccessShare()
                            },
                            onDismiss: {
                                appState.dismissQuickAccessOverlay()
                            }
                        )
                        .zIndex(1000)
                    }
                }
                .background {
                    Button("") {
                        appState.performProjectCommand { showLogs.toggle() }
                    }
                    .disabled(!appState.projectCommandsEnabled)
                    .keyboardShortcut("l", modifiers: [.command])
                    .opacity(0)
                }
                .onAppear {
                    appState.projectState.undoManager = undoManager
                }
                .onChange(of: undoManager) { _, newValue in
                    appState.projectState.undoManager = newValue
                }
                .onChange(of: appState.recentlyAddedClip) {
                    if let clip = appState.recentlyAddedClip {
                        selectedClip = clip
                    }
                }
                // Sync selectedClip with selectedClipIds (auto-selection support)
                .onChange(of: appState.selectedClipIds) { _, newIds in
                    if let firstId = newIds.first,
                       let project = appState.projectState.currentProject {
                        let clip = project.timeline.tracks
                            .flatMap(\.clips)
                            .first { $0.id == firstId }
                        if clip != selectedClip {
                            selectedClip = clip
                        }
                    } else if newIds.isEmpty, selectedClip != nil {
                        selectedClip = nil
                    }
                }
                .withUnifiedStateChanges()
                .sheet(item: $errorPresenter.activeError) { error in
                    ErrorDisplayView(
                        error: error,
                        onDismiss: { errorPresenter.dismiss() },
                        onRetry: error.recoverySuggestions.isEmpty
                            ? nil
                            : {
                                errorPresenter.dismiss()
                                // Retry only dismisses for now; no error type has its own retry yet.
                            }
                    )
                    .frame(width: 500, height: 400)
                }
                .withFileDropHandling(isTargeted: $isDraggingFile)
                .withGlobalSheets()
                .withToastOverlay()
                // Sheets are attached here together to keep UI tests reliable.
                .sheet(isPresented: $appState.showTeleprompterScriptSheet) {
                    TeleprompterScriptSheet()
                }
                .sheet(isPresented: $appState.showExportSheet) {
                    ExportView()
                        .onAppear {
                            NSLog("🎨 MainContentView: Export sheet appeared")
                        }
                }
                .sheet(isPresented: $showLogs) {
                    LogView()
                }
                .onReceive(NotificationCenter.default.publisher(for: NSNotification.Name("ExportAsGIF"))) { _ in
                    appState.performProjectCommand {
                        showGIFSheet = true
                    }
                }
                .sheet(isPresented: $showGIFSheet) {
                    if let project = appState.projectState.currentProject,
                       let firstClip = project.timeline.tracks.first?.clips.first {
                        GIFExportSheet(
                            videoURL: firstClip.url,
                            projectName: project.name,
                            clipDuration: CMTimeGetSeconds(firstClip.effectiveDuration)
                        )
                    }
                }
                .onReceive(
                    NotificationCenter.default.publisher(for: NSNotification.Name("ExportTranscriptPDF"))
                ) { _ in
                    appState.performProjectCommand {
                        showTranscriptSheet = true
                    }
                }
                .sheet(isPresented: $showTranscriptSheet) {
                    if let project = appState.projectState.currentProject {
                        TranscriptExportSheet(
                            captions: project.timelineCaptions,
                            projectName: project.name
                        )
                    }
                }
                .onReceive(
                    NotificationCenter.default.publisher(for: NSNotification.Name("GenerateVoiceover"))
                ) { _ in
                    appState.performProjectCommand {
                        showVoiceoverSheet = true
                    }
                }
                .sheet(isPresented: $showVoiceoverSheet) {
                    if let project = appState.projectState.currentProject {
                        VoiceoverSettingsSheet(
                            captions: project.timelineCaptions,
                            projectName: project.name,
                            onGenerate: { url in
                                ServiceContainer.shared.toastManager.show(
                                    String(localized: "toast.voiceover_saved", defaultValue: "✅ Voiceover saved!")
                                )
                                NSWorkspace.shared.open(url)
                            }
                        )
                        .onAppear {
                            AppLogger.uiLog.info("🎨 MainContentView: Voiceover sheet appeared")
                        }
                    }
                }
                .onReceive(
                    NotificationCenter.default.publisher(for: NSNotification.Name("GenerateThumbnail"))
                ) { _ in
                    appState.performProjectCommand {
                        showThumbnailSheet = true
                    }
                }
                .sheet(isPresented: $showThumbnailSheet) {
                    if let project = appState.projectState.currentProject,
                       let firstClip = project.timeline.tracks.first?.clips.first {
                        ThumbnailPickerSheet(
                            videoURL: firstClip.url,
                            projectName: project.name,
                            onSelect: { image in
                                NSPasteboard.general.clearContents()
                                NSPasteboard.general.writeObjects([image])
                                ServiceContainer.shared.toastManager.show(
                                    String(localized: "toast.thumbnail_copied", defaultValue: "✅ Thumbnail copied!")
                                )
                            }
                        )
                        .onAppear {
                            AppLogger.uiLog.info("🎨 MainContentView: Thumbnail sheet appeared")
                        }
                    }
                }
                .tooltipOverlay()
                .overlay {
                    if isDraggingFile {
                        ZStack {
                            Color.black.opacity(0.4)
                                .blur(radius: 20)

                            VStack(spacing: 20) {
                                Image(systemName: "plus.square.dashed")
                                    .font(.system(size: 80, weight: .light))
                                    .foregroundStyle(Theme.Colors.accentGradient)

                                Text("Drop to Import Media")
                                    .font(.system(size: 24, weight: .bold))
                                    .foregroundColor(.white)
                            }
                        }
                        .ignoresSafeArea()
                        .transition(.opacity.combined(with: .scale(scale: 1.1)))
                        .zIndex(1000)
                    }
                }
                .animation(.spring(response: 0.3, dampingFraction: 0.7), value: isDraggingFile)
                .accessibilityIdentifier(AccessibilityIdentifiers.mainWindow)
    }

    var mainContent: some View {
        @Bindable var appState = appState
        return ZStack(alignment: .top) {
            if appState.appMode == .recording {
                RecordingModeView()
                    .transition(
                        .asymmetric(
                            insertion: .move(edge: .leading).combined(with: .opacity),
                            removal: .move(edge: .trailing).combined(with: .opacity)
                        )
                    )
            } else {
                EditorLayoutView(
                    selectedClip: $selectedClip,
                    selectedClipIds: $appState.selectedClipIds
                )
                .transition(
                    .asymmetric(
                        insertion: .move(edge: .trailing).combined(with: .opacity),
                        removal: .move(edge: .leading).combined(with: .opacity)
                    )
                )
            }
        }
        .navigationTitle("")
        .animation(.spring(response: 0.4, dampingFraction: 0.8), value: appState.appMode)
        .toolbar {
            ToolbarItem(placement: .navigation) {
                HStack(spacing: 12) {
                    HStack(spacing: 0) {
                        Text("SANE")
                            .font(.system(size: 15, weight: .bold))
                            .tracking(1.5)
                        Text("VIDEO")
                            .font(.system(size: 15, weight: .thin))
                            .tracking(1.5)
                    }
                    .foregroundStyle(.primary)

                    if appState.appMode == .editing {
                        Divider().frame(height: 16)

                        Button(
                            action: {
                                NotificationCenter.default.post(
                                    name: NSNotification.Name("ShowRenameProjectDialog"), object: nil
                                )
                            },
                            label: {
                                HStack(spacing: 4) {
                                    Text(appState.projectState.currentProject?.name ?? "Untitled Project")
                                        .font(.system(size: Theme.Typography.fontSizeSM, weight: .semibold))
                                        .foregroundStyle(Theme.Colors.textPrimary)
                                    Image(systemName: "pencil")
                                        .font(.system(size: Theme.Typography.fontSizeXS, weight: .medium))
                                        .foregroundStyle(Theme.Colors.textSecondary)
                                }
                            }
                        )
                        .buttonStyle(.plain)
                        .help("Rename Project")
                    }
                }
                .padding(.leading, 8)
            }

            ToolbarItem(placement: .principal) {
                Button(
                    action: {
                        withAnimation(.smoothUI) {
                            appState.appMode = (appState.appMode == .recording ? .editing : .recording)
                        }
                    },
                    label: {
                        Label(
                            appState.appMode == .recording ? "Editor" : "Record",
                            systemImage: appState.appMode == .recording ? "scissors" : "record.circle"
                        )
                        .font(.system(size: 14, weight: .bold))
                        .imageScale(.large)
                    }
                )
                .buttonStyle(.borderedProminent)
                .controlSize(.regular)
                .hoverScale(1.05)
                .pressScale()
                .simultaneousGesture(
                    TapGesture().onEnded {
                        ServiceContainer.shared.hapticsManager.impact()
                    }
                )
                .animation(.smoothUI, value: appState.appMode)
                .help("Toggle Record/Edit Mode (Cmd+M)")
                .padding(.vertical, 4)
                .accessibilityIdentifier(AccessibilityIdentifiers.modeSwitcher)
                .enhancedAccessibility(
                    label: appState.appMode == .recording ? "Switch to Editor" : "Switch to Record",
                    hint: "Toggle between recording and editing modes",
                    traits: .isButton
                )
                .keyboardShortcutHint("⌘M")
            }

            ToolbarItem(placement: .automatic) {
                if appState.appMode == .editing {
                    ControlGroup {
                        Button(
                            action: { appState.performProjectCommand { undoManager?.undo() } },
                            label: {
                                Label("Undo", systemImage: "arrow.uturn.backward")
                            }
                        )
                        .disabled(!appState.projectCommandsEnabled || !(undoManager?.canUndo ?? false))
                        .keyboardShortcut("z", modifiers: [.command])

                        Button(
                            action: { appState.performProjectCommand { undoManager?.redo() } },
                            label: {
                                Label("Redo", systemImage: "arrow.uturn.forward")
                            }
                        )
                        .disabled(!appState.projectCommandsEnabled || !(undoManager?.canRedo ?? false))
                        .keyboardShortcut("z", modifiers: [.command, .shift])
                    }
                }
            }

            ToolbarItem(placement: .primaryAction) {
                if appState.appMode == .editing {
                    // Export is the primary next step; sharing remains available after a file exists.
                    Button(
                        action: { appState.performProjectCommand { appState.showExportSheet = true } },
                        label: {
                            Label("Export", systemImage: "square.and.arrow.up")
                        }
                    )
                    .buttonStyle(.borderedProminent)
                    .hoverScale(1.05)
                    .disabled(!appState.projectCommandsEnabled || (appState.currentProject?.timeline.tracks.allSatisfy(\.clips.isEmpty) ?? true))
                    .help((appState.currentProject?.timeline.tracks.allSatisfy(\.clips.isEmpty) ?? true) ? "Add clips to timeline first" : "Export (Cmd+E)")
                    .keyboardShortcut("e", modifiers: [.command])
                    .accessibilityIdentifier(AccessibilityIdentifiers.exportButton)
                    .enhancedAccessibility(
                        label: "Export",
                        hint: (appState.currentProject?.timeline.tracks.allSatisfy(\.clips.isEmpty) ?? true) ? "Add clips to timeline first" : "Export your video project",
                        traits: .isButton
                    )
                    .keyboardShortcutHint("⌘E")
                }
            }
        }
    }
}
