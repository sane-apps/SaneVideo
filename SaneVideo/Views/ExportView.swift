//
//  ExportView.swift
//  SaneVideo
//
//  Created by SaneVideo Refactor
//

import AVFoundation
import SwiftUI

struct ExportView: View {
    @Environment(\.dismiss) var dismiss
    @Environment(AppState.self) var appState

    // MARK: - State (Internal for Extension Access)

    @State var exportProgress: Double = 0
    @State var isExporting = false
    @State var exportError: Error?
    @State var showingError = false
    @State var exportSettings = SaneExportSettings()
    @State var selectedPreset: ExportPreset? = .youtube4K
    @State var mlEffects = MLExportEffects()
    @State var speedTracker = ExportSpeedTracker()
    @State var estimatedTotalBytes: Int64 = 0

    // YouTube State
    var youtubeService = ServiceContainer.shared.youtubeService
    @State var showYouTubeUpload = false
    @State var videoTitle = ""
    @State var videoDescription = ""
    @State var isGeneratingAI = false

    // Services
    let exportEngine = ServiceContainer.shared.exportService

    // MARK: - Computed Properties

    var hasMultipleClipsSelected: Bool {
        appState.selectedClipIds.count > 1
    }

    var selectedClips: [VideoClip] {
        guard let project = appState.currentProject else { return [] }
        return project.timeline.tracks
            .flatMap { $0.clips }
            .filter { appState.selectedClipIds.contains($0.id) }
    }

    private var hasCaptions: Bool {
        guard let project = appState.currentProject else { return false }
        return project.timeline.tracks
            .flatMap { $0.clips }
            .contains { !$0.captions.isEmpty }
    }
    
    // CRITICAL FIX: Check if timeline is empty
    private var isTimelineEmpty: Bool {
        guard let project = appState.currentProject else { return true }
        return project.timeline.tracks.allSatisfy { $0.clips.isEmpty }
    }

    /*
    private var templateSettings: SaneExportSettings? {
        // Template logic removed as VideoProject doesn't support templateId yet
        return nil
    }
    */

    // MARK: - Body

    var body: some View {
        VStack(spacing: 24) {
            // Header Section
            VStack(spacing: 8) {
                if isExporting {
                    LoadingIndicator(
                        message: exportProgress >= 1.0 ? "Finishing up..." : "Exporting...",
                        progress: exportProgress
                    )
                    .transition(.smoothScale)
                } else if youtubeService.isUploading {
                    LoadingIndicator(
                        message: "Uploading to YouTube...",
                        progress: youtubeService.uploadProgress
                    )
                    .transition(.smoothScale)
                } else {
                    Image(systemName: "film.stack")
                        .font(.system(size: 48))
                        .foregroundStyle(
                            LinearGradient(
                                colors: [.blue, .teal],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .padding(.bottom, 8)
                        .smoothAppear()
    
                    Text(appState.currentProject?.name ?? "Untitled Project")
                        .font(.title2)
                        .fontWeight(.bold)
                        .smoothAppear()
                }
            }
            .padding(.top, 10)
            .animation(.smoothUI, value: isExporting)
            .animation(.smoothUI, value: youtubeService.isUploading)
    
            // YouTube Config
            ExportYouTubeSection(
                youtubeService: youtubeService,
                showYouTubeUpload: $showYouTubeUpload,
                videoTitle: $videoTitle,
                videoDescription: $videoDescription,
                isGeneratingAI: $isGeneratingAI,
                hasCaptions: hasCaptions,
                onGenerateAI: generateAITitleDescription
            )
    
            // Primary Actions
            HStack(spacing: 16) {
                // Hero Export Button (Most prominent)
                Button {
                    ServiceContainer.shared.hapticsManager.impact()
                    if hasMultipleClipsSelected {
                        startBatchExport()
                    } else {
                        if showYouTubeUpload {
                            startExport(uploadToYouTube: true)
                        } else {
                            startExport(uploadToYouTube: false)
                        }
                    }
                } label: {
                    Label(
                        hasMultipleClipsSelected ? String(localized: "export.action.batch_export", defaultValue: "Batch Export Only") : (showYouTubeUpload ? String(localized: "export.action.export_upload", defaultValue: "Export & Upload") : String(localized: "export.action.export_file", defaultValue: "Export File")),
                        systemImage: hasMultipleClipsSelected ? "square.stack.3d.up.fill" : "square.and.arrow.up.fill"
                    )
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 8)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .disabled(isExporting || youtubeService.isUploading || isTimelineEmpty)
                .accessibilityIdentifier("export.action.primary")
    
                // YouTube Toggle
                Button {
                    withAnimation {
                        showYouTubeUpload.toggle()
                    }
                } label: {
                    Label(showYouTubeUpload ? String(localized: "action.hide", defaultValue: "Hide") : String(localized: "action.youtube", defaultValue: "YouTube"), systemImage: "video.badge.plus")
                        .padding(.vertical, 8)
                }
                .buttonStyle(.bordered)
                .controlSize(.large)
                .disabled(isExporting || youtubeService.isUploading)
                .accessibilityIdentifier("export.action.toggle_youtube")
    
                Button {
                    ServiceContainer.shared.hapticsManager.selection()
                    shareLink()
                } label: {
                    Image(systemName: "link")
                        .font(.system(size: 16))
                        .padding(.vertical, 8)
                }
                .buttonStyle(.bordered)
                .controlSize(.large)
                .disabled(isExporting || youtubeService.isUploading)
                .accessibilityIdentifier("export.action.share_link")
            }
    
            // Export Settings Configuration
            ExportConfigurationView(
                exportSettings: $exportSettings,
                selectedPreset: $selectedPreset,
                mlEffects: $mlEffects,
                estimateFileSize: estimateFileSize
            )
            .disabled(isExporting || youtubeService.isUploading)
    
            HStack {
                // Additional Export Options
                Menu {
                    Button(String(localized: "export.option.thumbnail", defaultValue: "Export Thumbnail"), action: generateThumbnail)
                    Button(String(localized: "export.option.study_guide", defaultValue: "Export Study Guide (PDF)"), action: exportStudyGuide)
                    Button(String(localized: "export.option.gif", defaultValue: "Export as GIF"), action: exportAsGIF)
                    Button(String(localized: "export.option.voiceover", defaultValue: "Generate Voiceover"), action: generateVoiceover)
                } label: {
                    Label(String(localized: "action.more_options", defaultValue: "More Options"), systemImage: "ellipsis.circle")
                        .accessibilityIdentifier(AccessibilityIdentifiers.moreOptionsButton)
                }
                .menuStyle(.borderlessButton)
                .frame(width: 120)
    
                Spacer()
    
                Button(String(localized: "action.close", defaultValue: "Close")) {
                    if isExporting { exportEngine.cancelExport() }
                    dismiss()
                }
                .accessibilityIdentifier(AccessibilityIdentifiers.cancelExportButton) // Changed from "CloseExportButton" to "CancelExportButton"
                .keyboardShortcut(.cancelAction)
                .controlSize(.regular)
            }
        }
        .padding(32)
        .frame(width: 520)
        .accessibilityIdentifier(AccessibilityIdentifiers.exportSheet)
        .onAppear {
            AppLogger.general.info("ExportView: appeared. isExporting: \(isExporting), isUploading: \(youtubeService.isUploading)")
            /*
            // Apply template settings if project was created from template
            if let template = templateSettings {
                exportSettings = template
                selectedPreset = .custom
            }
            */
        }
        .alert(String(localized: "export.error.title", defaultValue: "Export Error"), isPresented: $showingError, actions: {
            Button(String(localized: "action.ok", defaultValue: "OK"), role: .cancel) {
                exportError = nil
            }
            .accessibilityIdentifier("export.error.ok")
        }, message: {
            if let error = exportError {
                Text(error.localizedDescription)
            }
        })
    }

    // MARK: - Helper Methods

    func estimateFileSize() -> String {
        guard let project = appState.currentProject else { return "0 MB" }

        // Use bitrate to estimate
        // Bitrate is in bits per second
        let duration = project.timeline.duration.seconds
        guard duration > 0 else { return "0 MB" }

        // Audio bitrate (approx 192kbps)
        let audioBitrate = 192_000.0
        let videoBitrate = Double(exportSettings.bitrate)
        let totalBitrate = videoBitrate + audioBitrate

        // Additional overhead for container (approx 1-2%)
        let bitrateRef = totalBitrate * 1.02

        // Size (bits) = bitrate * duration
        // Size (bytes) = size / 8
        // Size (MB) = size / (1024*1024)

        let sizeMB = (bitrateRef * duration) / 8.0 / 1024.0 / 1024.0
        return String(format: "%.1f MB", sizeMB)
    }
}
