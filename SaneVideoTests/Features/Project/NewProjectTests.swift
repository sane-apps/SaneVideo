// Starting a new project: naming, ordering and saving to the store.

import Foundation
@testable import SaneVideo
import Testing

@Suite("New project")
@MainActor
struct NewProjectTests {
    private func makeState() throws -> (ProjectState, ProjectStore, URL) {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("NewProjectTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let store = ProjectStore(rootDirectory: root)
        return (ProjectState(projectStore: store), store, root)
    }

    @Test("A named project becomes current, goes first in the list and is saved to disk")
    func namedProjectIsCurrentFirstAndSaved() async throws {
        let (state, store, root) = try makeState()
        defer { try? FileManager.default.removeItem(at: root) }

        state.startNewProject(named: "Launch Video")

        let project = try #require(state.currentProject)
        #expect(project.name == "Launch Video")
        #expect(state.projects.first?.id == project.id)

        // Saving runs in a background task; wait for the file rather than a fixed delay.
        let fileURL = store.fileURL(for: project)
        let clock = ContinuousClock()
        let deadline = clock.now.advanced(by: .seconds(5))
        while !FileManager.default.fileExists(atPath: fileURL.path), clock.now < deadline {
            try await Task.sleep(for: .milliseconds(20))
        }
        #expect(FileManager.default.fileExists(atPath: fileURL.path), "New project should be written to the store")
    }

    @Test("Unnamed projects follow the Untitled Project, Untitled Project 2 convention")
    func unnamedProjectsGetUniqueNames() throws {
        let (state, _, root) = try makeState()
        defer { try? FileManager.default.removeItem(at: root) }

        state.startNewProject()
        state.startNewProject()
        state.startNewProject()

        #expect(state.projects.map(\.name) == ["Untitled Project 3", "Untitled Project 2", "Untitled Project"])
    }
}
