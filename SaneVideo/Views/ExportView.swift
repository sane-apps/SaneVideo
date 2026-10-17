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
    
    private var isTimelineEmpty: Bool {
        guard let project = appState.currentProject else { return true }
        return project.timeline.tracks.allSatisfy { $0.clips.isEmpty }
    }

    // MARK: - Body

    var body: some View {
        VStack(spacing: 16) {
            HStack(spacing: 12) {
                if isExporting {
                    LoadingIndicator(
                        message: exportProgress >= 1.0 ? "Finishing up..." : "Exporting...",
                        progress: exportProgress
                    )
                    .transition(.smoothScale)
                } else {
                    ZStack {
                        Circle()
                            .fill(Theme.Colors.accent)
                        Image(systemName: "square.and.arrow.up.fill")
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundStyle(.white)
                    }
                    .frame(width: 34, height: 34)

                    VStack(alignment: .leading, spacing: 2) {
                        Text(String(localized: "export.title", defaultValue: "Export"))
                            .saneReadableSectionTitle()
                        Text(appState.currentProject?.name ?? "Untitled Project")
                            .saneReadableSupportText()
                            .lineLimit(1)
                    }
                    .smoothAppear()

                    Spacer(minLength: 0)
                }
            }
            .animation(.smoothUI, value: isExporting)

            HStack(spacing: 16) {
                Button {
                    ServiceContainer.shared.hapticsManager.impact()
                    if hasMultipleClipsSelected {
                        startBatchExport()
                    } else {
                        startExport()
                    }
                } label: {
                    Label(
                        hasMultipleClipsSelected ? String(localized: "export.action.batch_export", defaultValue: "Export Each Clip") : String(localized: "export.action.export_file", defaultValue: "Export File"),
                        systemImage: hasMultipleClipsSelected ? "square.stack.3d.up.fill" : "square.and.arrow.up.fill"
                    )
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 8)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .disabled(isExporting || isTimelineEmpty)
                .keyboardShortcut(.defaultAction)
                .accessibilityIdentifier("export.action.primary")
                .help(hasMultipleClipsSelected ? "Exports each selected clip as its own file." : "Exports a video file.")

    
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
                .disabled(isExporting || isTimelineEmpty)
                .accessibilityIdentifier("export.action.share_link")
                .help(isTimelineEmpty ? "Add a clip before sharing an exported file." : "Exports a local file and opens the system share sheet for that file.")
            }

            ScrollView {
                VStack(spacing: 12) {
                    ExportConfigurationView(
                        exportSettings: $exportSettings,
                        selectedPreset: $selectedPreset,
                        mlEffects: $mlEffects,
                        estimateFileSize: estimateFileSize
                    )
                    .disabled(isExporting)
                }
                .padding(.vertical, 2)
            }
            .scrollIndicators(.visible)
            .frame(maxHeight: 560)
    
            HStack {
                Menu {
                    Button(String(localized: "export.option.thumbnail", defaultValue: "Export Thumbnail"), action: generateThumbnail)
                    Button(String(localized: "export.option.gif", defaultValue: "Export as GIF"), action: exportAsGIF)
                    Button(String(localized: "export.option.voiceover", defaultValue: "Generate Voiceover"), action: generateVoiceover)
                } label: {
                    Label(String(localized: "action.more_options", defaultValue: "More Options"), systemImage: "ellipsis.circle")
                        .accessibilityIdentifier(AccessibilityIdentifiers.moreOptionsButton)
                }
                .menuStyle(.borderlessButton)
                .frame(width: 120)
                .help("Thumbnail, GIF and voiceover.")
    
                Spacer()
    
                Button(String(localized: "action.close", defaultValue: "Close")) {
                    if isExporting { exportEngine.cancelExport() }
                    dismiss()
                }
                .buttonStyle(SaneSheetButtonStyle(kind: .secondary, isEnabled: true))
                .accessibilityIdentifier(AccessibilityIdentifiers.cancelExportButton)
                .keyboardShortcut(.cancelAction)
                .controlSize(.regular)
            }
        }
        .padding(20)
        .frame(width: 560)
        .task { await matchSourceFootage() }
        .sanePanel(radius: 18, emphasized: true, accent: Theme.Colors.accentSoft)
        .accessibilityIdentifier(AccessibilityIdentifiers.exportSheet)
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

    /// Start from the YouTube preset that fits the main clip instead of always 4K/60.
    private func matchSourceFootage() async {
        guard let clip = appState.currentProject?.timeline.tracks.flatMap(\.clips)
            .max(by: { $0.effectiveDuration.seconds < $1.effectiveDuration.seconds }),
              let track = try? await AVURLAsset(url: clip.url).loadTracks(withMediaType: .video).first,
              let (size, fps) = try? await track.load(.naturalSize, .nominalFrameRate) else { return }
        let (preset, settings) = SaneExportSettings.youTube(matchingWidth: abs(size.width), height: abs(size.height), fps: fps)
        exportSettings = settings
        // After the settings: changing resolution flips the picker to Custom.
        await Task.yield()
        selectedPreset = preset
    }

    // MARK: - Helper Methods

    func estimateFileSize() -> String {
        guard let project = appState.currentProject else { return "0 MB" }

        // Bitrate is in bits per second
        let duration = project.timeline.duration.seconds
        guard duration > 0 else { return "0 MB" }

        let audioBitrate = 192_000.0
        let videoBitrate = Double(exportSettings.bitrate)
        let totalBitrate = videoBitrate + audioBitrate

        // About 2% container overhead.
        let bitrateRef = totalBitrate * 1.02

        let sizeMB = (bitrateRef * duration) / 8.0 / 1024.0 / 1024.0
        return String(format: "%.1f MB", sizeMB)
    }
}
