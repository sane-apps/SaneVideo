//
//  MainContentView.swift
//  SaneVideo
//
//  Created by SaneVideo Refactor
//

import AVKit
import Combine
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
  // Note: selectedClipIds moved to AppState for global access

  @AppStorage("hasCompletedOnboarding") private var hasCompletedOnboarding = false

  private var isTesting: Bool {
    ProcessInfo.processInfo.arguments.contains("-uitesting")
      || ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil
  }

  var body: some View {
    @Bindable var appState = appState
    @Bindable var errorPresenter = errorPresenter
    
    return mainContent
      .background(.regularMaterial)
      .overlay(alignment: .top) {
        MagicOverlayView()
      }
      // Global Keyboard Shortcuts
      .background {
        Button("") {
          showLogs.toggle()
        }
        .keyboardShortcut("l", modifiers: [.command])
        .opacity(0)
      }
      .onAppear {
        // Connect SwiftUI's UndoManager to ProjectState
        appState.projectState.undoManager = undoManager
      }
      .onChange(of: undoManager) { _, newValue in
        appState.projectState.undoManager = newValue
      }
      // State Synchronization
      .onChange(of: appState.recentlyAddedClip) {
        if let clip = appState.recentlyAddedClip {
          selectedClip = clip
        }
      }
      // OPTIMIZED: Unified state change pipeline (replaces multiple onChange handlers)
      .withUnifiedStateChanges()
      .sheet(item: $errorPresenter.activeError) { error in
        ErrorDisplayView(
          error: error,
          onDismiss: { errorPresenter.dismiss() },
          onRetry: error.recoverySuggestions.isEmpty ? nil : {
            errorPresenter.dismiss()
            // Retry logic would be implemented per error type
          }
        )
        .frame(width: 500, height: 400)
      }
      // Refactored Modifiers
      .withFileDropHandling(isTargeted: $isDraggingFile)
      .withGlobalSheets()
      .withToastOverlay()
      // Consolidated Sheets for UI Test Reliability
      .sheet(isPresented: $appState.showExportSheet) {
        ExportView()
          .onAppear {
            NSLog("🎨 MainContentView: Export sheet appeared")
          }
      }
      .sheet(isPresented: $showLogs) {
        LogView()
      }
      // Menu command handlers for export features
      .onReceive(NotificationCenter.default.publisher(for: NSNotification.Name("ExportAsGIF"))) {
        _ in
        showGIFSheet = true
      }
      .sheet(isPresented: $showGIFSheet) {
        if let project = appState.projectState.currentProject,
          let firstClip = project.timeline.tracks.first?.clips.first
        {
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
        showTranscriptSheet = true
      }
      .sheet(isPresented: $showTranscriptSheet) {
        if let project = appState.projectState.currentProject {
          let captions = project.timeline.tracks
            .flatMap { $0.clips }
            .flatMap { $0.captions }
          TranscriptExportSheet(
            captions: captions,
            projectName: project.name
          )
        }
      }
      .onReceive(
        NotificationCenter.default.publisher(for: NSNotification.Name("GenerateVoiceover"))
      ) { _ in
        showVoiceoverSheet = true
      }
      .sheet(isPresented: $showVoiceoverSheet) {
        if let project = appState.projectState.currentProject {
          let captions = project.timeline.tracks
            .flatMap { $0.clips }
            .flatMap { $0.captions }
          VoiceoverSettingsSheet(
            captions: captions,
            projectName: project.name,
            onGenerate: { url in
              ServiceContainer.shared.toastManager.show(
                String(localized: "toast.voiceover_saved", defaultValue: "✅ Voiceover saved!"))
              NSWorkspace.shared.open(url)
            }
          )
        }
      }
      .onReceive(
        NotificationCenter.default.publisher(for: NSNotification.Name("GenerateThumbnail"))
      ) { _ in
        showThumbnailSheet = true
      }
      .sheet(isPresented: $showThumbnailSheet) {
        if let project = appState.projectState.currentProject,
          let firstClip = project.timeline.tracks.first?.clips.first
        {
          ThumbnailPickerSheet(
            videoURL: firstClip.url,
            projectName: project.name,
            onSelect: { image in
              NSPasteboard.general.clearContents()
              NSPasteboard.general.writeObjects([image])
              ServiceContainer.shared.toastManager.show(
                String(localized: "toast.thumbnail_copied", defaultValue: "✅ Thumbnail copied!"))
            }
          )
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
            ))
      } else {
        EditorLayoutView(
          selectedClip: $selectedClip,
          selectedClipIds: $appState.selectedClipIds
        )
        .transition(
          .asymmetric(
            insertion: .move(edge: .trailing).combined(with: .opacity),
            removal: .move(edge: .leading).combined(with: .opacity)
          ))
      }
    }
    .navigationTitle("")
    .animation(.spring(response: 0.4, dampingFraction: 0.8), value: appState.appMode)
    .toolbar {
      ToolbarItem(placement: .navigation) {
        HStack(spacing: 12) {
          // 1. Branding
          HStack(spacing: 0) {
            Text("SANE")
              .font(.system(size: 15, weight: .bold))
              .tracking(1.5)
            Text("VIDEO")
              .font(.system(size: 15, weight: .thin))
              .tracking(1.5)
          }
          .foregroundStyle(.primary)

          // 2. Project Name (Moved from Center)
          if appState.appMode == .editing {
            Divider().frame(height: 16)

            Button(
              action: {
                NotificationCenter.default.post(
                  name: NSNotification.Name("ShowRenameProjectDialog"), object: nil)
              },
              label: {
                HStack(spacing: 4) {
                  Text(appState.projectState.currentProject?.name ?? "Untitled Project")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(.secondary)
                  Image(systemName: "pencil")
                    .font(.system(size: 10))
                    .foregroundStyle(.tertiary)
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
        // Center is now dedicated to the main Mode Switcher
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
        .tint(Theme.Colors.accent)  // Force App Theme Color
        .controlSize(.regular)
        .hoverScale(1.05)
        .animation(.smoothUI, value: appState.appMode)
        .help("Toggle Record/Edit Mode (Cmd+M)")
        .padding(.vertical, 4)
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
              action: { undoManager?.undo() },
              label: {
                Label("Undo", systemImage: "arrow.uturn.backward")
              }
            )
            .disabled(!(undoManager?.canUndo ?? false))
            .keyboardShortcut("z", modifiers: [.command])

            Button(
              action: { undoManager?.redo() },
              label: {
                Label("Redo", systemImage: "arrow.uturn.forward")
              }
            )
            .disabled(!(undoManager?.canRedo ?? false))
            .keyboardShortcut("z", modifiers: [.command, .shift])
          }
        }
      }

      ToolbarItem(placement: .primaryAction) {
        if appState.appMode == .editing {
          HStack(spacing: 8) {
            // MAGIC QUICK BUTTON (Global)
            Button(
              action: {
                NotificationCenter.default.post(
                  name: NSNotification.Name("TriggerMagicFix"), object: nil)
              },
              label: {
                Label("Magic Fix", systemImage: "sparkles")
              }
            )
            .buttonStyle(.borderedProminent)
            .tint(Theme.Colors.accent)  // Force App Theme Color
            .hoverScale(1.05)
            .help("Auto-Fix Project (Cmd+Shift+M)")
            .keyboardShortcut("m", modifiers: [.command, .shift])
            .enhancedAccessibility(
                label: "Magic Fix",
                hint: "Automatically removes silence, filler words, and enhances your video",
                traits: .isButton
            )
            .keyboardShortcutHint("⌘⇧M")

            Divider()
              .frame(height: 16)

            // SHARE/EXPORT
            Button(
              action: { appState.showExportSheet = true },
              label: {
                Label("Share", systemImage: "square.and.arrow.up")
              }
            )
            .buttonStyle(.borderedProminent)
            .tint(Theme.Colors.accent)  // Force App Theme Color
            .hoverScale(1.05)
            .help("Export Gallery (Cmd+E)")
            .keyboardShortcut("e", modifiers: [.command])
            .enhancedAccessibility(
                label: "Share",
                hint: "Export your video project",
                traits: .isButton
            )
            .keyboardShortcutHint("⌘E")
          }
        }
      }
    }
  }
}
