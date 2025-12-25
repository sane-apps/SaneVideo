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
    
    // P0 FIX: Cancel current operation
    func cancelCurrentOperation() {
        currentProcessingTask?.cancel()
        currentProcessingTask = nil
        isProcessing = false
        processingProgress = 0.0
        processingStatus = nil
        AppLogger.project.info("Operation cancelled by user")
        ServiceContainer.shared.toastManager.show("Operation cancelled", type: .info)
    }

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

    // MARK: - Clip Management

    // MARK: - Notification Names
    func recalculateStartTimes(in timeline: inout Timeline) {
        // Only close gaps if Magnetic Timeline is enabled
        @AppStorage("magneticTimeline") var magneticTimeline = true
        
        // Recalculate for ALL tracks
        for (trackIndex, track) in timeline.tracks.enumerated() {
            var mutableTrack = track
            
            // CRITICAL FIX: Sort clips by startTime before recalculating
            // This ensures correct order even if clips were added out of order
            mutableTrack.clips.sort { $0.startTime < $1.startTime }
            
            if magneticTimeline {
                // Close gaps: sequential clips with no spacing
                var cumulativeTime = CMTime.zero
                for clipIndex in 0 ..< mutableTrack.clips.count {
                    mutableTrack.clips[clipIndex].startTime = cumulativeTime
                    cumulativeTime = CMTimeAdd(cumulativeTime, mutableTrack.clips[clipIndex].effectiveDuration)
                }
            } else {
                // Preserve gaps: only recalculate if clips overlap
                // If clips don't overlap, keep their startTimes
                for clipIndex in 1 ..< mutableTrack.clips.count {
                    let prevClip = mutableTrack.clips[clipIndex - 1]
                    let prevEnd = CMTimeAdd(prevClip.startTime, prevClip.effectiveDuration)
                    let currentClip = mutableTrack.clips[clipIndex]
                    
                    // If current clip starts before previous ends, fix overlap
                    if currentClip.startTime < prevEnd {
                        mutableTrack.clips[clipIndex].startTime = prevEnd
                    }
                    // Otherwise, preserve the gap
                }
            }
            timeline.tracks[trackIndex] = mutableTrack
        }
        
        // CRITICAL FIX: Update timeline duration after recalculating startTimes
        timeline.updateDuration()
    }
    
    /// CRITICAL FIX: Validate timeline state for consistency
    /// Checks for overlaps, invalid startTimes, duplicate IDs, etc.
    func validateTimelineState(_ timeline: Timeline) -> Bool {
        // Check for duplicate clip IDs
        var seenIDs = Set<UUID>()
        for track in timeline.tracks {
            for clip in track.clips {
                if seenIDs.contains(clip.id) {
                    AppLogger.project.error("Duplicate clip ID found: \(clip.id)")
                    return false
                }
                seenIDs.insert(clip.id)
                
                // Validate clip properties
                if clip.startTime.seconds < 0 {
                    AppLogger.project.error("Clip has negative startTime: \(clip.id)")
                    return false
                }
                
                if clip.effectiveDuration.seconds <= 0 {
                    AppLogger.project.error("Clip has zero or negative duration: \(clip.id)")
                    return false
                }
                
                // Check for overlaps within same track
                let sortedClips = track.clips.sorted { $0.startTime < $1.startTime }
                for i in 1 ..< sortedClips.count {
                    let prevClip = sortedClips[i - 1]
                    let currentClip = sortedClips[i]
                    let prevEnd = CMTimeAdd(prevClip.startTime, prevClip.effectiveDuration)
                    
                    if currentClip.startTime < prevEnd {
                        AppLogger.project.error("Clips overlap in track: \(prevClip.id) and \(currentClip.id)")
                        return false
                    }
                }
            }
        }
        
        return true
    }
    
    // CRITICAL FIX: Cleanup method to cancel all tasks before deallocation
    // This should be called explicitly, but also provides safety in deinit
    nonisolated deinit {
        // CRITICAL FIX: Cancel tasks on deallocation
        // Note: We can't access actor-isolated properties in nonisolated deinit,
        // but we can use MainActor.assumeIsolated for cancellation
        MainActor.assumeIsolated {
            currentProcessingTask?.cancel()
            currentProcessingTask = nil
            pendingSaveTask?.cancel()
            pendingSaveTask = nil
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
        } else {
            currentProject = nil
            // Session already stopped above
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
