// Project browser for sidebar - shows all projects inline
// Supports multi-select: Shift+Click/Arrow for range, Cmd+Click to toggle, Cmd+A for all

import SwiftUI
import AVFoundation

struct CompactProjectBrowserView: View {
    @Environment(AppState.self) var appState

    @State private var selectedIds: Set<UUID> = []
    @State private var anchorId: UUID?  // For Shift+Arrow/Click range selection
    @State private var lastSelectedId: UUID?  // Track last selected for keyboard nav

    private var projects: [VideoProject] {
        appState.projectState.projects
    }

    private var dateGroups: [(title: String, projects: [VideoProject])] {
        let calendar = Calendar.current
        let buckets: [(String, (Date) -> Bool)] = [
            ("Today", { calendar.isDateInToday($0) }),
            ("Yesterday", { calendar.isDateInYesterday($0) }),
            ("Earlier", { !calendar.isDateInToday($0) && !calendar.isDateInYesterday($0) })
        ]
        return buckets.compactMap { title, matches in
            let items = projects.filter { matches($0.modifiedAt) }
            return items.isEmpty ? nil : (title, items)
        }
    }

    private var selectedProjects: [VideoProject] {
        projects.filter { selectedIds.contains($0.id) }
    }

    var body: some View {
        VStack(spacing: 0) {
            headerView
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
            selectionCountLabel
            Spacer()
            newProjectMenu
        }
        .padding(.horizontal, 12)
        .padding(.bottom, 6)
    }

    @ViewBuilder
    private var selectionCountLabel: some View {
        if selectedIds.count > 1 {
            Text("\(selectedIds.count) selected")
                .font(.system(size: 13))
                .foregroundColor(Theme.Colors.accent)
        } else {
            Text("\(projects.count) project\(projects.count == 1 ? "" : "s")")
                .font(.system(size: 13))
                .foregroundStyle(Theme.Colors.textPrimary.opacity(0.7))
        }
    }

    @ViewBuilder
    private var newProjectMenu: some View {
        Button {
            appState.projectState.startNewProject()
        } label: {
            Image(systemName: "plus")
                .font(.system(size: 12, weight: .medium))
        }
        .buttonStyle(.borderless)
        .frame(width: 20, height: 20)
        .help("New Project")
    }

    @ViewBuilder
    private var projectListView: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 2) {
                ForEach(dateGroups, id: \.title) { group in
                    Text(group.title)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(Theme.Colors.textPrimary.opacity(0.7))
                        .padding(.horizontal, 12)
                        .padding(.top, 10)
                        .padding(.bottom, 2)
                    ForEach(group.projects) { project in
                        projectRow(for: project)
                    }
                }
            }
            .padding(.horizontal, 6)
            .padding(.bottom, 8)
        }
        .focusable()
        .focusEffectDisabled()
        .onKeyPress(.upArrow) { moveSingle(direction: -1); return .handled }
        .onKeyPress(.downArrow) { moveSingle(direction: 1); return .handled }
        .onKeyPress(.return) { openFirstSelected(); return .handled }
        .onKeyPress(.escape) { clearSelection(); return .handled }
        .onKeyPress(.delete) { if !selectedIds.isEmpty { deleteSelectedProjects() }; return .handled }
        // Hidden buttons for modifier shortcuts
        .background {
            Group {
                Button("") { extendSelection(direction: -1) }
                    .keyboardShortcut(.upArrow, modifiers: [.shift])
                Button("") { extendSelection(direction: 1) }
                    .keyboardShortcut(.downArrow, modifiers: [.shift])
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

    private static func when(_ date: Date) -> String {
        let calendar = Calendar.current
        if calendar.isDateInToday(date) || calendar.isDateInYesterday(date) {
            return date.formatted(date: .omitted, time: .shortened)
        }
        return date.formatted(.dateTime.month(.abbreviated).day())
    }

    private var firstClip: VideoClip? {
        project.timeline.tracks.first(where: { !$0.clips.isEmpty })?.clips.first
    }

    private var isMultiSelect: Bool {
        selectedCount > 1 && isSelected
    }

    var body: some View {
        HStack(spacing: 10) {
            ZStack {
                if let thumbnail = thumbnail {
                    Image(nsImage: thumbnail)
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                } else {
                    RoundedRectangle(cornerRadius: 6)
                        .fill(Theme.Colors.accent.opacity(0.2))
                    Image(systemName: firstClip == nil ? "film.stack" : "photo")
                        .font(.system(size: 16))
                        .foregroundColor(Color.stone)
                }
            }
            .frame(width: 50, height: 32)
            .clipShape(RoundedRectangle(cornerRadius: 6))

            VStack(alignment: .leading, spacing: 2) {
                Text(project.name)
                    .font(.system(size: 14, weight: isCurrent ? .semibold : .regular))
                    .foregroundStyle(Theme.Colors.textPrimary)
                    .lineLimit(1)
                    .truncationMode(.middle)

                Text("\(Self.when(project.modifiedAt)) · \(project.clipCount) clip\(project.clipCount == 1 ? "" : "s")")
                    .font(.system(size: 13))
                    .foregroundStyle(Theme.Colors.textPrimary.opacity(0.7))
            }

            Spacer(minLength: 0)
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 6)
        .background {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(isSelected ? Theme.Colors.accent.opacity(0.35) : (isCurrent ? Color.white.opacity(0.06) : Color.clear))
        }
        .contentShape(Rectangle())
        .onTapGesture {
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
