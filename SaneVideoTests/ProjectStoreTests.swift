import Testing
import Foundation
@testable import SaneVideo

@Suite("Project Store Tests")
@MainActor
struct ProjectStoreTests {
    
    // MARK: - Setup and Utilities
    
    private static func createTempDir() -> URL {
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try? FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true, attributes: nil)
        return tempDir
    }
    
    private static func cleanupTempDir(_ url: URL) {
        try? FileManager.default.removeItem(at: url)
    }

    // MARK: - Tests

    @Test("Save and load project persistence")
    func saveAndLoadProject() async throws {
        let tempDir = Self.createTempDir()
        defer { Self.cleanupTempDir(tempDir) }
        
        let store = ProjectStore(rootDirectory: tempDir)
        let project = VideoProject(name: "Test Project")
        let projectId = project.id
        
        try await store.saveProject(project)
        
        let loadedProjects = try await store.loadProjects()
        #expect(loadedProjects.contains(where: { $0.id == projectId }))
        #expect(loadedProjects.contains(where: { $0.name == "Test Project" }))
    }

    @Test("Recent projects retrieval")
    func recentProjects() async throws {
        let tempDir = Self.createTempDir()
        defer { Self.cleanupTempDir(tempDir) }
        
        let store = ProjectStore(rootDirectory: tempDir)
        let project1 = VideoProject(name: "Recent 1")
        let project2 = VideoProject(name: "Recent 2")
        
        try await store.saveProject(project1)
        try await store.saveProject(project2)
        
        let recents = try await store.recentProjects(limit: 5)
        #expect(recents.contains { $0.id == project1.id })
        #expect(recents.contains { $0.id == project2.id })
        
        // Cleanup
        for project in recents {
            try await store.deleteProject(project)
        }
    }
}
