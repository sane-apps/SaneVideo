//
//  ProjectState.swift
//  SaneVideo
//
//  Created by SaneVideo Refactor
//

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

    /// Active processing transactions
    /// Multiple operations can run concurrently, each with its own transaction ID
    internal var processingTransactions: Set<UUID> = []

    /// Check if processing is active (computed from transaction set)
    /// This is the new way to check if processing is happening
    var hasActiveTransactions: Bool {
        !processingTransactions.isEmpty
    }

    /// Processing state (computed from transactions for backward compatibility)
    /// This property is now computed to maintain compatibility with existing code
    /// while transitioning to the transaction system
    var isProcessing: Bool {
        get {
            !processingTransactions.isEmpty
        }
        set {
            // Legacy setter support: if setting to false, clear all transactions
            // If setting to true, create a temporary transaction (for backward compatibility)
            if !newValue {
                processingTransactions.removeAll()
            } else if processingTransactions.isEmpty {
                // Create a temporary transaction for legacy code that sets isProcessing = true
                // This will be cleaned up when the code is migrated to use transactions
                _ = beginTransaction()
            }
        }
    }

    var processingProgress: Double = 0.0
    var processingStatus: String?

    /// Per-transaction progress tracking
    /// Maps transaction ID to progress (0.0-1.0)
    internal var transactionProgress: [UUID: Double] = [:]

    /// CRITICAL FIX: Track if initial project load is in progress
    /// UI should check this to avoid accessing empty project list during startup
    var isLoadingProjects = true

    private var currentScopeSession: ProjectFileManager.SecurityScopeSession?

    // nonisolated(unsafe) required for deinit access
    /// Current processing task for cancellation support
    @ObservationIgnored nonisolated(unsafe) var currentProcessingTask: Task<Void, Error>?

    // P0 FIX: Cancel current operation
    func cancelCurrentOperation() {
        currentProcessingTask?.cancel()
        currentProcessingTask = nil
        cancelAllTransactions() // Use transaction system
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
            // CRITICAL: Disable automatic run-loop grouping so each registerUndo
            // call becomes its own undo step. Without this, multiple operations
            // in the same run loop pass would be grouped into one undo action.
            // We use explicit beginUndoGroup/endUndoGroup when we want grouping.
            undoManager?.groupsByEvent = false

            // MEMORY SAFETY: Limit undo stack depth to prevent unbounded memory growth.
            // Each undo captures the entire project state (value type copy), so
            // with large projects (100+ clips) this can consume significant memory.
            // 30 levels provides good undo history while maintaining reasonable memory use.
            undoManager?.levelsOfUndo = 30
        }
    }

    // MARK: - Undo Helper

    func registerUndo(_ actionName: String) {
        guard let project = currentProject else { return }
        guard let undoManager = undoManager else { return }

        // CRITICAL: With groupsByEvent = false, each undo registration must be
        // wrapped in its own explicit group. This ensures each operation becomes
        // a separate undo step that can be undone individually.
        undoManager.beginUndoGrouping()

        // Capture the ENTIRE project state (value type) for robust undo
        undoManager.registerUndo(withTarget: self) { target in
            MainActor.assumeIsolated {
                target.restoreProjectState(project)
            }
        }
        undoManager.setActionName(actionName)

        undoManager.endUndoGrouping()
    }

    /// Begin an undo group for multiple related operations
    /// All subsequent registerUndo calls will be grouped until endUndoGroup is called
    func beginUndoGroup(_ groupName: String) {
        undoManager?.beginUndoGrouping()
        // Register initial state before group starts
        if let project = currentProject {
            undoManager?.registerUndo(withTarget: self) { target in
                MainActor.assumeIsolated {
                    target.restoreProjectState(project)
                }
            }
            undoManager?.setActionName(groupName)
        }
    }

    /// End an undo group
    func endUndoGroup() {
        undoManager?.endUndoGrouping()
    }

    private func restoreProjectState(_ project: VideoProject) {
        // Capture current state for Redo
        if let current = currentProject {
            undoManager?.registerUndo(withTarget: self) { target in
                MainActor.assumeIsolated {
                    target.restoreProjectState(current)
                }
            }
        }

        // CRITICAL FIX: Recalculate startTimes after undo/redo to ensure consistency
        var timeline = project.timeline
        recalculateStartTimes(in: &timeline)
        timeline.updateDuration()

        // CRITICAL FIX: Validate timeline state after undo/redo
        if !validateTimelineState(timeline) {
            AppLogger.project.error("Timeline state invalid after undo/redo, attempting to fix")
            // Attempt to fix by recalculating
            recalculateStartTimes(in: &timeline)
            timeline.updateDuration()

            if !validateTimelineState(timeline) {
                AppLogger.project.error("Failed to fix timeline state after undo/redo")
                ServiceContainer.shared.toastManager.show("Timeline state invalid after undo/redo", type: .error)
            }
        }

        var updatedProject = project
        updatedProject.timeline = timeline

        // Restore
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

        // Register undo ONLY on drag end (when this is typically called)
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
                        UserDefaults.standard.bool(forKey: "open_editor") ||
                        ProcessInfo.processInfo.arguments.contains("-ui_testing")

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

        // First, try without a number (Apple convention: first doc has no number)
        if !existingNames.contains(baseName) {
            return baseName
        }

        // Find the next available number (starting at 2, per Apple convention)
        var number = 2
        while existingNames.contains("\(baseName) \(number)") {
            number += 1
        }

        return "\(baseName) \(number)"
    }

    func startNewProject(template: ProjectTemplate? = nil) {
        var project = VideoProject()

        // Apply template settings if provided
        if let template = template {
            project.name = template.name
            // Note: Aspect ratio and export settings are applied at export time
            // Caption style can be set here
            project.captionStyleName = template.defaultCaptionStyle
            project.presentationPreset = template.defaultPresentationPreset
            project.demoPackSettings = template.defaultPresentationPreset.recommendedDemoPackSettings
            project.publishMetadata = .default(for: template.name)
            project.publishMetadata.subtitle = template.description
        } else {
            // Generate unique name following Apple convention
            project.name = generateUniqueProjectName()
            project.publishMetadata = .default(for: project.name)
        }

        updateCurrentProject(project)
        projects.insert(project, at: 0)
        saveProject(project)
        AppLogger.project.info("Started new project \(project.id) with template: \(template?.name ?? "none")")
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
                        UserDefaults.standard.bool(forKey: "open_editor") ||
                        UserDefaults.standard.string(forKey: "UI_TESTING") != nil ||
                        ProcessInfo.processInfo.environment["UI_TESTING"] != nil ||
                        ProcessInfo.processInfo.environment["OPEN_EDITOR"] != nil ||
                        ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil ||
                        ProcessInfo.processInfo.arguments.contains("-ui_testing") ||
                        ProcessInfo.processInfo.arguments.contains("-open_editor")

        if isTesting {
            AppLogger.project.info("🧪 ProjectState: Skipping loadProjects (UI Test Environment)")
            isLoadingProjects = false
            return
        }

        defer { isLoadingProjects = false }
        do {
            // 1. Load existing projects from disk
            let loadedProjects = try await projectStore.loadProjects()
            projects = loadedProjects.sorted(by: { $0.createdAt > $1.createdAt })
            AppLogger.project.info("Loaded \(projects.count) projects")

            // 2. Set current project
            if let mostRecent = projects.first {
                updateCurrentProject(mostRecent)
            } else {
                startNewProject()
            }
        } catch {
            AppLogger.project.error("Failed to load projects: \(error)")
            // Fallback to new project
            startNewProject()
        }
    }

    /// Get the file URL for the current project storage
    func getProjectFileURL(_ project: VideoProject) -> URL {
        return projectStore.fileURL(for: project)
    }

    func saveProject(_ project: VideoProject) {
        // CRITICAL: Wait for previous save to complete before starting new one
        // This prevents race conditions where last save might complete after new one
        let previousTask = pendingSaveTask

        // If last save was very recent, debounce with a small delay
        let now = Date()
        let timeSinceLastSave = now.timeIntervalSince(lastSaveTime)
        let shouldDebounce = timeSinceLastSave < 0.1 // 100ms window

        pendingSaveTask = Task {
            // CRITICAL: Wait for previous save to complete (if any)
            // This ensures saves happen in order and prevents data loss
            if let previous = previousTask {
                _ = await previous.value
            }

            // Check if we were cancelled while waiting
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
                    // CRITICAL: Show error to user - save failure means potential data loss
                    ServiceContainer.shared.errorPresenter.present(AppError.projectSaveFailed(error))
                    ServiceContainer.shared.toastManager.show("⚠️ Failed to save project. Changes may be lost.", type: .error)
                }
            }
        }
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

    /// Update the caption style for the current project
    func updateCaptionStyle(_ style: CaptionStyle) {
        guard var project = currentProject else { return }

        registerUndo("Change Caption Style")

        project.captionStyleName = style.name
        currentProject = project
        saveProject(project)
        ServiceContainer.shared.toastManager.show("Caption Style: \(style.name)")
        AppLogger.project.info("Updated caption style to \(style.name)")
    }

    func updatePresentationPreset(_ preset: PresentationPreset) {
        guard var project = currentProject else { return }
        project.updatePresentationPreset(preset)
        currentProject = project
        saveProject(project)
    }

    func updateSpeakerNotes(_ notes: SpeakerNotes) {
        guard var project = currentProject else { return }
        project.updateSpeakerNotes(notes)
        currentProject = project
        saveProject(project)
    }

    func updateChapterMarkers(_ markers: [ChapterMarker]) {
        guard var project = currentProject else { return }
        project.updateChapterMarkers(markers)
        currentProject = project
        saveProject(project)
    }

    func updateWorkflowBrief(_ brief: WorkflowBrief) {
        guard var project = currentProject else { return }
        project.updateWorkflowBrief(brief)
        currentProject = project
        saveProject(project)
    }

    func updateCommentaryPlanItems(_ items: [CommentaryPlanItem]) {
        guard var project = currentProject else { return }
        project.updateCommentaryPlanItems(items)
        currentProject = project
        saveProject(project)
    }

    func updateCommentaryMarkers(_ markers: [CommentaryMarker]) {
        guard var project = currentProject else { return }
        project.updateCommentaryMarkers(markers)
        currentProject = project
        saveProject(project)
    }

    func updateDemoPackSettings(_ settings: DemoPackSettings) {
        guard var project = currentProject else { return }
        project.updateDemoPackSettings(settings)
        currentProject = project
        saveProject(project)
    }

    func updatePublishMetadata(_ metadata: PublishMetadata) {
        guard var project = currentProject else { return }
        project.updatePublishMetadata(metadata)
        currentProject = project
        saveProject(project)
    }

    func renameProject(_ newName: String) {
        guard var project = currentProject else { return }
        guard !newName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }

        registerUndo("Rename Project")

        let oldName = project.name
        project.rename(newName)
        if project.publishMetadata.title.isEmpty || project.publishMetadata.title == oldName {
            project.publishMetadata.title = newName
        }
        currentProject = project
        saveProject(project)

        // Also update in the projects list if present
        if let index = projects.firstIndex(where: { $0.id == project.id }) {
            projects[index] = project
        }

        AppLogger.project.info("Renamed project from '\(oldName)' to '\(newName)'")
        ServiceContainer.shared.toastManager.show("Project Renamed")
    }

    func duplicateProject(_ project: VideoProject) {
        // Create a new project with copied data (id and createdAt are let constants)
        var duplicate = VideoProject(
            id: UUID(),
            name: "\(project.name) Copy",
            createdAt: Date()
        )
        
        // Copy all mutable properties
        duplicate.timeline = project.timeline
        duplicate.modifiedAt = Date()
        duplicate.captionStyleName = project.captionStyleName
        duplicate.captionOffset = project.captionOffset
        duplicate.captionFontName = project.captionFontName
        duplicate.presentationPreset = project.presentationPreset
        duplicate.speakerNotes = project.speakerNotes
        duplicate.chapterMarkers = project.chapterMarkers
        duplicate.commentaryMarkers = project.commentaryMarkers
        duplicate.demoPackSettings = project.demoPackSettings
        duplicate.publishMetadata = project.publishMetadata
        
        // Reset playback state for the duplicate
        duplicate.currentTime = 0.0
        duplicate.scrollOffset = 0.0
        duplicate.zoomLevel = 1.0
        
        // Insert at the beginning of the list (most recent)
        projects.insert(duplicate, at: 0)
        
        // Save the duplicate
        saveProject(duplicate)
        
        AppLogger.project.info("Duplicated project '\(project.name)' to '\(duplicate.name)'")
        ServiceContainer.shared.toastManager.show("Project Duplicated")
    }

    func deleteProject(_ project: VideoProject) {
        // CRITICAL: Check if project is currently active before deleting
        // This prevents deleting the project the user is actively working on
        if currentProject?.id == project.id {
            AppLogger.project.warning("⚠️ Attempted to delete currently active project")
            // The delete will proceed and switch to another project (handled below)
            // But we log it for visibility
        }

        Task {
            do {
                try await projectStore.deleteProject(project)

                await MainActor.run {
                    self.projects.removeAll { $0.id == project.id }

                    // CRITICAL: If we deleted the current project, switch to another one
                    // This is already handled, but ensure it happens before UI updates
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

    /// Delete multiple projects at once
    /// - Parameter projectIds: Set of project IDs to delete
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
                // Remove deleted projects from array
                self.projects.removeAll { projectIds.contains($0.id) }

                // Switch to another project if needed
                if needsSwitch {
                    if let next = self.projects.first {
                        self.updateCurrentProject(next)
                    } else {
                        self.startNewProject()
                    }
                }

                // Show result
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
        // CRITICAL FIX: Stop existing security scope session before creating a new one
        // This prevents security scope leaks when switching projects
        if let existingSession = currentScopeSession {
            existingSession.stop()
            currentScopeSession = nil
        }

        if let project = project {
            // Hydrate project to resolve stale bookmarks before ensuring access
            let (hydratedProject, needsSave) = ServiceContainer.shared.projectFileManager.hydrateProject(project)
            currentProject = hydratedProject

            // CRITICAL: Save project if bookmarks were updated during hydration
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

    /// P0 FIX: Posted when a clip is updated (e.g., relinked to new file)
    /// Object: VideoProject that was updated
    static let clipUpdated = Notification.Name("clipUpdated")
}
