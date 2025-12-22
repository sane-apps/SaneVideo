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

    init(rootDirectory: URL? = nil) {
        if let rootDirectory {
            projectsDirectory = rootDirectory
        } else {
            // Check for Test Mode / Editor Mode via UserDefaults (which we confirmed works)
            let isTesting = UserDefaults.standard.bool(forKey: "ui_testing") || 
                            UserDefaults.standard.bool(forKey: "open_editor") ||
                            ProcessInfo.processInfo.environment["UI_TESTING"] != nil ||
                            ProcessInfo.processInfo.environment["OPEN_EDITOR"] != nil ||
                            ProcessInfo.processInfo.arguments.contains("-ui_testing") ||
                            ProcessInfo.processInfo.arguments.contains("-open_editor")

            if isTesting {
                // Use a dedicated temporary directory for tests to avoid loading user data
                AppLogger.project.info("🧪 ProjectStore: Using temporary directory for tests")
                projectsDirectory = FileManager.default.temporaryDirectory.appendingPathComponent("SaneVideo_Test_Projects")
                // Ensure it's clean
                try? FileManager.default.removeItem(at: projectsDirectory)
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
        NSLog("🕵️‍♀️ ProjectStore: loadProjects called!")
        for symbol in Thread.callStackSymbols.prefix(10) { NSLog("\(symbol)") }
        let directory = projectsDirectory
        return try await Task.detached(priority: .userInitiated) {
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

            await MainActor.run {
                AppLogger.project.info("Found \(projectFiles.count) project files on disk")
            }

            // Load all projects (removed hardcoded limit of 10)
            let limitedFiles = projectFiles

            var projects: [VideoProject] = []

            for fileURL in limitedFiles {
                do {
                    // Load file data on background thread to avoid blocking
                    let data = try await Task.detached(priority: .utility) {
                        try Data(contentsOf: fileURL)
                    }.value

                    // Decode on MainActor to satisfy Swift 6 Codable isolation
                    let rawProject = try await MainActor.run {
                        try JSONDecoder().decode(VideoProject.self, from: data)
                    }

                    // Hydrate project (resolve bookmarks, update URLs)
                    // ProjectFileManager is now Sendable, so calling it from Task.detached is safe.
                    let hydratedProject = await MainActor.run {
                        ServiceContainer.shared.projectFileManager.hydrateProject(rawProject)
                    }

                    projects.append(hydratedProject)
                } catch {
                    await MainActor.run {
                        AppLogger.logError(
                            AppError.projectLoadFailed(error),
                            category: AppLogger.project
                        )
                    }
                }
            }
            return projects
        }.value
    }

    func saveProject(_ project: VideoProject) async throws {
        let directory = projectsDirectory
        // Encode on MainActor to satisfy Swift 6 Codable isolation
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(project)
        let filename = "\(project.id.uuidString).svproj"
        let fileURL = directory.appendingPathComponent(filename)

        try await Task.detached(priority: .utility) {
            let activity = ProcessInfo.processInfo.beginActivity(options: [.userInitiated, .suddenTerminationDisabled], reason: "Save Project")
            defer { ProcessInfo.processInfo.endActivity(activity) }
            
            try data.write(to: fileURL, options: Data.WritingOptions.atomic)
        }.value

        AppLogger.project.info("Saved project: \(project.name) to \(filename)")
    }

    func deleteProject(_ project: VideoProject) async throws {
        let directory = projectsDirectory
        try await Task.detached(priority: .utility) {
            let fileManager = FileManager.default
            let filename = "\(project.id.uuidString).svproj"
            let fileURL = directory.appendingPathComponent(filename)

            do {
                try fileManager.removeItem(at: fileURL)
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
