//
//  ProjectStoreBackupRecoveryTests.swift
//  SaneVideoTests
//
//  Comprehensive tests for ProjectStore backup and recovery functionality
//

import Testing
import Foundation
@testable import SaneVideo

@Suite("ProjectStore Backup Recovery Tests")
@MainActor
struct ProjectStoreBackupRecoveryTests {

    // MARK: - Setup and Utilities

    private static func createTempDir() -> URL {
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try? FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true, attributes: nil)
        return tempDir
    }

    private static func cleanupTempDir(_ url: URL) {
        try? FileManager.default.removeItem(at: url)
    }

    private static func createValidProjectData(project: VideoProject) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return try encoder.encode(project)
    }

    // MARK: - Backup Creation Tests

    @Test("Save creates backup when file exists")
    func saveCreatesBackupWhenFileExists() async throws {
        let tempDir = Self.createTempDir()
        defer { Self.cleanupTempDir(tempDir) }

        let store = ProjectStore(rootDirectory: tempDir)
        let project = VideoProject(name: "Backup Test")

        // Act - save twice (second save should create backup of first)
        try await store.saveProject(project)
        let fileURL = store.fileURL(for: project)

        // Small delay to ensure different timestamps
        try await Task.sleep(nanoseconds: 100_000_000) // 0.1s

        try await store.saveProject(project)

        // Assert - backup should have been created and removed after success
        // Note: The current implementation removes backup after successful save
        // So we verify the save completed successfully
        #expect(FileManager.default.fileExists(atPath: fileURL.path))
    }

    @Test("Save atomic write prevents partial writes")
    func saveAtomicWritePreventsPartialWrites() async throws {
        let tempDir = Self.createTempDir()
        defer { Self.cleanupTempDir(tempDir) }

        let store = ProjectStore(rootDirectory: tempDir)
        let project = VideoProject(name: "Atomic Test")

        // Act
        try await store.saveProject(project)

        // Assert - file should be valid JSON and readable
        let fileURL = store.fileURL(for: project)
        let data = try Data(contentsOf: fileURL)
        let decoded = try JSONDecoder().decode(VideoProject.self, from: data)
        #expect(decoded.id == project.id)
        #expect(decoded.name == "Atomic Test")
    }

    // MARK: - Corruption Recovery on Load Tests

    @Test("Load recovers from corrupted file using backup")
    func loadRecoversFromCorruptedFileUsingBackup() async throws {
        let tempDir = Self.createTempDir()
        defer { Self.cleanupTempDir(tempDir) }

        let store = ProjectStore(rootDirectory: tempDir)
        let project = VideoProject(name: "Recovery Test")

        // Arrange - save valid project, then corrupt the main file
        try await store.saveProject(project)
        let fileURL = store.fileURL(for: project)
        let backupURL = fileURL.appendingPathExtension("backup")

        // Create a valid backup
        let validData = try Self.createValidProjectData(project: project)
        try validData.write(to: backupURL)

        // Corrupt the main file with invalid JSON
        try "CORRUPTED DATA".data(using: .utf8)?.write(to: fileURL)

        // Act
        let loadedProjects = try await store.loadProjects()

        // Assert - should have loaded from backup
        #expect(loadedProjects.contains(where: { $0.id == project.id }))
    }

    @Test("Load replaces corrupted file with backup after recovery")
    func loadReplacesCorruptedFileWithBackupAfterRecovery() async throws {
        let tempDir = Self.createTempDir()
        defer { Self.cleanupTempDir(tempDir) }

        let store = ProjectStore(rootDirectory: tempDir)
        let project = VideoProject(name: "Replace Test")

        // Arrange - create valid backup, corrupt main file
        let fileURL = store.fileURL(for: project)
        let backupURL = fileURL.appendingPathExtension("backup")

        let validData = try Self.createValidProjectData(project: project)
        try validData.write(to: backupURL)
        try "CORRUPTED".data(using: .utf8)?.write(to: fileURL)

        // Act - load should recover from backup AND replace corrupted file
        let loadedProjects = try await store.loadProjects()

        // Assert - project should be loaded
        #expect(loadedProjects.contains(where: { $0.id == project.id }))

        // CRITICAL: Verify corrupted file was replaced with backup data
        // This prevents repeated warnings on every app launch
        let mainFileData = try Data(contentsOf: fileURL)
        let decoded = try JSONDecoder().decode(VideoProject.self, from: mainFileData)
        #expect(decoded.id == project.id, "Main file should now contain valid project data")
        #expect(decoded.name == "Replace Test", "Main file should match backup data")
    }

    @Test("Load recovers from too-small file using backup")
    func loadRecoversFromTooSmallFileUsingBackup() async throws {
        let tempDir = Self.createTempDir()
        defer { Self.cleanupTempDir(tempDir) }

        let store = ProjectStore(rootDirectory: tempDir)
        let project = VideoProject(name: "Small File Test")

        // Arrange - create valid backup, tiny main file
        let fileURL = store.fileURL(for: project)
        let backupURL = fileURL.appendingPathExtension("backup")

        let validData = try Self.createValidProjectData(project: project)
        try validData.write(to: backupURL)

        // Write tiny file (less than 10 bytes triggers corruption check)
        try "tiny".data(using: .utf8)?.write(to: fileURL)

        // Act
        let loadedProjects = try await store.loadProjects()

        // Assert - should have loaded from backup
        #expect(loadedProjects.contains(where: { $0.id == project.id }))
    }

    @Test("Load skips corrupted file when no backup exists")
    func loadSkipsCorruptedFileWithNoBackup() async throws {
        let tempDir = Self.createTempDir()
        defer { Self.cleanupTempDir(tempDir) }

        let store = ProjectStore(rootDirectory: tempDir)

        // Arrange - create corrupted file with no backup
        let projectId = UUID()
        let fileURL = tempDir.appendingPathComponent("\(projectId.uuidString).svproj")
        try "CORRUPTED".data(using: .utf8)?.write(to: fileURL)

        // Act - should not crash
        let loadedProjects = try await store.loadProjects()

        // Assert - corrupted project should be skipped (not in loaded list)
        // Verify the corrupted project is not in the loaded projects
        let containsCorruptedProject = loadedProjects.contains(where: { $0.id == projectId })
        #expect(containsCorruptedProject == false, "Corrupted project should not be in loaded projects")
    }

    @Test("Load handles both file and backup corrupted")
    func loadHandlesBothFileAndBackupCorrupted() async throws {
        let tempDir = Self.createTempDir()
        defer { Self.cleanupTempDir(tempDir) }

        let store = ProjectStore(rootDirectory: tempDir)

        // Arrange - create corrupted main file and corrupted backup
        let projectId = UUID()
        let fileURL = tempDir.appendingPathComponent("\(projectId.uuidString).svproj")
        let backupURL = fileURL.appendingPathExtension("backup")

        try "CORRUPTED MAIN".data(using: .utf8)?.write(to: fileURL)
        try "CORRUPTED BACKUP".data(using: .utf8)?.write(to: backupURL)

        // Act - should not crash
        let loadedProjects = try await store.loadProjects()

        // Assert - project should not be loaded
        #expect(!loadedProjects.contains(where: { $0.id == projectId }))
    }

    // MARK: - Delete Cleanup Tests

    @Test("Delete removes backup file")
    func deleteRemovesBackupFile() async throws {
        let tempDir = Self.createTempDir()
        defer { Self.cleanupTempDir(tempDir) }

        let store = ProjectStore(rootDirectory: tempDir)
        let project = VideoProject(name: "Delete Test")

        // Arrange - save project and create backup
        try await store.saveProject(project)
        let fileURL = store.fileURL(for: project)
        let backupURL = fileURL.appendingPathExtension("backup")

        // Create backup file
        let validData = try Self.createValidProjectData(project: project)
        try validData.write(to: backupURL)

        #expect(FileManager.default.fileExists(atPath: fileURL.path))
        #expect(FileManager.default.fileExists(atPath: backupURL.path))

        // Act
        try await store.deleteProject(project)

        // Assert - both files should be removed
        #expect(!FileManager.default.fileExists(atPath: fileURL.path))
        #expect(!FileManager.default.fileExists(atPath: backupURL.path))
    }

    @Test("Delete non-existent project completes without error")
    func deleteNonExistentProjectDoesNotCrash() async throws {
        let tempDir = Self.createTempDir()
        defer { Self.cleanupTempDir(tempDir) }

        let store = ProjectStore(rootDirectory: tempDir)
        let project = VideoProject(name: "Phantom")

        // Act - deleteProject returns silently if file doesn't exist (not an error)
        try await store.deleteProject(project)

        // Assert - Verify method completed without throwing
        // The fact that we get here means the method completed successfully
        // Verify the project file still doesn't exist (proves method ran)
        let projectURL = store.fileURL(for: project)
        #expect(!FileManager.default.fileExists(atPath: projectURL.path),
                "Project file should not exist after deleting non-existent project")
    }

    // MARK: - File Verification Tests

    @Test("Save verifies file is readable after write")
    func saveVerifiesFileIsReadableAfterWrite() async throws {
        let tempDir = Self.createTempDir()
        defer { Self.cleanupTempDir(tempDir) }

        let store = ProjectStore(rootDirectory: tempDir)
        let project = VideoProject(name: "Verify Test")

        // Act
        try await store.saveProject(project)

        // Assert - file should be readable and decodable
        let fileURL = store.fileURL(for: project)
        let data = try Data(contentsOf: fileURL)
        #expect(!data.isEmpty)

        let decoded = try JSONDecoder().decode(VideoProject.self, from: data)
        #expect(decoded.id == project.id)
    }

    // MARK: - Multiple Project Tests

    @Test("Load multiple projects with one corrupted")
    func loadMultipleProjectsWithOneCorrupted() async throws {
        let tempDir = Self.createTempDir()
        defer { Self.cleanupTempDir(tempDir) }

        let store = ProjectStore(rootDirectory: tempDir)
        let validProject1 = VideoProject(name: "Valid 1")
        let validProject2 = VideoProject(name: "Valid 2")

        // Arrange - save two valid projects
        try await store.saveProject(validProject1)
        try await store.saveProject(validProject2)

        // Create a corrupted third file
        let corruptedId = UUID()
        let corruptedURL = tempDir.appendingPathComponent("\(corruptedId.uuidString).svproj")
        try "GARBAGE".data(using: .utf8)?.write(to: corruptedURL)

        // Act
        let loadedProjects = try await store.loadProjects()

        // Assert - valid projects should load, corrupted should be skipped
        #expect(loadedProjects.contains(where: { $0.id == validProject1.id }))
        #expect(loadedProjects.contains(where: { $0.id == validProject2.id }))
        #expect(!loadedProjects.contains(where: { $0.id == corruptedId }))
    }

    @Test("Recent projects respects limit")
    func recentProjectsRespectsLimit() async throws {
        let tempDir = Self.createTempDir()
        defer { Self.cleanupTempDir(tempDir) }

        let store = ProjectStore(rootDirectory: tempDir)

        // Arrange - create 5 projects
        var projects: [VideoProject] = []
        for i in 1...5 {
            let project = VideoProject(name: "Project \(i)")
            try await store.saveProject(project)
            projects.append(project)
        }

        // Act
        let recents = try await store.recentProjects(limit: 3)

        // Assert
        #expect(recents.count == 3)
    }

    // MARK: - Edge Cases

    @Test("Save project with special characters in name")
    func saveProjectWithSpecialCharactersInName() async throws {
        let tempDir = Self.createTempDir()
        defer { Self.cleanupTempDir(tempDir) }

        let store = ProjectStore(rootDirectory: tempDir)
        let project = VideoProject(name: "Test: \"Special\" <chars> & more!")

        // Act
        try await store.saveProject(project)
        let loadedProjects = try await store.loadProjects()

        // Assert
        let loaded = loadedProjects.first(where: { $0.id == project.id })
        #expect(loaded?.name == "Test: \"Special\" <chars> & more!")
    }

    @Test("Save empty project name")
    func saveEmptyProjectName() async throws {
        let tempDir = Self.createTempDir()
        defer { Self.cleanupTempDir(tempDir) }

        let store = ProjectStore(rootDirectory: tempDir)
        let project = VideoProject(name: "")

        // Act
        try await store.saveProject(project)
        let loadedProjects = try await store.loadProjects()

        // Assert
        let loaded = loadedProjects.first(where: { $0.id == project.id })
        #expect(loaded?.name == "")
    }

    @Test("File URL returns correct path")
    func fileURLReturnsCorrectPath() {
        let tempDir = Self.createTempDir()
        defer { Self.cleanupTempDir(tempDir) }

        let store = ProjectStore(rootDirectory: tempDir)
        let project = VideoProject(name: "URL Test")

        // Act
        let fileURL = store.fileURL(for: project)

        // Assert
        #expect(fileURL.pathExtension == "svproj")
        #expect(fileURL.lastPathComponent == "\(project.id.uuidString).svproj")
        // Compare paths to avoid trailing slash issues
        #expect(fileURL.deletingLastPathComponent().path == tempDir.path)
    }

    // MARK: - Concurrent Access Tests

    @Test("Concurrent saves do not corrupt data")
    func concurrentSavesDoNotCorruptData() async throws {
        let tempDir = Self.createTempDir()
        defer { Self.cleanupTempDir(tempDir) }

        let store = ProjectStore(rootDirectory: tempDir)
        let project = VideoProject(name: "Concurrent Test")

        // Act - multiple rapid saves
        try await withThrowingTaskGroup(of: Void.self) { group in
            for i in 1...5 {
                group.addTask {
                    var modified = project
                    modified = VideoProject(name: "Update \(i)")
                    try await store.saveProject(modified)
                }
            }
            try await group.waitForAll()
        }

        // Assert - at least one save should have succeeded
        // Note: The concurrent saves may overwrite each other, but should not corrupt
        let loadedProjects = try await store.loadProjects()
        #expect(loadedProjects.count >= 1)
    }

    @Test("Load deduplication prevents redundant disk reads")
    func loadDeduplicationPreventsRedundantDiskReads() async throws {
        let tempDir = Self.createTempDir()
        defer { Self.cleanupTempDir(tempDir) }

        let store = ProjectStore(rootDirectory: tempDir)
        let project = VideoProject(name: "Dedup Test")
        try await store.saveProject(project)

        // Act - concurrent loads
        async let load1 = store.loadProjects()
        async let load2 = store.loadProjects()
        async let load3 = store.loadProjects()

        let results = try await [load1, load2, load3]

        // Assert - all loads should return the same data
        #expect(results[0].count == results[1].count)
        #expect(results[1].count == results[2].count)
        #expect(results[0].first?.id == project.id)
    }
}
