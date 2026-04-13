//
//  CompactProjectBrowserView.swift
//  SaneVideo
//
//  Project browser for sidebar - shows all projects inline
//  Supports multi-select: Shift+Click/Arrow for range, Cmd+Click to toggle, Cmd+A for all
//

import SwiftUI
import AVFoundation

struct CompactProjectBrowserView: View {
    @Environment(AppState.self) var appState

    // Multi-select state
    @State private var selectedIds: Set<UUID> = []
    @State private var anchorId: UUID?  // For Shift+Arrow/Click range selection
    @State private var lastSelectedId: UUID?  // Track last selected for keyboard nav

    private var projects: [VideoProject] {
        appState.projectState.projects
    }

    private var selectedProjects: [VideoProject] {
        projects.filter { selectedIds.contains($0.id) }
    }

    var body: some View {
        VStack(spacing: 0) {
            headerView
            Divider()
            projectListView
        }
        .onAppear {
            if let currentId = appState.projectState.currentProject?.id {
                selectedIds = [currentId]
                anchorId = currentId
                lastSelectedId = currentId
            }
        }
    }

    // MARK: - Subviews

    @ViewBuilder
    private var headerView: some View {
        HStack {
            Text("Projects")
                .font(.headline)
            selectionCountLabel
            Spacer()
            newProjectMenu
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }

    @ViewBuilder
    private var selectionCountLabel: some View {
        if selectedIds.count > 1 {
            Text("(\(selectedIds.count) selected)")
                .font(.caption)
                .foregroundColor(.accentColor)
        } else {
            Text("(\(projects.count))")
                .font(.caption)
                .foregroundColor(Color.stone)
        }
    }

    @ViewBuilder
    private var newProjectMenu: some View {
        Menu {
            ForEach(ProjectTemplate.allTemplates) { template in
                Button {
                    appState.projectState.startNewProject(template: template)
                } label: {
                    Label(template.name, systemImage: template.icon)
                }
            }
        } label: {
            Image(systemName: "plus")
                .font(.system(size: 12, weight: .medium))
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .frame(width: 20, height: 20)
        .help("New Project")
    }

    @ViewBuilder
    private var projectListView: some View {
        ScrollView {
            LazyVStack(spacing: 8) {
                ForEach(projects) { project in
                    projectRow(for: project)
                }
            }
            .padding(.vertical, 8)
        }
        .focusable()
        .focusEffectDisabled()
        // Basic arrow keys
        .onKeyPress(.upArrow) { moveSingle(direction: -1); return .handled }
        .onKeyPress(.downArrow) { moveSingle(direction: 1); return .handled }
        .onKeyPress(.return) { openFirstSelected(); return .handled }
        .onKeyPress(.escape) { clearSelection(); return .handled }
        .onKeyPress(.delete) { if !selectedIds.isEmpty { deleteSelectedProjects() }; return .handled }
        // Hidden buttons for modifier shortcuts
        .background {
            Group {
                // Shift+Up - extend selection up
                Button("") { extendSelection(direction: -1) }
                    .keyboardShortcut(.upArrow, modifiers: [.shift])
                // Shift+Down - extend selection down
                Button("") { extendSelection(direction: 1) }
                    .keyboardShortcut(.downArrow, modifiers: [.shift])
                // Cmd+A - select all
                Button("") { selectAll() }
                    .keyboardShortcut("a", modifiers: [.command])
            }
            .opacity(0)
        }
    }

    @ViewBuilder
    private func projectRow(for project: VideoProject) -> some View {
        let isCurrent = appState.projectState.currentProject?.id == project.id
        CompactProjectRow(
            project: project,
            isCurrent: isCurrent,
            isSelected: selectedIds.contains(project.id),
            selectedCount: selectedIds.count,
            onSelect: { appState.projectState.openProject(project) },
            onRowClick: { modifiers in handleRowClick(project: project, modifiers: modifiers) },
            onBulkDelete: deleteSelectedProjects,
            onBulkDuplicate: duplicateSelectedProjects,
            onBulkShowInFinder: showSelectedInFinder
        )
    }

    private func openFirstSelected() {
        if let firstId = selectedIds.first,
           let project = projects.first(where: { $0.id == firstId }) {
            appState.projectState.openProject(project)
        }
    }

    private func clearSelection() {
        selectedIds.removeAll()
        anchorId = nil
        lastSelectedId = nil
    }

    // MARK: - Selection Logic

    private func handleRowClick(project: VideoProject, modifiers: EventModifiers) {
        if modifiers.contains(.command) {
            // Cmd+Click: Toggle individual selection
            if selectedIds.contains(project.id) {
                selectedIds.remove(project.id)
            } else {
                selectedIds.insert(project.id)
            }
            lastSelectedId = project.id
        } else if modifiers.contains(.shift), let anchor = anchorId {
            // Shift+Click: Range selection from anchor
            selectRange(from: anchor, to: project.id)
            lastSelectedId = project.id
        } else {
            // Plain click: Single selection
            selectedIds = [project.id]
            anchorId = project.id
            lastSelectedId = project.id
        }
    }

    private func moveSingle(direction: Int) {
        guard !projects.isEmpty else { return }

        let currentIndex: Int
        if let lastId = lastSelectedId,
           let idx = projects.firstIndex(where: { $0.id == lastId }) {
            currentIndex = idx
        } else {
            currentIndex = direction > 0 ? -1 : projects.count
        }

        let newIndex = max(0, min(projects.count - 1, currentIndex + direction))
        let newId = projects[newIndex].id

        selectedIds = [newId]
        anchorId = newId
        lastSelectedId = newId
    }

    private func extendSelection(direction: Int) {
        guard !projects.isEmpty else { return }

        // Set anchor if not set
        if anchorId == nil {
            anchorId = lastSelectedId ?? projects.first?.id
        }

        let currentIndex: Int
        if let lastId = lastSelectedId,
           let idx = projects.firstIndex(where: { $0.id == lastId }) {
            currentIndex = idx
        } else {
            currentIndex = direction > 0 ? -1 : projects.count
        }

        let newIndex = max(0, min(projects.count - 1, currentIndex + direction))
        let newId = projects[newIndex].id
        lastSelectedId = newId

        // Select range from anchor to new position
        if let anchor = anchorId {
            selectRange(from: anchor, to: newId)
        }
    }

    private func selectRange(from startId: UUID, to endId: UUID) {
        guard let startIdx = projects.firstIndex(where: { $0.id == startId }),
              let endIdx = projects.firstIndex(where: { $0.id == endId }) else {
            return
        }

        let range = min(startIdx, endIdx)...max(startIdx, endIdx)
        selectedIds = Set(projects[range].map { $0.id })
    }

    private func selectAll() {
        selectedIds = Set(projects.map { $0.id })
        anchorId = projects.first?.id
        lastSelectedId = projects.last?.id
    }

    // MARK: - Bulk Operations

    private func deleteSelectedProjects() {
        for id in selectedIds {
            NotificationCenter.default.post(
                name: NSNotification.Name("DeleteProject"),
                object: id
            )
        }
        selectedIds.removeAll()
    }

    private func duplicateSelectedProjects() {
        for id in selectedIds {
            NotificationCenter.default.post(
                name: NSNotification.Name("DuplicateProject"),
                object: id
            )
        }
    }

    private func showSelectedInFinder() {
        let urls = selectedProjects.map {
            ServiceContainer.shared.projectStore.fileURL(for: $0)
        }
        NSWorkspace.shared.activateFileViewerSelecting(urls)
    }
}

struct CompactProjectRow: View {
    let project: VideoProject
    let isCurrent: Bool
    let isSelected: Bool
    let selectedCount: Int
    let onSelect: () -> Void
    let onRowClick: (EventModifiers) -> Void
    let onBulkDelete: () -> Void
    let onBulkDuplicate: () -> Void
    let onBulkShowInFinder: () -> Void

    @State private var thumbnail: NSImage?

    private var firstClip: VideoClip? {
        project.timeline.tracks.first(where: { !$0.clips.isEmpty })?.clips.first
    }

    private var isMultiSelect: Bool {
        selectedCount > 1 && isSelected
    }

    var body: some View {
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
                        .foregroundColor(Color.stone)
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

                Text("\(project.clipCount) clip\(project.clipCount == 1 ? "" : "s")")
                    .font(.caption2)
                    .foregroundColor(Color.stone)
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
                .fill(isSelected ? Color.accentColor.opacity(0.2) : (isCurrent ? Color.accentColor.opacity(0.1) : Color.clear))
        }
        .overlay {
            if isSelected {
                RoundedRectangle(cornerRadius: 8)
                    .stroke(Color.accentColor, lineWidth: 2)
            }
        }
        .contentShape(Rectangle())
        .onTapGesture {
            // Detect modifiers from current event
            let modifiers = NSEvent.modifierFlags
            var eventModifiers: EventModifiers = []
            if modifiers.contains(.shift) { eventModifiers.insert(.shift) }
            if modifiers.contains(.command) { eventModifiers.insert(.command) }
            onRowClick(eventModifiers)
        }
        .simultaneousGesture(
            TapGesture(count: 2).onEnded {
                onSelect()
            }
        )
        .contextMenu {
            if isMultiSelect {
                // Multi-select context menu
                Text("\(selectedCount) projects selected")
                    .font(.caption)

                Divider()

                Button {
                    onBulkDuplicate()
                } label: {
                    Label("Duplicate \(selectedCount) Projects", systemImage: "doc.on.doc")
                }

                Button {
                    onBulkShowInFinder()
                } label: {
                    Label("Show in Finder", systemImage: "folder")
                }

                Divider()

                Button(role: .destructive) {
                    onBulkDelete()
                } label: {
                    Label("Delete \(selectedCount) Projects", systemImage: "trash")
                }
            } else {
                // Single item context menu
                Button {
                    onSelect()
                } label: {
                    Label("Open", systemImage: "arrow.right.circle")
                }

                Divider()

                Button {
                    NotificationCenter.default.post(
                        name: NSNotification.Name("RenameProject"),
                        object: project.id
                    )
                } label: {
                    Label("Rename...", systemImage: "pencil")
                }

                Button {
                    NotificationCenter.default.post(
                        name: NSNotification.Name("DuplicateProject"),
                        object: project.id
                    )
                } label: {
                    Label("Duplicate", systemImage: "doc.on.doc")
                }

                Button {
                    let url = ServiceContainer.shared.projectStore.fileURL(for: project)
                    NSWorkspace.shared.activateFileViewerSelecting([url])
                } label: {
                    Label("Show in Finder", systemImage: "folder")
                }

                Divider()

                Button(role: .destructive) {
                    NotificationCenter.default.post(
                        name: NSNotification.Name("DeleteProject"),
                        object: project.id
                    )
                } label: {
                    Label("Delete", systemImage: "trash")
                }
            }
        }
        .task {
            await loadThumbnail()
        }
    }

    private func loadThumbnail() async {
        guard let clip = firstClip, !clip.isMissing else { return }

        try? await Task.sleep(for: .milliseconds(100))

        let time = CMTime(seconds: clip.effectiveDuration.seconds * 0.25, preferredTimescale: 600)
        let originalTime = clip.originalTime(forEffectiveTime: time) ?? clip.trimStart

        let scaleFactor: CGFloat = 2.0
        let size = CGSize(width: 200 * scaleFactor, height: 128 * scaleFactor)

        let thumb = await Task.detached(priority: .utility) {
            await ServiceContainer.shared.thumbnailService.thumbnail(
                for: clip,
                time: originalTime,
                size: size
            )
        }.value

        if let thumb = thumb {
            await MainActor.run {
                self.thumbnail = thumb.value
            }
        }
    }
}
