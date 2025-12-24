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
    var isProcessing = false
    var processingProgress: Double = 0.0
    var processingStatus: String?

    /// CRITICAL FIX: Track if initial project load is in progress
    /// UI should check this to avoid accessing empty project list during startup
    var isLoadingProjects = true

    private var currentScopeSession: ProjectFileManager.SecurityScopeSession?
    
    /// Current processing task for cancellation support
    var currentProcessingTask: Task<Void, Error>?

    // MARK: - Smart Features State
    
    var magicFixOptions = MagicFixOptions()

    // MARK: - Save Debounce

    /// Debounce save operations to avoid duplicate saves from rapid changes
    private var pendingSaveTask: Task<Void, Never>?
    private var lastSaveTime: Date = .distantPast

    // MARK: - Undo Manager (SwiftUI's built-in)

    var undoManager: UndoManager?

    // MARK: - Undo Helper

    func registerUndo(_ actionName: String) {
        guard let project = currentProject else { return }
        // Capture the ENTIRE project state (value type) for robust undo
        undoManager?.registerUndo(withTarget: self) { target in
            target.restoreProjectState(project)
        }
        undoManager?.setActionName(actionName)
        // Note: Toast removed - showing "Undo: X" before action completes was confusing UX
    }

    private func restoreProjectState(_ project: VideoProject) {
        // Capture current state for Redo
        if let current = currentProject {
            undoManager?.registerUndo(withTarget: self) { target in
                target.restoreProjectState(current)
            }
        }

        // Restore
        updateCurrentProject(project)
        saveProject(project)
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

    func startNewProject(template: ProjectTemplate? = nil) {
        var project = VideoProject()

        // Apply template settings if provided
        if let template = template {
            project.name = template.name
            // Note: Aspect ratio and export settings are applied at export time
            // Caption style can be set here
            project.captionStyleName = template.defaultCaptionStyle
        }

        updateCurrentProject(project)
        projects.insert(project, at: 0)
        saveProject(project)
        AppLogger.project.info("Started new project \(project.id) with template: \(template?.name ?? "none")")
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
        // Debounce: Cancel any pending save and schedule a new one
        // This prevents duplicate saves from rapid changes (e.g., rotation + onChange)
        pendingSaveTask?.cancel()

        // If last save was very recent, debounce with a small delay
        let now = Date()
        let timeSinceLastSave = now.timeIntervalSince(lastSaveTime)
        let shouldDebounce = timeSinceLastSave < 0.1 // 100ms window

        pendingSaveTask = Task {
            if shouldDebounce {
                try? await Task.sleep(for: .milliseconds(100))
                guard !Task.isCancelled else { return }
            }

            do {
                try await projectStore.saveProject(project)
                await MainActor.run {
                    self.lastSaveTime = Date()
                }
                AppLogger.project.info("Saved project \(project.name)")
            } catch {
                guard !Task.isCancelled else { return }
                AppLogger.project.error("Failed to save project: \(error)")
                await MainActor.run {
                    ServiceContainer.shared.errorPresenter.present(AppError.projectSaveFailed(error))
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

    func renameProject(_ newName: String) {
        guard var project = currentProject else { return }
        guard !newName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }

        registerUndo("Rename Project")

        let oldName = project.name
        project.rename(newName)
        currentProject = project
        saveProject(project)

        // Also update in the projects list if present
        if let index = projects.firstIndex(where: { $0.id == project.id }) {
            projects[index] = project
        }

        AppLogger.project.info("Renamed project from '\(oldName)' to '\(newName)'")
        ServiceContainer.shared.toastManager.show("Project Renamed")
    }
    
    func deleteProject(_ project: VideoProject) {
        // Prevent deleting the *only* project (create a new one first if needed, or handle in UI)
        // But for now, just allow it and if checking current, switch.

        Task {
            do {
                try await projectStore.deleteProject(project)

                await MainActor.run {
                    self.projects.removeAll { $0.id == project.id }

                    // If we deleted the current project, switch to another one
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

    // MARK: - Clip Management

    // MARK: - Notification Names
    func recalculateStartTimes(in timeline: inout Timeline) {
        // Only close gaps if Magnetic Timeline is enabled
        @AppStorage("magneticTimeline") var magneticTimeline = true
        guard magneticTimeline else { return }

        // Recalculate for ALL tracks
        for (trackIndex, track) in timeline.tracks.enumerated() {
            var mutableTrack = track
            var cumulativeTime = CMTime.zero
            for clipIndex in 0 ..< mutableTrack.clips.count {
                mutableTrack.clips[clipIndex].startTime = cumulativeTime
                cumulativeTime = CMTimeAdd(cumulativeTime, mutableTrack.clips[clipIndex].effectiveDuration)
            }
            timeline.tracks[trackIndex] = mutableTrack
        }
    }

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

    private func updateCurrentProject(_ project: VideoProject?) {
        if let project = project {
            // Hydrate project to resolve stale bookmarks before ensuring access
            let hydratedProject = ServiceContainer.shared.projectFileManager.hydrateProject(project)
            currentProject = hydratedProject
            currentScopeSession = ServiceContainer.shared.projectFileManager.enterSecurityScope(for: hydratedProject)
        } else {
            currentProject = nil
            currentScopeSession = nil
        }
    }
}

// MARK: - Notification Names

extension Notification.Name {
    /// Posted when a clip is added to the timeline
    /// Object: VideoProject that was updated
    static let clipAddedToTimeline = Notification.Name("clipAddedToTimeline")
}
