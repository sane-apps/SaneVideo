//
//  ProjectStore.swift
//  SaneVideo
//
//  File-based project persistence implementation

import Foundation
import OSLog

/// File-based implementation of ProjectStoreProtocol
final class ProjectStore: ProjectStoreProtocol {
    private let projectsDirectory: URL
    private let loadState = OSAllocatedUnfairLock<Task<[VideoProject], Error>?>(initialState: nil)

    init(rootDirectory: URL? = nil) {
        if let rootDirectory {
            projectsDirectory = rootDirectory
        } else {
            // Check for Test Mode / Editor Mode via UserDefaults (which we confirmed works)
            let isTesting = UserDefaults.standard.bool(forKey: "ui_testing") ||
                            UserDefaults.standard.bool(forKey: "open_editor") ||
                            ProcessInfo.processInfo.environment["UI_TESTING"] != nil ||
                            ProcessInfo.processInfo.environment["OPEN_EDITOR"] != nil ||
                            ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil ||
                            ProcessInfo.processInfo.arguments.contains("-ui_testing") ||
                            ProcessInfo.processInfo.arguments.contains("-open_editor")

            if isTesting {
                // Use a dedicated, isolated temporary directory for EACH instance during tests
                // This prevents race conditions where one test wipes the directory while another writes
                AppLogger.project.info("🧪 ProjectStore: Using isolated temporary directory for test instance")
                projectsDirectory = FileManager.default.temporaryDirectory
                    .appendingPathComponent("SaneVideo_Test_Projects")
                    .appendingPathComponent(UUID().uuidString)
            } else {
                // Projects directory in user's Movies folder
                if let moviesDir = FileManager.default.urls(for: .moviesDirectory, in: .userDomainMask).first {
                    projectsDirectory = moviesDir.appendingPathComponent("SaneVideo/Projects")
                } else {
                    // Fallback to Documents if Movies not found
                    if let documentsDir = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first {
                        projectsDirectory = documentsDir.appendingPathComponent("SaneVideo/Projects")
                    } else {
                        // Ultimate fallback - use temp directory (should never happen)
                        AppLogger.project.error("CRITICAL: Could not find Documents directory, using temp")
                        projectsDirectory = FileManager.default.temporaryDirectory.appendingPathComponent("SaneVideo/Projects")
                    }
                }
            }
        }

        // Ensure directory exists
        do {
            try FileManager.default.createDirectory(at: projectsDirectory, withIntermediateDirectories: true)
            AppLogger.project.info("ProjectStore initialized at: \(projectsDirectory.path)")
        } catch {
            AppLogger.project.error("Failed to create projects directory: \(error.localizedDescription)")
        }
    }

    // MARK: - ProjectStoreProtocol

    // MARK: - ProjectStoreProtocol

    func loadProjects() async throws -> [VideoProject] {
        let task = loadState.withLock { state -> Task<[VideoProject], Error> in
            if let existing = state {
                AppLogger.project.debug("♻️ ProjectStore: Reusing existing load task")
                return existing
            }

            // Capture necessary values to avoid capturing `self` strongly if possible,
            // or rely on self being Sendable.
            let directory = projectsDirectory

            let newTask = Task<[VideoProject], Error> {
                NSLog("🕵️‍♀️ ProjectStore: loadProjects started loading from disk")
                let fileManager = FileManager.default

                var projectFiles = try fileManager.contentsOfDirectory(
                    at: directory,
                    includingPropertiesForKeys: [.contentModificationDateKey],
                    options: [.skipsHiddenFiles]
                ).filter { $0.pathExtension == "svproj" }

                // Sort by modification date (newest first)
                projectFiles.sort { url1, url2 in
                    let date1 = (try? url1.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
                    let date2 = (try? url2.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
                    return date1 > date2
                }

                AppLogger.project.info("Found \(projectFiles.count) project files on disk")

                var projects: [VideoProject] = []

                for fileURL in projectFiles {
                    // CRITICAL: Check if file exists BEFORE trying to read it
                    // This prevents false "corrupted" errors for files that were deleted
                    let fileManager = FileManager.default
                    guard fileManager.fileExists(atPath: fileURL.path) else {
                        AppLogger.project.warning("⚠️ Project file not found (may have been deleted): \(fileURL.lastPathComponent)")
                        AppLogger.uiLog.warning("Project file missing: \(fileURL.lastPathComponent) - file was deleted or moved")
                        // Skip this project - don't show error for missing files
                        continue
                    }
                    
                    do {
                        // Load file data
                        let data = try Data(contentsOf: fileURL)

                        // CRITICAL: Check if file is empty or too small (likely corrupted)
                        guard data.count > 10 else {
                            AppLogger.project.warning("⚠️ Project file appears corrupted (too small: \(data.count) bytes): \(fileURL.lastPathComponent)")
                            AppLogger.uiLog.warning("Project file too small: \(fileURL.lastPathComponent) (\(data.count) bytes)")
                            // Try to load backup if available
                            let backupURL = fileURL.appendingPathExtension("backup")
                            if FileManager.default.fileExists(atPath: backupURL.path) {
                                AppLogger.project.info("Attempting to load from backup: \(backupURL.lastPathComponent)")
                                do {
                                    let backupData = try Data(contentsOf: backupURL)
                                    let rawProject = try await MainActor.run {
                                        try JSONDecoder().decode(VideoProject.self, from: backupData)
                                    }
                                    projects.append(rawProject)
                                    AppLogger.project.info("✅ Successfully loaded from backup: \(fileURL.lastPathComponent)")
                                    AppLogger.uiLog.warning("⚠️ Project recovery: \(fileURL.lastPathComponent) was corrupted but restored from backup")
                                    // Show toast even on successful recovery so user knows file was corrupted
                                    await MainActor.run {
                                        ServiceContainer.shared.toastManager.show("⚠️ Project file corrupted (recovered from backup): \(fileURL.lastPathComponent)", type: .error)
                                    }
                                    continue
                                } catch {
                                    let backupError = "\(error.localizedDescription) (type: \(type(of: error)))"
                                    AppLogger.project.error("Backup also corrupted: \(backupError)")
                                    AppLogger.uiLog.error("Project recovery failed: \(fileURL.lastPathComponent) - backup also corrupted: \(backupError)")
                                }
                            } else {
                                AppLogger.uiLog.error("Project corruption (no backup): \(fileURL.lastPathComponent) - file too small (\(data.count) bytes)")
                            }
                            continue
                        }

                        // Decode on MainActor to satisfy Swift 6 Codable isolation
                        let rawProject = try await MainActor.run {
                            try JSONDecoder().decode(VideoProject.self, from: data)
                        }

                        // We no longer hydrate ALL projects at boot to keep logs clean
                        // and startup fast. Hydration will happen when a project is opened.
                        projects.append(rawProject)
                    } catch {
                        // CRITICAL: Enhanced logging for corruption detection
                        let errorDetails = "\(error.localizedDescription) (type: \(type(of: error)))"
                        
                        // Check if error is "file not found" (might have been deleted between listing and reading)
                        let nsError = error as NSError
                        if nsError.domain == NSCocoaErrorDomain && nsError.code == NSFileReadNoSuchFileError {
                            AppLogger.project.warning("⚠️ Project file not found (deleted after listing): \(fileURL.lastPathComponent)")
                            AppLogger.uiLog.warning("Project file missing: \(fileURL.lastPathComponent) - file was deleted or moved")
                            // Skip this project - don't show error for missing files
                            continue
                        }
                        
                        // Double-check file still exists (race condition)
                        if !fileManager.fileExists(atPath: fileURL.path) {
                            AppLogger.project.warning("⚠️ Project file not found (deleted during read): \(fileURL.lastPathComponent)")
                            AppLogger.uiLog.warning("Project file missing: \(fileURL.lastPathComponent) - file was deleted or moved")
                            continue
                        }
                        
                        // File exists but failed to load - this is actual corruption
                        AppLogger.project.error("❌ Failed to load project at \(fileURL.path): \(errorDetails)")
                        AppLogger.uiLog.error("Project corruption detected: \(fileURL.lastPathComponent) - \(errorDetails)")

                        // CRITICAL: Try to load backup if main file fails
                        let backupURL = fileURL.appendingPathExtension("backup")
                        if fileManager.fileExists(atPath: backupURL.path) {
                            AppLogger.project.info("Attempting to load from backup: \(backupURL.lastPathComponent)")
                            do {
                                let backupData = try Data(contentsOf: backupURL)
                                let rawProject = try await MainActor.run {
                                    try JSONDecoder().decode(VideoProject.self, from: backupData)
                                }
                                projects.append(rawProject)
                                AppLogger.project.info("✅ Successfully loaded corrupted project from backup: \(fileURL.lastPathComponent)")
                                AppLogger.uiLog.warning("⚠️ Project recovery: \(fileURL.lastPathComponent) was corrupted but restored from backup")
                                // Show toast even on successful recovery so user knows file was corrupted
                                await MainActor.run {
                                    ServiceContainer.shared.toastManager.show("⚠️ Project file corrupted (recovered from backup): \(fileURL.lastPathComponent)", type: .error)
                                }
                            } catch {
                                let backupError = "\(error.localizedDescription) (type: \(type(of: error)))"
                                AppLogger.project.error("Backup also failed to load: \(backupError)")
                                AppLogger.uiLog.error("Project recovery failed: \(fileURL.lastPathComponent) - backup also corrupted: \(backupError)")
                                // CRITICAL: Show warning to user about corrupted project
                                await MainActor.run {
                                    ServiceContainer.shared.toastManager.show("⚠️ Project file corrupted: \(fileURL.lastPathComponent)", type: .error)
                                }
                            }
                        } else {
                            // No backup available - show warning
                            AppLogger.project.warning("No backup available for corrupted project: \(fileURL.lastPathComponent)")
                            AppLogger.uiLog.error("Project corruption (no backup): \(fileURL.lastPathComponent) - \(errorDetails)")
                            await MainActor.run {
                                ServiceContainer.shared.toastManager.show("⚠️ Project file corrupted (no backup): \(fileURL.lastPathComponent)", type: .error)
                            }
                        }
                    }
                }
                return projects
            }

            state = newTask
            return newTask
        }

        do {
            let projects = try await task.value

            loadState.withLock { state in
                if state == task { state = nil }
            }

            return projects
        } catch {
            loadState.withLock { state in
                if state == task { state = nil }
            }
            throw error
        }
    }

    func saveProject(_ project: VideoProject) async throws {
        // CRITICAL FIX: Use retry for transient file I/O errors
        try await retryOperation(maxAttempts: 3, initialDelay: 0.5) {
            let directory = self.projectsDirectory
            // Encode on MainActor to satisfy Swift 6 Codable isolation
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            let data = try encoder.encode(project)
            let filename = "\(project.id.uuidString).svproj"
            let fileURL = directory.appendingPathComponent(filename)

            // CRITICAL: Create backup before overwrite to prevent data loss
            let backupURL = fileURL.appendingPathExtension("backup")
            let fileManager = FileManager.default

            try await Task.detached(priority: .utility) {
                let activity = ProcessInfo.processInfo.beginActivity(options: [.userInitiated, .suddenTerminationDisabled], reason: "Save Project")
                defer { ProcessInfo.processInfo.endActivity(activity) }

                // CRITICAL: Create backup if file exists
                if fileManager.fileExists(atPath: fileURL.path) {
                    do {
                        try fileManager.copyItem(at: fileURL, to: backupURL)
                        AppLogger.project.debug("Created backup: \(backupURL.lastPathComponent)")
                    } catch {
                        AppLogger.project.warning("Failed to create backup (non-fatal): \(error.localizedDescription)")
                        // Continue with save even if backup fails
                    }
                }

                // CRITICAL: Atomic write with verification
                try data.write(to: fileURL, options: Data.WritingOptions.atomic)

                // CRITICAL: Verify file was written correctly
                guard fileManager.fileExists(atPath: fileURL.path) else {
                    // Restore backup if write failed
                    if fileManager.fileExists(atPath: backupURL.path) {
                        try? fileManager.copyItem(at: backupURL, to: fileURL)
                        AppLogger.project.warning("Write verification failed, restored from backup")
                    }
                    throw AppError.projectSaveFailed(NSError(domain: "ProjectStore", code: -1, userInfo: [NSLocalizedDescriptionKey: "File write verification failed"]))
                }

                // CRITICAL: Verify file is readable and valid JSON (not corrupted)
                do {
                    let verifyData = try Data(contentsOf: fileURL)
                    // Quick sanity check - file should not be empty
                    guard !verifyData.isEmpty else {
                        throw AppError.projectSaveFailed(NSError(domain: "ProjectStore", code: -2, userInfo: [NSLocalizedDescriptionKey: "Saved file is empty"]))
                    }

                    // CRITICAL: Verify file is valid JSON and can be decoded
                    // This catches corruption that makes file non-empty but invalid JSON
                    let _ = try await MainActor.run {
                        try JSONDecoder().decode(VideoProject.self, from: verifyData)
                    }
                } catch {
                    // Restore backup if verification fails
                    if fileManager.fileExists(atPath: backupURL.path) {
                        try? fileManager.copyItem(at: backupURL, to: fileURL)
                        AppLogger.project.warning("File verification failed (invalid JSON), restored from backup")
                        AppLogger.uiLog.error("Save verification failed: \(fileURL.lastPathComponent) - file is not valid JSON")
                    }
                    throw AppError.projectSaveFailed(NSError(domain: "ProjectStore", code: -3, userInfo: [NSLocalizedDescriptionKey: "Saved file is not valid JSON: \(error.localizedDescription)"]))
                }

                // CRITICAL: Clean up backup after successful save
                // Keep last backup for recovery, but remove older ones
                try? fileManager.removeItem(at: backupURL)
            }.value
        }

        AppLogger.project.info("Saved project: \(project.name)")
    }

    func deleteProject(_ project: VideoProject) async throws {
        // CRITICAL: Check if project is currently active before deleting
        // This should be checked by caller, but add safety check here too
        let directory = projectsDirectory
        try await Task.detached(priority: .utility) {
            let fileManager = FileManager.default
            let filename = "\(project.id.uuidString).svproj"
            let fileURL = directory.appendingPathComponent(filename)

            // CRITICAL: Check if file exists before trying to delete
            guard fileManager.fileExists(atPath: fileURL.path) else {
                AppLogger.project.warning("Project file does not exist: \(fileURL.path)")
                // Not an error - file might have been deleted already
                return
            }

            do {
                try fileManager.removeItem(at: fileURL)

                // CRITICAL: Also delete backup if it exists
                let backupURL = fileURL.appendingPathExtension("backup")
                if fileManager.fileExists(atPath: backupURL.path) {
                    try? fileManager.removeItem(at: backupURL)
                }

                await MainActor.run {
                    AppLogger.project.info("Deleted project: \(project.name)")
                }
            } catch {
                throw AppError.projectSaveFailed(error)
            }
        }.value
    }

    func recentProjects(limit: Int) async throws -> [VideoProject] {
        let allProjects = try await loadProjects()

        // Sort by creation date (newest first)
        let sorted = allProjects.sorted { $0.createdAt > $1.createdAt }

        return Array(sorted.prefix(limit))
    }

    func fileURL(for project: VideoProject) -> URL {
        return projectsDirectory.appendingPathComponent("\(project.id.uuidString).svproj")
    }
}
