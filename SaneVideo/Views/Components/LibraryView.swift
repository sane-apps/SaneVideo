//
//  LibraryView.swift
//  SaneVideo
//
//  Library view for importing and managing clips in the sidebar
//

import SwiftUI
import UniformTypeIdentifiers

/// Library panel for managing project clips
struct LibraryView: View {
    @Environment(AppState.self) var appState
    @Binding var selectedClip: VideoClip?
    @State private var showingAudioImporter = false

    // Deletion State
    @State private var clipToDelete: VideoClip?
    @State private var showDeleteConfirmation = false

    var body: some View {
        VStack(spacing: 0) {
            // Import options row
            HStack(spacing: 12) {
                // Import Video
                Button(action: { appState.importVideo() }, label: {
                    HStack(spacing: 4) {
                        Image(systemName: "film.stack")
                            .font(.system(size: 12))
                        Text(String(localized: "sidebar.action.import_video", defaultValue: "Video"))
                            .font(.system(size: 11, weight: .medium))
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                })
                .buttonStyle(.plain)
                .accessibilityIdentifier("ImportVideoButton")
                .help(KeyboardShortcutHelper.helpWithShortcut("Import Video", key: "i", modifiers: [.command]))

                // Import Audio
                Button(action: { showingAudioImporter = true }, label: {
                    HStack(spacing: 4) {
                        Image(systemName: "waveform")
                            .font(.system(size: 12))
                        Text(String(localized: "sidebar.action.import_audio", defaultValue: "Audio"))
                            .font(.system(size: 11, weight: .medium))
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(Color.green.opacity(0.15))
                })
                .buttonStyle(.plain)
                .accessibilityIdentifier("ImportAudioButton")
                .help("Import Audio File")

                Spacer()

                if appState.projectState.isProcessing {
                    ProgressView()
                        .scaleEffect(0.7)
                }
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 6)
            .background(Color(white: 0.15))

            Divider()

            // Clips header
            HStack {
                Text(String(localized: "sidebar.clips.header", defaultValue: "Project Clips"))
                    .font(.caption)
                    .foregroundColor(.secondary)
                Spacer()
                Text("\(clipCount) clips")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 4)

            Divider()

            // Clips list
            clipsListView
        }
        .fileImporter(
            isPresented: $showingAudioImporter,
            allowedContentTypes: [.audio, .mp3, .wav, .aiff],
            allowsMultipleSelection: false
        ) { result in
            switch result {
            case let .success(urls):
                if let url = urls.first {
                    Task {
                        await appState.projectState.addAudioToTimeline(url: url)
                    }
                }
            case let .failure(error):
                ServiceContainer.shared.toastManager.show(
                    String(localized: "sidebar.error.import_audio", defaultValue: "Failed to import audio") + ": \(error.localizedDescription)",
                    type: .error
                )
            }
        }
        .confirmationDialog(
            String(localized: "sidebar.delete.title", defaultValue: "Delete File from Disk?"),
            isPresented: $showDeleteConfirmation,
            titleVisibility: .visible
        ) {
            if let name = clipToDelete?.url.lastPathComponent {
                Button(String(localized: "sidebar.action.delete", defaultValue: "Delete") + " '\(name)'", role: .destructive) {
                    if let clip = clipToDelete {
                        appState.projectState.deleteClipFile(clip)
                    }
                }
                .accessibilityIdentifier("sidebar.delete_disk_confirm")
            }
            Button(String(localized: "sidebar.action.cancel", defaultValue: "Cancel"), role: .cancel) {}
        } message: {
            Text(String(localized: "sidebar.delete.message", defaultValue: "This will move the source file to the Trash. This action cannot be undone."))
        }
    }

    // MARK: - Clips List

    @ViewBuilder
    private var clipsListView: some View {
        if let project = appState.projectState.currentProject, !project.timeline.tracks.allSatisfy({ $0.clips.isEmpty }) {
            List {
                ForEach(project.timeline.tracks) { track in
                    Section(header: Text(track.type.rawValue)) {
                        ForEach(track.clips) { clip in
                            clipRowView(clip: clip)
                        }
                    }
                }
            }
            .listStyle(.plain)
            .scrollContentBackground(.hidden)
        } else {
            emptyClipsView
        }
    }

    @ViewBuilder
    private func clipRowView(clip: VideoClip) -> some View {
        HStack(spacing: 4) {
            LibraryClipRow(clip: clip, isSelected: selectedClip?.id == clip.id)
        }
        .contentShape(Rectangle())
        .onTapGesture {
            selectedClip = clip
            appState.playbackState.seek(to: clip.startTime)
        }
        .onDrag {
            NSItemProvider(object: clip.id.uuidString as NSString)
        }
        .contextMenu {
            clipContextMenu(clip: clip)
        }
        .listRowInsets(EdgeInsets(top: 4, leading: 8, bottom: 4, trailing: 8))
        .listRowSeparator(.hidden)
        .listRowBackground(Color.clear)
    }

    // MARK: - Context Menu

    @ViewBuilder
    private func clipContextMenu(clip: VideoClip) -> some View {
        Button {
            Task { _ = try? await appState.projectState.generateCaptions(for: clip) }
        } label: {
            Label(String(localized: "sidebar.menu.captions", defaultValue: "Generate Captions"), systemImage: "captions.bubble")
        }
        .accessibilityIdentifier("sidebar.menu.captions")

        Button { appState.projectState.removeSilence(from: clip) } label: {
            Label(String(localized: "sidebar.menu.remove_silence", defaultValue: "Remove Silence"), systemImage: "waveform.path")
        }
        .accessibilityIdentifier("sidebar.menu.remove_silence")

        Button { appState.projectState.removeFillerWords(from: clip) } label: {
            Label(String(localized: "sidebar.menu.remove_fillers", defaultValue: "Remove Fillers"), systemImage: "text.badge.minus")
        }
        .disabled(clip.captions.isEmpty)
        .accessibilityIdentifier("sidebar.menu.remove_fillers")

        Divider()

        Button { appState.projectState.rotateClip(clip) } label: {
            Label(String(localized: "sidebar.menu.rotate", defaultValue: "Rotate 90°"), systemImage: "rotate.right")
        }
        .accessibilityIdentifier("sidebar.menu.rotate")

        Button(String(localized: "sidebar.menu.finder", defaultValue: "Show in Finder")) {
            NSWorkspace.shared.activateFileViewerSelecting([clip.url])
        }
        .accessibilityIdentifier("sidebar.menu.finder")

        Divider()

        Button(role: .destructive) {
            appState.projectState.deleteClip(clip)
        } label: {
            Label(String(localized: "sidebar.menu.remove", defaultValue: "Remove from Project"), systemImage: "xmark.bin")
        }
        .accessibilityIdentifier("sidebar.menu.remove")

        Button(role: .destructive) {
            clipToDelete = clip
            showDeleteConfirmation = true
        } label: {
            Label(String(localized: "sidebar.menu.delete_disk", defaultValue: "Delete from Disk"), systemImage: "trash")
        }
        .accessibilityIdentifier("sidebar.menu.delete_disk")
    }

    // MARK: - Empty State

    private var emptyClipsView: some View {
        VStack(spacing: 12) {
            Spacer()
            Image(systemName: "film.stack")
                .font(.system(size: 40))
                .foregroundStyle(.tertiary)
            Text(String(localized: "sidebar.empty.title", defaultValue: "No clips yet"))
                .font(.headline)
                .foregroundColor(.secondary)
            Text(String(localized: "sidebar.empty.message", defaultValue: "Import video or record to get started"))
                .font(.caption)
                .foregroundColor(.secondary)
            Spacer()
        }
        .padding()
    }

    private var clipCount: Int {
        appState.projectState.currentProject?.timeline.tracks.reduce(0) { $0 + $1.clips.count } ?? 0
    }
}
