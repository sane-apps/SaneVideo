import AVFoundation
import Combine
import Foundation
import SwiftUI

@MainActor
@Observable
class ProjectState {
    // MARK: - Published Properties

    var currentProject: VideoProject?
    var projects: [VideoProject] = []
    var recentlyAddedClip: VideoClip?
    var showingImportPicker = false

    // MARK: - Processing State (Transaction-Based)

    /// Active processing transactions; several operations can run at once, each with its own ID.
    internal var processingTransactions: Set<UUID> = []

    var hasActiveTransactions: Bool {
        !processingTransactions.isEmpty
    }

    /// Computed from transactions; kept for older callers.
    var isProcessing: Bool {
        get {
            !processingTransactions.isEmpty
        }
        set {
            // Setting false clears all transactions; setting true opens a temporary one for older callers.
            if !newValue {
                processingTransactions.removeAll()
            } else if processingTransactions.isEmpty {
                _ = beginTransaction()
            }
        }
    }

    var processingProgress: Double = 0.0
    var processingStatus: String?

    /// Progress (0.0-1.0) per transaction ID.
    internal var transactionProgress: [UUID: Double] = [:]

    /// True during the first project load, so the UI does not read an empty project list at startup.
    var isLoadingProjects = true

    private var currentScopeSession: ProjectFileManager.SecurityScopeSession?

    // nonisolated(unsafe) required for deinit access
    @ObservationIgnored nonisolated(unsafe) var currentProcessingTask: Task<Void, Error>?

    func cancelCurrentOperation() {
        currentProcessingTask?.cancel()
        currentProcessingTask = nil
        cancelAllTransactions()
        AppLogger.project.info("Operation cancelled by user")
        ServiceContainer.shared.toastManager.show("Operation cancelled", type: .info)
    }

    // MARK: - Smart Features State

    var magicFixOptions = MagicFixOptions()

    // MARK: - Save Debounce

    // nonisolated(unsafe) required for deinit access
    /// Debounce save operations to avoid duplicate saves from rapid changes
    @ObservationIgnored nonisolated(unsafe) private var pendingSaveTask: Task<Void, Never>?
    private var lastSaveTime: Date = .distantPast

    // MARK: - Undo Manager (SwiftUI's built-in)

    var undoManager: UndoManager? {
        didSet {
            // Turn off run-loop grouping so each registerUndo is its own step; use beginUndoGroup/endUndoGroup to group.
            undoManager?.groupsByEvent = false

            // Cap undo depth: each step copies the whole project, which gets large with 100+ clips.
            undoManager?.levelsOfUndo = 30
        }
    }

    // MARK: - Undo Helper

    func registerUndo(_ actionName: String) {
        // Inside an undo group the snapshot taken when it began already covers this step.
        guard undoGroupDepth == 0 else { return }
        guard let project = currentProject else { return }
        registerUndoStep(restoring: project, named: actionName)
    }

    private func registerUndoStep(restoring project: VideoProject, named actionName: String) {
        guard let undoManager = undoManager else { return }

        // With groupsByEvent off, each registration needs its own explicit group.
        undoManager.beginUndoGrouping()

        // Capture the whole project (a value type) for undo.
        undoManager.registerUndo(withTarget: self) { target in
            MainActor.assumeIsolated {
                target.restoreProjectState(project)
            }
        }
        undoManager.setActionName(actionName)

        undoManager.endUndoGrouping()
    }

    // Long operations such as Clean Up span awaits. Holding an NSUndoManager group open that long made
    // Undo raise ("undo was called with too many nested undo groups"), so a group is a snapshot taken
    // when it begins and one undo step registered when it ends.
    @ObservationIgnored private var undoGroupDepth = 0
    @ObservationIgnored private var undoGroupSnapshot: VideoProject?
    @ObservationIgnored private var undoGroupName = ""
    // Snapshots replaced by an undo during the group, so the matching redo can put them back.
    @ObservationIgnored private var undoGroupSnapshotsBeforeUndo: [VideoProject] = []

    /// Makes every change until endUndoGroup() one undo step.
    func beginUndoGroup(_ groupName: String) {
        if undoGroupDepth == 0 {
            undoGroupSnapshot = currentProject
            undoGroupName = groupName
            undoGroupSnapshotsBeforeUndo = []
        }
        undoGroupDepth += 1
    }

    func endUndoGroup() {
        guard undoGroupDepth > 0 else { return }
        undoGroupDepth -= 1
        guard undoGroupDepth == 0, let snapshot = undoGroupSnapshot else { return }
        undoGroupSnapshot = nil
        undoGroupSnapshotsBeforeUndo = []
        guard currentProject?.id == snapshot.id else { return }
        registerUndoStep(restoring: snapshot, named: undoGroupName)
    }

    /// Undo or redo during a group: undoing the group afterwards should return to the user's state, not to
    /// before their undo, and not keep group changes a redo brought back.
    private func moveUndoGroupSnapshot(to restored: VideoProject) {
        guard undoGroupDepth > 0, let snapshot = undoGroupSnapshot, snapshot.id == restored.id else { return }
        if undoManager?.isRedoing == true, let previous = undoGroupSnapshotsBeforeUndo.popLast() {
            // Redoing an undo made during the group: that redo state can hold the group's own changes.
            undoGroupSnapshot = previous
        } else {
            if undoManager?.isUndoing == true {
                undoGroupSnapshotsBeforeUndo.append(snapshot)
            }
            undoGroupSnapshot = restored
        }
    }

    private func restoreProjectState(_ project: VideoProject) {
        // Never let a snapshot from another project replace the open one; that overwrote a project's clips when undo history survived a project switch.
        guard project.id == currentProject?.id else {
            AppLogger.project.warning("Ignoring undo snapshot from a different project")
            return
        }
        // Capture current state for Redo
        if let current = currentProject {
            undoManager?.registerUndo(withTarget: self) { target in
                MainActor.assumeIsolated {
                    target.restoreProjectState(current)
                }
            }
        }

        // Recalculate startTimes after undo/redo to ensure consistency
        var timeline = project.timeline
        recalculateStartTimes(in: &timeline)
        timeline.updateDuration()

        if !validateTimelineState(timeline) {
            AppLogger.project.error("Timeline state invalid after undo/redo, attempting to fix")
            recalculateStartTimes(in: &timeline)
            timeline.updateDuration()

            if !validateTimelineState(timeline) {
                AppLogger.project.error("Failed to fix timeline state after undo/redo")
                ServiceContainer.shared.toastManager.show("Timeline state invalid after undo/redo", type: .error)
            }
        }

        var updatedProject = project
        updatedProject.timeline = timeline

        moveUndoGroupSnapshot(to: updatedProject)

        updateCurrentProject(updatedProject)
        saveProject(updatedProject)
        AppLogger.project.info("Undo/Redo performed: Restored project state")
        ServiceContainer.shared.toastManager.show("Restored State")
    }

    // MARK: - Internal Properties

    private let projectStore: ProjectStoreProtocol

    // Debounce state for preventing duplicate imports (internal for use in extensions)
    var lastImportedURL: URL?
    var lastImportTime: Date?

    // MARK: - Caption Positioning

    func updateCaptionOffset(_ offset: CGSize) {
        guard var project = currentProject else { return }

        // Register undo only on drag end, which is when this is usually called.
        registerUndo("Move Captions")

        project.updateCaptionOffset(offset)

        currentProject = project
        saveProject(project)
    }

    func updateCaptionFont(_ fontName: String?) {
        guard var project = currentProject else { return }

        registerUndo("Change Font")

        project.updateCaptionFont(fontName)

        currentProject = project
        saveProject(project)
    }

    // MARK: - Initialization

    init(projectStore: ProjectStoreProtocol? = nil) {
        self.projectStore = projectStore ?? ServiceContainer.shared.projectStore

        // Skip auto-loading in UI tests to prevent race conditions with bootstrap
        let isTesting = UserDefaults.standard.bool(forKey: "ui_testing") ||
                        ProcessInfo.processInfo.arguments.contains("-ui_testing") ||
                        TestEnvironment.shouldOpenEditor

        if !isTesting {
            Task {
                await loadProjects()
            }
        } else {
            isLoadingProjects = false
        }
    }

    // MARK: - Project Management

    /// Generate a unique project name following Apple convention: "Untitled Project", "Untitled Project 2", etc.
    func generateUniqueProjectName(baseName: String = "Untitled Project") -> String {
        let existingNames = Set(projects.map { $0.name })

        // Apple convention: the first document has no number.
        if !existingNames.contains(baseName) {
            return baseName
        }

        var number = 2
        while existingNames.contains("\(baseName) \(number)") {
            number += 1
        }

        return "\(baseName) \(number)"
    }

    func startNewProject(named name: String? = nil) {
        var project = VideoProject()
        project.name = name ?? generateUniqueProjectName()
        updateCurrentProject(project)
        projects.insert(project, at: 0)
        saveProject(project)
        AppLogger.project.info("Started new project \(project.id)")
    }

    func openProject(_ project: VideoProject) {
        updateCurrentProject(project)
    }

    func openProjectFile(at url: URL) throws {
        let data = try Data(contentsOf: url)
        let project = try JSONDecoder().decode(VideoProject.self, from: data)

        if let existingIndex = projects.firstIndex(where: { $0.id == project.id }) {
            projects[existingIndex] = project
        } else {
            projects.insert(project, at: 0)
        }

        updateCurrentProject(project)
        AppLogger.project.info("Opened project file: \(url.lastPathComponent)")
    }

    func loadProjects() async {
        // Prevent loading during UI tests to avoid race conditions and file access issues
        let isTesting = UserDefaults.standard.bool(forKey: "ui_testing") ||
                        UserDefaults.standard.string(forKey: "UI_TESTING") != nil ||
                        ProcessInfo.processInfo.environment["UI_TESTING"] != nil ||
                        ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil ||
                        ProcessInfo.processInfo.arguments.contains("-ui_testing") ||
                        TestEnvironment.shouldOpenEditor

        if isTesting {
            AppLogger.project.info("🧪 ProjectState: Skipping loadProjects (UI Test Environment)")
            isLoadingProjects = false
            return
        }

        defer { isLoadingProjects = false }
        do {
            let loadedProjects = try await projectStore.loadProjects()
            projects = loadedProjects.sorted(by: { $0.createdAt > $1.createdAt })
            AppLogger.project.info("Loaded \(projects.count) projects")

            if let mostRecent = projects.first {
                updateCurrentProject(mostRecent)
            } else {
                startNewProject()
            }
        } catch {
            AppLogger.project.error("Failed to load projects: \(error)")
            startNewProject()
        }
    }

    func getProjectFileURL(_ project: VideoProject) -> URL {
        return projectStore.fileURL(for: project)
    }

    func saveProject(_ project: VideoProject) {
        // Keep the sidebar list in step with what is saved (clip counts went stale).
        if let index = projects.firstIndex(where: { $0.id == project.id }) {
            projects[index] = project
        }
        // Chain after the previous save so an older save cannot finish after a newer one.
        let previousTask = pendingSaveTask

        let now = Date()
        let timeSinceLastSave = now.timeIntervalSince(lastSaveTime)
        let shouldDebounce = timeSinceLastSave < 0.1 // 100ms window

        pendingSaveTask = Task {
            if let previous = previousTask {
                _ = await previous.value
            }

            guard !Task.isCancelled else { return }

            if shouldDebounce {
                try? await Task.sleep(for: .milliseconds(100))
                guard !Task.isCancelled else { return }
            }

            do {
                try await projectStore.saveProject(project)
                await MainActor.run {
                    self.lastSaveTime = Date()
                }
                AppLogger.project.info("✅ Saved project \(project.name)")
            } catch {
                guard !Task.isCancelled else { return }
                AppLogger.project.error("❌ Failed to save project: \(error)")
                await MainActor.run {
                    // A failed save can lose data, so tell the user.
                    ServiceContainer.shared.errorPresenter.present(AppError.projectSaveFailed(error))
                    ServiceContainer.shared.toastManager.show("⚠️ Failed to save project. Changes may be lost.", type: .error)
                }
            }
        }
    }

    /// Waits until every queued save has reached disk (each save waits for the one before it).
    func flushPendingSaves() async {
        await pendingSaveTask?.value
    }

    /// Update playback state (time, scroll, zoom) and save
    func updatePlaybackState(currentTime: Double, scrollOffset: CGFloat, zoomLevel: CGFloat) {
        guard var project = currentProject else { return }
        project.updatePlaybackState(time: currentTime, scroll: scrollOffset, zoom: zoomLevel)
        currentProject = project

        saveProject(project)
    }

    /// Update zoom level in memory (persisted on autosave)
    func updateZoomLevel(_ level: CGFloat) {
        guard var project = currentProject else { return }
        project.zoomLevel = level
        currentProject = project
    }

    func updateCaptionStyle(_ style: CaptionStyle) {
        guard var project = currentProject else { return }

        registerUndo("Change Caption Style")

        project.captionStyleName = style.name
        currentProject = project
        saveProject(project)
        ServiceContainer.shared.toastManager.show("Caption Style: \(style.name)")
        AppLogger.project.info("Updated caption style to \(style.name)")
    }

    func updateSpeakerNotes(_ notes: SpeakerNotes) {
        guard var project = currentProject else { return }
        project.updateSpeakerNotes(notes)
        currentProject = project
        saveProject(project)
    }

    func renameProject(_ newName: String) {
        guard var project = currentProject else { return }
        guard !newName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }

        registerUndo("Rename Project")

        project.rename(newName)
        currentProject = project
        saveProject(project)

        if let index = projects.firstIndex(where: { $0.id == project.id }) {
            projects[index] = project
        }

        AppLogger.project.info("Renamed project to '\(newName)'")
        ServiceContainer.shared.toastManager.show("Project Renamed")
    }

    func duplicateProject(_ project: VideoProject) {
        // id and createdAt are let constants, so build a new project.
        var duplicate = VideoProject(
            id: UUID(),
            name: "\(project.name) Copy",
            createdAt: Date()
        )
        
        duplicate.timeline = project.timeline
        duplicate.modifiedAt = Date()
        duplicate.captionStyleName = project.captionStyleName
        duplicate.captionOffset = project.captionOffset
        duplicate.captionFontName = project.captionFontName
        duplicate.speakerNotes = project.speakerNotes
        
        duplicate.currentTime = 0.0
        duplicate.scrollOffset = 0.0
        duplicate.zoomLevel = 1.0
        
        projects.insert(duplicate, at: 0)
        
        saveProject(duplicate)
        
        AppLogger.project.info("Duplicated project '\(project.name)' to '\(duplicate.name)'")
        ServiceContainer.shared.toastManager.show("Project Duplicated")
    }

    func deleteProject(_ project: VideoProject) {
        if currentProject?.id == project.id {
            AppLogger.project.warning("⚠️ Attempted to delete currently active project")
            // The delete still proceeds and switches to another project below.
        }

        Task {
            do {
                try await projectStore.deleteProject(project)

                await MainActor.run {
                    self.projects.removeAll { $0.id == project.id }

                    if self.currentProject?.id == project.id {
                        if let next = self.projects.first {
                            self.updateCurrentProject(next)
                        } else {
                            self.startNewProject()
                        }
                    }

                    AppLogger.project.info("Deleted project \(project.name)")
                    ServiceContainer.shared.toastManager.show("Project Deleted")
                }
            } catch {
                await MainActor.run {
                    AppLogger.project.error("Failed to delete project: \(error)")
                    ServiceContainer.shared.errorPresenter.present(AppError.projectSaveFailed(error))
                }
            }
        }
    }

    // MARK: - Bulk Project Operations

    func deleteProjects(_ projectIds: Set<UUID>) {
        let projectsToDelete = projects.filter { projectIds.contains($0.id) }
        guard !projectsToDelete.isEmpty else { return }

        // If current project is being deleted, switch first
        let needsSwitch = projectIds.contains(currentProject?.id ?? UUID())

        Task {
            var deletedCount = 0
            var errors: [Error] = []

            for project in projectsToDelete {
                do {
                    try await projectStore.deleteProject(project)
                    deletedCount += 1
                } catch {
                    errors.append(error)
                    AppLogger.project.error("Failed to delete project \(project.name): \(error)")
                }
            }

            await MainActor.run {
                self.projects.removeAll { projectIds.contains($0.id) }

                if needsSwitch {
                    if let next = self.projects.first {
                        self.updateCurrentProject(next)
                    } else {
                        self.startNewProject()
                    }
                }

                if errors.isEmpty {
                    ServiceContainer.shared.toastManager.show("\(deletedCount) project\(deletedCount == 1 ? "" : "s") deleted")
                } else {
                    ServiceContainer.shared.toastManager.show(
                        "Deleted \(deletedCount) of \(projectsToDelete.count) projects",
                        type: .error
                    )
                }

                AppLogger.project.info("Bulk deleted \(deletedCount) projects")
            }
        }
    }

    /// Delete all projects and start fresh
    func clearAllProjects() {
        let allProjectIds = Set(projects.map { $0.id })
        guard !allProjectIds.isEmpty else { return }

        Task {
            var deletedCount = 0

            for project in projects {
                do {
                    try await projectStore.deleteProject(project)
                    deletedCount += 1
                } catch {
                    AppLogger.project.error("Failed to delete project \(project.name): \(error)")
                }
            }

            await MainActor.run {
                self.projects.removeAll()
                self.startNewProject()
                ServiceContainer.shared.toastManager.show("All projects cleared")
                AppLogger.project.info("Cleared all \(deletedCount) projects")
            }
        }
    }

    // MARK: - Clip Management

    // MARK: - Notification Names
    func showImportPicker() {
        showingImportPicker = true
    }

    /// Check if a track is locked (helper for guarding operations)
    func isTrackLocked(for clip: VideoClip) -> Bool {
        guard let project = currentProject else { return false }
        for track in project.timeline.tracks where track.type == .video {
            if track.clips.contains(where: { $0.id == clip.id }) {
                return track.isLocked
            }
        }
        return false
    }

    // MARK: - Internal Helpers

    func updateCurrentProject(_ project: VideoProject?) {
        // Undo history belongs to one project.
        if project?.id != currentProject?.id {
            undoManager?.removeAllActions()
        }
        // Stop the old security scope session first so switching projects does not leak it.
        if let existingSession = currentScopeSession {
            existingSession.stop()
            currentScopeSession = nil
        }

        if let project = project {
            // Hydrate project to resolve stale bookmarks before ensuring access
            let (hydratedProject, needsSave) = ServiceContainer.shared.projectFileManager.hydrateProject(project)
            currentProject = hydratedProject

            if needsSave {
                AppLogger.project.info("Bookmarks updated during hydration, saving project...")
                saveProject(hydratedProject)
            }

            currentScopeSession = ServiceContainer.shared.projectFileManager.enterSecurityScope(for: hydratedProject)

            // Register clip URLs with VolumeMonitor to track external drive availability
            let clipURLs = hydratedProject.timeline.tracks.flatMap { $0.clips }.map { $0.url }
            VolumeMonitor.shared.registerClipURLs(clipURLs)
        } else {
            currentProject = nil
            // Session already stopped above
            VolumeMonitor.shared.clearTrackedClips()
        }
    }
}

// MARK: - Notification Names

extension Notification.Name {
    /// Posted when a clip is added to the timeline
    /// Object: VideoProject that was updated
    static let clipAddedToTimeline = Notification.Name("clipAddedToTimeline")

    /// Posted when a clip is updated, for example relinked to a new file.
    /// Object: VideoProject that was updated
    static let clipUpdated = Notification.Name("clipUpdated")
}
