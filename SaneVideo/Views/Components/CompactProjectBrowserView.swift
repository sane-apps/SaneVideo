//
//  CompactProjectBrowserView.swift
//  SaneVideo
//
//  Compact project browser for sidebar
//

import SwiftUI

struct CompactProjectBrowserView: View {
    @Environment(AppState.self) var appState
    @State private var showingFullBrowser = false

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Text("Projects")
                    .font(.headline)
                Spacer()
                Button {
                    NotificationCenter.default.post(name: NSNotification.Name("ShowProjectBrowser"), object: nil)
                } label: {
                    Label("Browse All", systemImage: "arrow.right.circle")
                        .font(.caption)
                }
                .buttonStyle(.borderless)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)

            Divider()

            // Projects list
            ScrollView {
                LazyVStack(spacing: 8) {
                    ForEach(appState.projectState.projects.prefix(10)) { project in
                        CompactProjectRow(
                            project: project,
                            isCurrent: appState.projectState.currentProject?.id == project.id
                        ) {
                            appState.projectState.currentProject = project
                        }
                    }
                }
                .padding(.vertical, 8)
            }
        }
    }
}

struct CompactProjectRow: View {
    let project: VideoProject
    let isCurrent: Bool
    let onSelect: () -> Void

    @State private var thumbnail: NSImage?
    private var firstClip: VideoClip? {
        project.timeline.tracks.first(where: { !$0.clips.isEmpty })?.clips.first
    }

    var body: some View {
        Button(action: onSelect) {
            HStack(spacing: 10) {
                // Thumbnail
                ZStack {
                    if let thumbnail = thumbnail {
                        Image(nsImage: thumbnail)
                            .resizable()
                            .aspectRatio(contentMode: .fill)
                    } else {
                        RoundedRectangle(cornerRadius: 6)
                            .fill(Color.accentColor.opacity(0.2))
                        Image(systemName: firstClip == nil ? "film.stack" : "photo")
                            .font(.system(size: 16))
                            .foregroundColor(.secondary)
                    }
                }
                .frame(width: 50, height: 32)
                .clipShape(RoundedRectangle(cornerRadius: 6))

                // Info
                VStack(alignment: .leading, spacing: 2) {
                    Text(project.name)
                        .font(.system(size: 13, weight: isCurrent ? .semibold : .regular))
                        .foregroundColor(isCurrent ? .accentColor : .primary)
                        .lineLimit(1)

                    let clipCount = project.timeline.tracks.reduce(0) { $0 + $1.clips.count }
                    Text("\(clipCount) clip\(clipCount == 1 ? "" : "s")")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }

                Spacer()

                if isCurrent {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundColor(.accentColor)
                        .font(.system(size: 14))
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .background {
                RoundedRectangle(cornerRadius: 8)
                    .fill(isCurrent ? Color.accentColor.opacity(0.1) : Color.clear)
            }
        }
        .buttonStyle(.plain)
        .task {
            await loadThumbnail()
        }
    }

    private func loadThumbnail() async {
        guard let clip = firstClip, !clip.isMissing else { return }
        let time = CMTime(seconds: clip.effectiveDuration.seconds * 0.25, preferredTimescale: 600)
        let originalTime = clip.originalTime(forEffectiveTime: time) ?? clip.trimStart
        if let thumb = await ServiceContainer.shared.thumbnailService.thumbnail(
            for: clip,
            time: originalTime,
            size: CGSize(width: 100, height: 64)
        ) {
            await MainActor.run {
                self.thumbnail = thumb
            }
        }
    }
}

