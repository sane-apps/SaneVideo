// Bulk project deletion from the project list.

import Foundation
@testable import SaneVideo
import Testing

/// Deletion runs in an unstructured task; wait for its effect instead of a fixed delay.
@MainActor
private func waitUntil(timeout: Duration = .seconds(5), _ condition: () -> Bool) async -> Bool {
    let clock = ContinuousClock()
    let deadline = clock.now.advanced(by: timeout)
    while !condition() {
        if clock.now >= deadline {
            return false
        }
        try? await Task.sleep(for: .milliseconds(10))
    }
    return true
}

@Suite("Bulk Project Operations Tests")
@MainActor
struct BulkProjectOperationsTests {
    private func makeState(projectCount: Int) throws -> (ProjectState, URL) {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("ProjectSelectionTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let state = ProjectState(projectStore: ProjectStore(rootDirectory: root))
        for _ in 0 ..< projectCount {
            state.startNewProject()
        }
        return (state, root)
    }

    @Test("Deleting a selection removes exactly those projects")
    func deleteProjectsRemovesMultiple() async throws {
        let (projectState, root) = try makeState(projectCount: 3)
        defer { try? FileManager.default.removeItem(at: root) }

        let idsToDelete = Set(projectState.projects.prefix(2).map(\.id))
        let survivor = try #require(projectState.projects.last?.id)

        projectState.deleteProjects(idsToDelete)

        let removed = await waitUntil { projectState.projects.count == 1 }
        #expect(removed)
        #expect(projectState.projects.map(\.id) == [survivor])
    }

    @Test("Deleting the open project switches to another project")
    func deleteProjectsSwitchesCurrentIfDeleted() async throws {
        let (projectState, root) = try makeState(projectCount: 2)
        defer { try? FileManager.default.removeItem(at: root) }

        let currentId = try #require(projectState.currentProject?.id)
        let otherId = try #require(projectState.projects.first { $0.id != currentId }?.id)

        projectState.deleteProjects([currentId])

        let switched = await waitUntil { projectState.currentProject?.id != currentId }
        #expect(switched)
        #expect(projectState.currentProject?.id == otherId)
    }

    @Test("Clear all removes every project and opens one fresh project")
    func clearAllProjectsRemovesAllAndCreatesNew() async throws {
        let (projectState, root) = try makeState(projectCount: 3)
        defer { try? FileManager.default.removeItem(at: root) }

        let oldIds = Set(projectState.projects.map(\.id))

        projectState.clearAllProjects()

        let cleared = await waitUntil {
            projectState.projects.count == 1 && !oldIds.contains(projectState.projects[0].id)
        }
        #expect(cleared)
        #expect(projectState.currentProject?.id == projectState.projects.first?.id)
    }

    @Test("Deleting an empty selection leaves the list unchanged")
    func deleteEmptySelectionDoesNothing() throws {
        let (projectState, root) = try makeState(projectCount: 1)
        defer { try? FileManager.default.removeItem(at: root) }
        let before = projectState.projects.map(\.id)

        // deleteProjects returns before scheduling any work when nothing matches.
        projectState.deleteProjects([])

        #expect(projectState.projects.map(\.id) == before)
    }
}
