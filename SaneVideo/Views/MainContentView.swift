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
    // Note: selectedClipIds moved to AppState for global access

    @AppStorage("hasCompletedOnboarding") private var hasCompletedOnboarding = false

    private var isTesting: Bool {
        ProcessInfo.processInfo.arguments.contains("-uitesting") ||
        ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil
    }

    var body: some View {
        @Bindable var appState = appState
        @Bindable var errorPresenter = errorPresenter
        return mainContent
            .background(Color(NSColor.windowBackgroundColor))
            .overlay(alignment: .top) {
                if ThermalManager.shared.isThermalPressureHigh {
                    VStack {
                        HStack {
                            Image(systemName: "thermometer.sun.fill")
                                .foregroundColor(.orange)
                            Text(ThermalManager.shared.performanceLevel == .emergency ? 
                                 String(localized: "thermal.emergency", defaultValue: "System Overheating: Performance reduced") :
                                 String(localized: "thermal.throttled", defaultValue: "System Hot: Optimizing performance"))
                                .font(.caption)
                                .fontWeight(.medium)
                            Spacer()
                        }
                        .padding(8)
                        .background(Color.black.opacity(0.8))
                        .cornerRadius(8)
                        .padding()
                        Spacer()
                    }
                    .transition(.move(edge: .top).combined(with: .opacity))
                    .accessibilityIdentifier("thermal.status.overlay")
                }
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
            // CONSOLIDATED: Single handler for project/timeline changes
            // Using a computed trigger to prevent double-firing
            .onChange(of: appState.projectState.currentProject?.id) {
                // Project identity changed - reset and load
                appState.playbackState.reset()
                if let project = appState.projectState.currentProject {
                    appState.playbackState.loadProject(project, forceReload: true)
                }
            }
            .onChange(of: appState.projectState.currentProject?.timeline.tracks) {
                // When tracks change (clip added, removed, or properties changed)
                if let project = appState.projectState.currentProject {
                    // Reload player - hash debounce in PlaybackState prevents duplicates
                    appState.playbackState.loadProject(project)
                    appState.projectState.saveProject(project)
                }
            }
            // Backup trigger for new clip + new project race condition
            // Uses debounce to coalesce rapid changes and avoid duplicate compositions
            .onReceive(
                NotificationCenter.default.publisher(for: .clipAddedToTimeline)
                    .debounce(for: .milliseconds(150), scheduler: DispatchQueue.main)
            ) { notification in
                if let project = notification.object as? VideoProject {
                    // Don't use forceReload - let hash debounce prevent duplicates
                    // The hash WILL be different since a clip was added
                    appState.playbackState.loadProject(project)
                }
            }
            .alert(item: $errorPresenter.activeError) { error in
                let message = if let suggestion = error.recoverySuggestion {
                    "\(error.localizedDescription)\n\n💡 \(suggestion)"
                } else {
                    error.localizedDescription
                }

                return Alert(
                    title: Text(String(localized: "error.title", defaultValue: "Error")),
                    message: Text(message),
                    dismissButton: .default(Text(String(localized: "action.ok", defaultValue: "OK"))) {
                        errorPresenter.dismiss()
                    }
                )
            }
            // Refactored Modifiers
            .withFileDropHandling()
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
            .onReceive(NotificationCenter.default.publisher(for: NSNotification.Name("ExportAsGIF"))) { _ in
                showGIFSheet = true
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
            .onReceive(NotificationCenter.default.publisher(for: NSNotification.Name("ExportTranscriptPDF"))) { _ in
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
            .onReceive(NotificationCenter.default.publisher(for: NSNotification.Name("GenerateVoiceover"))) { _ in
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
                            ServiceContainer.shared.toastManager.show(String(localized: "toast.voiceover_saved", defaultValue: "✅ Voiceover saved!"))
                            NSWorkspace.shared.open(url)
                        }
                    )
                }
            }
            .onReceive(NotificationCenter.default.publisher(for: NSNotification.Name("GenerateThumbnail"))) { _ in
                showThumbnailSheet = true
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
                            ServiceContainer.shared.toastManager.show(String(localized: "toast.thumbnail_copied", defaultValue: "✅ Thumbnail copied!"))
                        }
                    )
                }
            }
            .tooltipOverlay()
    }

    var mainContent: some View {
        @Bindable var appState = appState
        return ZStack(alignment: .top) {
            if appState.appMode == .recording {
                RecordingModeView()
                    .transition(.asymmetric(
                        insertion: .move(edge: .leading).combined(with: .opacity),
                        removal: .move(edge: .trailing).combined(with: .opacity)
                    ))
            } else {
                EditorLayoutView(
                    selectedClip: $selectedClip,
                    selectedClipIds: $appState.selectedClipIds
                )
                .transition(.asymmetric(
                    insertion: .move(edge: .trailing).combined(with: .opacity),
                    removal: .move(edge: .leading).combined(with: .opacity)
                ))
            }
        }
        .animation(.spring(response: 0.4, dampingFraction: 0.8), value: appState.appMode)
        .toolbar {
            ToolbarItem(placement: .navigation) {
                HStack(spacing: 8) {
                    Button(action: { 
                        withAnimation {
                            appState.appMode = (appState.appMode == .recording ? .editing : .recording)
                        }
                    }, label: {
                        Label(appState.appMode == .recording ? "Editor" : "Record", 
                              systemImage: appState.appMode == .recording ? "scissors" : "record.circle")
                    })
                    .keyboardShortcut("M", modifiers: [.command])
                    .help("Toggle Record/Edit Mode (Cmd+M)")
                }
            }
            
            ToolbarItem(placement: .automatic) {
                HStack(spacing: 12) {
                    Button(action: { undoManager?.undo() }, label: {
                        Image(systemName: "arrow.uturn.backward")
                    })
                    .disabled(!(undoManager?.canUndo ?? false))
                    .keyboardShortcut("z", modifiers: [.command])

                    Button(action: { undoManager?.redo() }, label: {
                        Image(systemName: "arrow.uturn.forward")
                    })
                    .disabled(!(undoManager?.canRedo ?? false))
                    .keyboardShortcut("z", modifiers: [.command, .shift])
                }
            }
            
            ToolbarItem(placement: .principal) {
                if appState.appMode == .editing {
                    HStack(spacing: 4) {
                        Image(systemName: "sparkles")
                            .symbolEffect(.pulse, options: .repeating)
                            .foregroundStyle(Theme.Colors.accentGradient)
                        Text(appState.projectState.currentProject?.name ?? "Untitled Project")
                            .font(.headline)
                    }
                }
            }

            ToolbarItem(placement: .primaryAction) {
                HStack(spacing: 12) {
                    // MAGIC QUICK BUTTON
                    Button(action: { 
                        // Trigger Magic Fix for selected clip or global project
                        NotificationCenter.default.post(name: NSNotification.Name("TriggerMagicFix"), object: nil)
                    }, label: {
                        Label("Magic Fix", systemImage: "wand.and.stars")
                            .foregroundStyle(Theme.Colors.accentGradient)
                    })
                    .help("Apply Magic Fix to Selected Clip (Cmd+Shift+M)")
                    .keyboardShortcut("m", modifiers: [.command, .shift])

                    Divider()
                        .frame(height: 16)

                    // SHARE/EXPORT
                    Button(action: { appState.showExportSheet = true }, label: {
                        Label("Share", systemImage: "square.and.arrow.up")
                    })
                    .buttonStyle(.borderedProminent)
                    .tint(.blue)
                    .help("Export and Share Video")
                }
            }
        }
    }
}

// MARK: - Export Menu Functions

extension MainContentView {
    /// Export as animated GIF using FFmpeg
    private func exportAsGIF() {
        guard let project = appState.projectState.currentProject,
              let clip = project.timeline.tracks.first?.clips.first else {
            ServiceContainer.shared.toastManager.show(String(localized: "toast.error.no_clip_to_export", defaultValue: "No clip to export"), type: .error)
            return
        }
        
        ServiceContainer.shared.toastManager.show(String(localized: "toast.exporting_gif", defaultValue: "🎞️ Exporting GIF..."))
        
        Task {
            do {
                let outputURL = FileManager.default.temporaryDirectory
                    .appendingPathComponent("\(project.name)_clip.gif")
                
                try await ServiceContainer.shared.ffmpegService.exportAsGIF(inputURL: clip.url, outputURL: outputURL)
                
                // Show save panel
                await MainActor.run {
                    let savePanel = NSSavePanel()
                    savePanel.allowedContentTypes = [.gif]
                    savePanel.nameFieldStringValue = "\(project.name).gif"
                    
                    savePanel.begin { response in
                        if response == .OK, let url = savePanel.url {
                            try? FileManager.default.copyItem(at: outputURL, to: url)
                            ServiceContainer.shared.toastManager.show(String(localized: "toast.gif_saved", defaultValue: "GIF saved!"))
                        }
                    }
                }
            } catch {
                await MainActor.run {
                    ServiceContainer.shared.toastManager.show(String(localized: "toast.error.gif_failed", defaultValue: "GIF export failed") + ": \(error.localizedDescription)", type: .error)
                }
            }
        }
    }
    
    /// Export transcript as PDF
    private func exportTranscriptPDF() {
        guard let project = appState.projectState.currentProject else {
            ServiceContainer.shared.toastManager.show(String(localized: "toast.error.no_project", defaultValue: "No project open"), type: .error)
            return
        }
        
        let captions = project.timeline.tracks
            .flatMap { $0.clips }
            .flatMap { $0.captions }
        
        guard !captions.isEmpty else {
            ServiceContainer.shared.toastManager.show(String(localized: "toast.error.no_captions_for_pdf", defaultValue: "No captions to export. Generate captions first."), type: .error)
            return
        }
        
        ServiceContainer.shared.toastManager.show(String(localized: "toast.generating_pdf", defaultValue: "📄 Generating PDF..."))
        
        Task {
            do {
                let desktopURL = FileManager.default.urls(for: .desktopDirectory, in: .userDomainMask).first!
                let outputURL = desktopURL.appendingPathComponent("\(project.name)_Transcript.pdf")
                
                try await ServiceContainer.shared.pdfService.generateStudyGuide(for: project, outputURL: outputURL)
                
                await MainActor.run {
                    ServiceContainer.shared.toastManager.show(String(localized: "toast.pdf_saved", defaultValue: "PDF saved to Desktop!"))
                    NSWorkspace.shared.open(outputURL)
                }
            } catch {
                await MainActor.run {
                    ServiceContainer.shared.toastManager.show(String(localized: "toast.error.pdf_failed", defaultValue: "PDF export failed"), type: .error)
                }
            }
        }
    }
    
    /// Generate AI thumbnail
    private func generateThumbnail() {
        guard let project = appState.projectState.currentProject,
              let clip = project.timeline.tracks.first?.clips.first else {
            ServiceContainer.shared.toastManager.show(String(localized: "toast.error.no_clip_for_thumbnail", defaultValue: "No clip for thumbnail"), type: .error)
            return
        }
        
        ServiceContainer.shared.toastManager.show(String(localized: "toast.generating_thumbnail", defaultValue: "🎨 Generating thumbnail..."))
        
        Task {
            do {
                let image = try await ServiceContainer.shared.thumbnailService.generateBestThumbnail(for: clip.url)
                await MainActor.run {
                    // Copy to clipboard
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.writeObjects([image])
                    ServiceContainer.shared.toastManager.show(String(localized: "toast.thumbnail_copied_clipboard", defaultValue: "✅ Thumbnail copied to clipboard!"))
                }
            } catch {
                await MainActor.run {
                    ServiceContainer.shared.toastManager.show(String(localized: "toast.error.thumbnail_failed", defaultValue: "Thumbnail generation failed"), type: .error)
                }
            }
        }
    }
    
    /// Generate voiceover from captions
    private func generateVoiceover() {
        guard let project = appState.projectState.currentProject else {
            ServiceContainer.shared.toastManager.show("No project open", type: .error)
            return
        }
        
        let captions = project.timeline.tracks
            .flatMap { $0.clips }
            .flatMap { $0.captions }
        
        guard !captions.isEmpty else {
            ServiceContainer.shared.toastManager.show(String(localized: "toast.error.no_captions_for_voiceover", defaultValue: "No captions for voiceover. Generate captions first."), type: .error)
            return
        }
        
        ServiceContainer.shared.toastManager.show(String(localized: "toast.generating_voiceover", defaultValue: "🎤 Generating voiceover..."))
        
        Task {
            do {
                let desktopURL = FileManager.default.urls(for: .desktopDirectory, in: .userDomainMask).first!
                let outputURL = desktopURL.appendingPathComponent("\(project.name)_Voiceover.m4a")
                
                try await ServiceContainer.shared.voiceoverService.generateVoiceoverFromCaptions(captions, outputURL: outputURL)
                
                await MainActor.run {
                    ServiceContainer.shared.toastManager.show(String(localized: "toast.voiceover_saved_desktop", defaultValue: "✅ Voiceover saved to Desktop!"))
                    NSWorkspace.shared.open(outputURL)
                }
            } catch {
                await MainActor.run {
                    ServiceContainer.shared.toastManager.show(String(localized: "toast.error.voiceover_failed", defaultValue: "Voiceover failed") + ": \(error.localizedDescription)", type: .error)
                }
            }
        }
    }
}

#Preview {
    MainContentView()
        .environment(ServiceContainer.shared.appState)
        .frame(minWidth: 1080, minHeight: 720)
}
