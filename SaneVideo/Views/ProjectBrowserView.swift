//
//  ProjectBrowserView.swift
//  SaneVideo
//
//  Created by SaneVideo Refactor
//

import SwiftUI
import AVFoundation

struct ProjectBrowserView: View {
    @Environment(AppState.self) var appState
    @Environment(\.dismiss) var dismiss

    @State private var hoveredProjectId: UUID?

    // Rename state
    @State private var projectToRename: VideoProject?
    @State private var newName: String = ""
    @State private var isRenaming = false

    // Delete state
    @State private var projectToDelete: VideoProject?
    @State private var showingDeleteConfirmation = false

    // Info state
    @State private var projectToShowInfo: VideoProject?
    @State private var showingProjectInfo = false

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text(String(localized: "browser.header", defaultValue: "Projects"))
                        .font(.system(size: 28, weight: .bold))
                    Text("\(appState.projectState.projects.count) projects")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }
                Spacer()
                Menu {
                    ForEach(ProjectTemplate.allTemplates) { template in
                        Button(action: {
                            appState.projectState.startNewProject(template: template)
                            dismiss()
                        }, label: {
                            Label(template.name, systemImage: template.icon)
                        })
                        .accessibilityIdentifier("browser.template.\(template.id)")
                    }
                } label: {
                    Label(String(localized: "browser.action.new", defaultValue: "New Project"), systemImage: "plus.circle.fill")
                        .font(.headline)
                }
                .buttonStyle(.borderedProminent)
                .accessibilityIdentifier("browser.new_project")
            }
            .padding(24)
            .background(.ultraThinMaterial)

            Divider()

            // Template Selection Section
            VStack(alignment: .leading, spacing: 12) {
                Text(String(localized: "browser.templates.header", defaultValue: "Choose a Template"))
                    .font(.headline)
                    .padding(.horizontal)
                    .padding(.top, 8)

                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 16) {
                        ForEach(ProjectTemplate.allTemplates) { template in
                            TemplateCard(template: template) {
                                appState.projectState.startNewProject(template: template)
                                dismiss()
                            }
                        }
                    }
                    .padding(.horizontal)
                }

                Divider()
                    .padding(.vertical, 8)
            }

            // Grid or List
            ScrollView {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 240, maximum: 280), spacing: 20)], spacing: 20) {
                    // Projects
                    ForEach(appState.projectState.projects) { project in
                        ProjectCard(
                            project: project,
                            isCurrent: appState.projectState.currentProject?.id == project.id,
                            onSelect: {
                                appState.projectState.currentProject = project
                                dismiss()
                            },
                            onRename: {
                                projectToRename = project
                                newName = project.name
                                isRenaming = true
                            },
                            onDelete: {
                                projectToDelete = project
                                showingDeleteConfirmation = true
                            },
                            onDuplicate: {
                                appState.projectState.duplicateProject(project)
                            },
                            onShowInFinder: {
                                let url = appState.projectState.getProjectFileURL(project)
                                NSWorkspace.shared.activateFileViewerSelecting([url])
                            },
                            onShowInfo: {
                                projectToShowInfo = project
                                showingProjectInfo = true
                            }
                        )
                        .id(project.id) // Force view identity for proper lazy loading
                    }
                }
                .padding()
            }
        }
        .frame(minWidth: 800, minHeight: 600)
        .background(Color(NSColor.windowBackgroundColor))
        // Escape key to close
        .onKeyPress(.escape) {
            dismiss()
            return .handled
        }
        // Project Info Sheet
        .sheet(isPresented: $showingProjectInfo) {
            if let project = projectToShowInfo {
                ProjectInfoSheet(project: project)
            }
        }
        // Rename Alert
        .alert(String(localized: "browser.rename.title", defaultValue: "Rename Project"), isPresented: $isRenaming) {
            TextField(String(localized: "browser.rename.placeholder", defaultValue: "Project Name"), text: $newName)
                .accessibilityIdentifier("browser.rename_field")
            Button(String(localized: "browser.action.rename", defaultValue: "Rename")) {
                if let project = projectToRename {
                    if appState.projectState.currentProject?.id == project.id {
                        appState.projectState.renameProject(newName)
                    } else {
                        appState.projectState.currentProject = project
                        appState.projectState.renameProject(newName)
                    }
                }
            }
            .accessibilityIdentifier("browser.rename_submit")
            Button(String(localized: "browser.action.cancel", defaultValue: "Cancel"), role: .cancel) {}
        } message: {
            if let name = projectToRename?.name {
                Text(String(localized: "browser.rename.message", defaultValue: "Enter a new name for project") + ": '\(name)'")
            }
        }

        // Delete Alert
        .confirmationDialog(
            String(localized: "browser.delete.title", defaultValue: "Are you sure you want to delete this project?"),
            isPresented: $showingDeleteConfirmation,
            titleVisibility: .visible
        ) {
            if let name = projectToDelete?.name {
                Button(String(localized: "browser.action.delete", defaultValue: "Delete") + " '\(name)'", role: .destructive) {
                    if let project = projectToDelete {
                        appState.projectState.deleteProject(project)
                    }
                }
                .accessibilityIdentifier("browser.delete_confirm")
            }
            Button(String(localized: "browser.action.cancel", defaultValue: "Cancel"), role: .cancel) {}
        } message: {
            Text(String(localized: "browser.delete.message", defaultValue: "This action cannot be undone."))
        }
    }
}

struct TemplateCard: View {
    let template: ProjectTemplate
    let onSelect: () -> Void

    @State private var isHovering = false

    var body: some View {
        Button(action: onSelect) {
            VStack(spacing: 12) {
                Image(systemName: template.icon)
                    .font(.system(size: 32))
                    .foregroundColor(Color(template.color))
                    .frame(width: 60, height: 60)
                    .background(Color(template.color).opacity(0.1))
                    .clipShape(Circle())

                VStack(spacing: 4) {
                    Text(template.name)
                        .font(.headline)
                        .foregroundColor(.primary)

                    Text(template.description)
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                        .lineLimit(2)
                }
            }
            .frame(width: 180, height: 160)
            .padding(16)
            .background(Color(NSColor.controlBackgroundColor))
            .cornerRadius(12)
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(isHovering ? Color.accentColor : Color.secondary.opacity(0.2), lineWidth: isHovering ? 2 : 1)
            )
            .shadow(color: Color.black.opacity(isHovering ? 0.1 : 0), radius: 4, x: 0, y: 2)
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("browser.template_card.\(template.id)")
        .onHover { hover in
            withAnimation(.smoothUI) {
                isHovering = hover
            }
        }
        .scaleEffect(isHovering ? 1.02 : 1.0)
        .animation(.smoothUI, value: isHovering)
    }
}

struct ProjectCard: View {
    let project: VideoProject
    let isCurrent: Bool
    let onSelect: () -> Void
    let onRename: () -> Void
    let onDelete: () -> Void
    let onDuplicate: () -> Void
    let onShowInFinder: () -> Void
    let onShowInfo: () -> Void

    @State private var isHovering = false
    @State private var thumbnail: NSImage?
    @State private var isLoadingThumbnail = false

    // Get first clip from project for thumbnail
    private var firstClip: VideoClip? {
        project.timeline.tracks.first(where: { !$0.clips.isEmpty })?.clips.first
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Thumbnail / Preview Area
            ZStack {
                if let thumbnail = thumbnail {
                    Image(nsImage: thumbnail)
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                } else {
                    // Fallback gradient background
                    LinearGradient(
                        colors: [
                            Color.accentColor.opacity(0.3),
                            Color.accentColor.opacity(0.1)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )

                    // Icon overlay
                    Image(systemName: firstClip == nil ? "film.stack" : "photo")
                        .font(.system(size: 32))
                        .foregroundColor(.secondary.opacity(0.6))
                }

                // Loading indicator
                if isLoadingThumbnail {
                    ProgressView()
                        .scaleEffect(0.8)
                }
            }
            .frame(height: 140)
            .frame(maxWidth: .infinity)
            .clipped()
            .overlay(
                // Subtle border
                Rectangle()
                    .stroke(Color.secondary.opacity(0.1), lineWidth: 1)
            )

            // Info Area
            VStack(alignment: .leading, spacing: 6) {
                Text(project.name)
                    .font(.system(size: 14, weight: .semibold))
                    .lineLimit(2)
                    .foregroundColor(isCurrent ? .accentColor : .primary)
                    .fixedSize(horizontal: false, vertical: true)

                HStack(spacing: 8) {
                    // PERFORMANCE: Use model's clipCount instead of inline reduce()
                    Label("\(project.clipCount)", systemImage: project.clipCount == 1 ? "film" : "film.stack")
                        .font(.caption)
                        .foregroundColor(.secondary)

                    Text("•")
                        .foregroundColor(.secondary.opacity(0.5))

                    Text(project.modifiedAt.formatted(.relative(presentation: .named)))
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background {
                RoundedRectangle(cornerRadius: 0)
                    .fill(.regularMaterial)
            }
        }
        .background {
            RoundedRectangle(cornerRadius: 16)
                .fill(.regularMaterial)
        }
        .cornerRadius(16)
        .accessibilityIdentifier("browser.project_card.\(project.id)")
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .stroke(
                    isCurrent ? Color.accentColor : (isHovering ? Color.accentColor.opacity(0.4) : Color.clear),
                    lineWidth: isCurrent ? 3 : (isHovering ? 2 : 0)
                )
        )
        .shadow(
            color: Color.black.opacity(isHovering ? 0.15 : (isCurrent ? 0.1 : 0.05)),
            radius: isHovering ? 8 : (isCurrent ? 6 : 4),
            x: 0,
            y: isHovering ? 4 : 2
        )
        .onTapGesture {
            onSelect()
        }
        .onHover { hover in
            withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                isHovering = hover
            }
        }
        .scaleEffect(isHovering ? 1.03 : (isCurrent ? 1.01 : 1.0))
        .animation(.spring(response: 0.3, dampingFraction: 0.7), value: isHovering)
        .task {
            await loadThumbnail()
        }
        .contextMenu {
            // Primary Actions
            Button {
                onSelect()
            } label: {
                Label(String(localized: "browser.action.open", defaultValue: "Open"), systemImage: "arrow.right.circle")
            }
            .accessibilityIdentifier("browser.card_menu.open")

            Divider()

            // Project Management
            Button {
                onDuplicate()
            } label: {
                Label(String(localized: "browser.action.duplicate", defaultValue: "Duplicate"), systemImage: "doc.on.doc")
            }
            .accessibilityIdentifier("browser.card_menu.duplicate")

            Button {
                onShowInFinder()
            } label: {
                Label(String(localized: "browser.action.finder", defaultValue: "Show in Finder"), systemImage: "folder")
            }
            .accessibilityIdentifier("browser.card_menu.finder")

            Button {
                onShowInfo()
            } label: {
                Label(String(localized: "browser.action.info", defaultValue: "Get Info"), systemImage: "info.circle")
            }
            .accessibilityIdentifier("browser.card_menu.info")

            Divider()

            // Edit Actions
            Button {
                onRename()
            } label: {
                Label(String(localized: "browser.action.rename_menu", defaultValue: "Rename..."), systemImage: "pencil")
            }
            .accessibilityIdentifier("browser.card_menu.rename")

            Button(role: .destructive) {
                onDelete()
            } label: {
                Label(String(localized: "browser.action.delete", defaultValue: "Delete"), systemImage: "trash")
            }
            .accessibilityIdentifier("browser.card_menu.delete")
        }
    }

    // MARK: - Thumbnail Loading

    private func loadThumbnail() async {
        guard let clip = firstClip, !clip.isMissing else {
            return
        }

        guard !isLoadingThumbnail else { return }
        isLoadingThumbnail = true

        // PERFORMANCE: Add small delay to throttle concurrent thumbnail loads
        // This prevents all 30 projects from loading thumbnails simultaneously
        try? await Task.sleep(for: .milliseconds(50))

        // Get thumbnail from first clip at 25% through its duration
        let time = CMTime(seconds: clip.effectiveDuration.seconds * 0.25, preferredTimescale: 600)
        let originalTime = clip.originalTime(forEffectiveTime: time) ?? clip.trimStart

        // QUALITY: Request retina-quality thumbnails (2x for display, higher for crisp previews)
        // Card display is ~280x140, request 800x450 for high-quality retina display
        let scaleFactor: CGFloat = 2.0 // Retina scaling
        let size = CGSize(width: 800 * scaleFactor, height: 450 * scaleFactor)

        // PERFORMANCE: Use lower priority for thumbnail loading
        let thumb = await Task.detached(priority: .utility) {
            await ServiceContainer.shared.thumbnailService.thumbnail(
                for: clip,
                time: originalTime,
                size: size
            )
        }.value

        if let thumb = thumb {
            await MainActor.run {
                self.thumbnail = thumb
                self.isLoadingThumbnail = false
            }
        } else {
            await MainActor.run {
                self.isLoadingThumbnail = false
            }
        }
    }
}

// MARK: - Project Info Sheet

struct ProjectInfoSheet: View {
    let project: VideoProject
    @Environment(\.dismiss) var dismiss

    // PERFORMANCE: Use model's clipCount property instead of inline calculation
    private var clipCount: Int {
        project.clipCount
    }

    private var trackCount: Int {
        project.timeline.tracks.count
    }

    private var durationString: String {
        let seconds = CMTimeGetSeconds(project.timeline.duration)
        let minutes = Int(seconds) / 60
        let secs = Int(seconds) % 60
        if minutes > 0 {
            return String(format: "%d:%02d", minutes, secs)
        } else {
            return String(format: "0:%02d", secs)
        }
    }

    private var fileSizeString: String {
        let url = ServiceContainer.shared.projectStore.fileURL(for: project)
        if let attributes = try? FileManager.default.attributesOfItem(atPath: url.path),
           let size = attributes[.size] as? UInt64 {
            let formatter = ByteCountFormatter()
            formatter.countStyle = .file
            return formatter.string(fromByteCount: Int64(size))
        }
        return "Unknown"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            // Header
            HStack {
                Text("Project Info")
                    .font(.system(size: 24, weight: .bold))
                Spacer()
                Button {
                    dismiss()
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundColor(.secondary)
                }
                .buttonStyle(.plain)
            }
            .padding(.bottom, 8)

            Divider()

            // Project Name
            VStack(alignment: .leading, spacing: 8) {
                Text("Name")
                    .font(.headline)
                    .foregroundColor(.secondary)
                Text(project.name)
                    .font(.title3)
            }

            Divider()

            // Statistics
            VStack(alignment: .leading, spacing: 12) {
                Text("Statistics")
                    .font(.headline)
                    .foregroundColor(.secondary)

                HStack(spacing: 24) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Clips")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        Text("\(clipCount)")
                            .font(.title2)
                            .fontWeight(.semibold)
                    }

                    VStack(alignment: .leading, spacing: 4) {
                        Text("Tracks")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        Text("\(trackCount)")
                            .font(.title2)
                            .fontWeight(.semibold)
                    }

                    VStack(alignment: .leading, spacing: 4) {
                        Text("Duration")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        Text(durationString)
                            .font(.title2)
                            .fontWeight(.semibold)
                    }
                }
            }

            Divider()

            // Metadata
            VStack(alignment: .leading, spacing: 12) {
                Text("Metadata")
                    .font(.headline)
                    .foregroundColor(.secondary)

                VStack(alignment: .leading, spacing: 8) {
                    ProjectInfoRow(label: "Created", value: project.createdAt.formatted(date: .abbreviated, time: .shortened))
                    ProjectInfoRow(label: "Modified", value: project.modifiedAt.formatted(date: .abbreviated, time: .shortened))
                    ProjectInfoRow(label: "File Size", value: fileSizeString)
                    ProjectInfoRow(label: "Project ID", value: project.id.uuidString)
                }
            }

            Spacer()

            // Actions
            HStack {
                Spacer()
                Button("Done") {
                    dismiss()
                }
                .buttonStyle(.borderedProminent)
            }
        }
        .padding(24)
        .frame(width: 500, height: 500)
    }
}

struct ProjectInfoRow: View {
    let label: String
    let value: String
    
    var body: some View {
        HStack {
            Text(label)
                .foregroundColor(.secondary)
                .frame(width: 100, alignment: .leading)
            Text(value)
                .textSelection(.enabled)
        }
        .font(.system(size: 13))
    }
}
