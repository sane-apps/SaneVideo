//
//  SidebarView.swift
//  SaneVideo
//
//  Created by SaneVideo Refactor
//

import CoreMedia
import SwiftUI

import UniformTypeIdentifiers

struct SidebarView: View {
    @Environment(AppState.self) var appState
    @Binding var selectedClip: VideoClip?

    var body: some View {
        VStack(spacing: 0) {
            // Simple header - no tabs, just "Media"
            HStack {
                Text(String(localized: "sidebar.header", defaultValue: "Media"))
                    .font(.system(.headline, design: .rounded))
                Spacer()
            }
            .accessibilityIdentifier("sidebar.header")
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .background(.ultraThinMaterial)

            Divider()

            // Single view - Library/Media browser
            LibraryView(selectedClip: $selectedClip)
        }
        .frame(minWidth: 180, idealWidth: 240, maxWidth: 350)
        .background(.ultraThinMaterial)
    }
}

// MARK: - Library View

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
                ServiceContainer.shared.toastManager.show(String(localized: "sidebar.error.import_audio", defaultValue: "Failed to import audio") + ": \(error.localizedDescription)", type: .error)
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

// Library clip row for Advanced mode
struct LibraryClipRow: View {
    let clip: VideoClip
    let isSelected: Bool
    @State private var thumbnail: NSImage?

    /// Display-friendly name for the clip
    private var displayName: String {
        let filename = clip.url.deletingPathExtension().lastPathComponent
        // Check if filename is a UUID (recordings use UUID names)
        if UUID(uuidString: filename) != nil {
            // It's a recording with UUID name - show shortened version
            let prefix = String(filename.prefix(8))
            return String(localized: "sidebar.clip.recording", defaultValue: "Recording") + " \(prefix)"
        }
        return filename
    }

    var body: some View {
        HStack(spacing: 8) {
            // Thumbnail
            ZStack {
                if let thumb = thumbnail {
                    Image(nsImage: thumb)
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                        .frame(width: 60, height: 34)
                        .clipped() // Fix distortion/bleeding
                        .cornerRadius(Theme.Dimensions.smallCornerRadius)
                } else {
                    Rectangle()
                        .fill(Color.secondary.opacity(0.3))
                        .frame(width: 60, height: 34)
                        .cornerRadius(4)
                        .overlay(
                            Image(systemName: "film")
                                .foregroundColor(.secondary)
                        )
                }
            }

            // Info
            VStack(alignment: .leading, spacing: 2) {
                Text(displayName)
                    .font(.caption)
                    .lineLimit(1)
                HStack(spacing: 4) {
                    Text(formatDuration(clip.duration))
                        .font(.caption2)
                        .foregroundColor(.secondary)

                    // Caption badge
                    if !clip.captions.isEmpty {
                        HStack(spacing: 2) {
                            Image(systemName: "captions.bubble.fill")
                                .font(.system(size: 8))
                            Text("\(clip.captions.count)")
                                .font(.system(size: 9, weight: .medium))
                        }
                        .foregroundColor(.white)
                        .padding(.horizontal, 4)
                        .padding(.vertical, 2)
                        .background(Color.green)
                        .cornerRadius(4)
                    }
                }
            }

            Spacer()
        }
        .padding(6)
        .background(isSelected ? Color.accentColor.opacity(0.2) : Color.clear)
        .cornerRadius(6)
        .accessibilityIdentifier("sidebar.clip_row.\(clip.id)")
        .task {
            thumbnail = await ServiceContainer.shared.timelineThumbnailService.thumbnail(
                for: clip,
                time: .zero,
                size: CGSize(width: 120, height: 68)
            )
        }
    }

    private func formatDuration(_ time: CMTime) -> String {
        let seconds = CMTimeGetSeconds(time)
        let mins = Int(seconds) / 60
        let secs = Int(seconds) % 60
        return String(format: "%d:%02d", mins, secs)
    }
}
