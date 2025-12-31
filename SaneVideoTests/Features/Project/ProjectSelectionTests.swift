//
//  ProjectSelectionTests.swift
//  SaneVideoTests
//
//  Tests for project multi-selection and bulk operations
//

import Testing
@testable import SaneVideo
import Foundation

@Suite("Project Selection Tests")
@MainActor
struct ProjectSelectionTests {

    // MARK: - Selection State Tests

    @Test("Selected project IDs starts empty")
    func selectedProjectIdsStartsEmpty() async {
        let appState = AppState()
        #expect(appState.selectedProjectIds.isEmpty)
    }

    @Test("Can add project to selection")
    func canAddProjectToSelection() async {
        let appState = AppState()
        let projectId = UUID()

        appState.selectedProjectIds.insert(projectId)

        #expect(appState.selectedProjectIds.contains(projectId))
        #expect(appState.selectedProjectIds.count == 1)
    }

    @Test("Can remove project from selection")
    func canRemoveProjectFromSelection() async {
        let appState = AppState()
        let projectId = UUID()

        appState.selectedProjectIds.insert(projectId)
        appState.selectedProjectIds.remove(projectId)

        #expect(!appState.selectedProjectIds.contains(projectId))
        #expect(appState.selectedProjectIds.isEmpty)
    }

    @Test("Can select multiple projects")
    func canSelectMultipleProjects() async {
        let appState = AppState()
        let id1 = UUID()
        let id2 = UUID()
        let id3 = UUID()

        appState.selectedProjectIds = [id1, id2, id3]

        #expect(appState.selectedProjectIds.count == 3)
        #expect(appState.selectedProjectIds.contains(id1))
        #expect(appState.selectedProjectIds.contains(id2))
        #expect(appState.selectedProjectIds.contains(id3))
    }

    @Test("Clear all removes all selections")
    func clearAllRemovesAllSelections() async {
        let appState = AppState()
        let id1 = UUID()
        let id2 = UUID()

        appState.selectedProjectIds = [id1, id2]
        appState.selectedProjectIds.removeAll()

        #expect(appState.selectedProjectIds.isEmpty)
    }
}

@Suite("Bulk Project Operations Tests")
@MainActor
struct BulkProjectOperationsTests {

    @Test("Delete projects removes multiple projects")
    func deleteProjectsRemovesMultiple() async throws {
        let projectState = ProjectState()

        // Create test projects
        projectState.startNewProject()
        projectState.startNewProject()
        projectState.startNewProject()

        let initialCount = projectState.projects.count
        #expect(initialCount >= 3)

        // Get IDs of first two projects
        let idsToDelete = Set(projectState.projects.prefix(2).map { $0.id })

        // Delete them
        projectState.deleteProjects(idsToDelete)

        // Wait for async deletion
        try await Task.sleep(for: .milliseconds(500))

        // Verify projects were removed
        for id in idsToDelete {
            #expect(!projectState.projects.contains(where: { $0.id == id }))
        }
    }

    @Test("Delete projects switches current project if deleted")
    func deleteProjectsSwitchesCurrentIfDeleted() async throws {
        let projectState = ProjectState()

        // Create test projects
        projectState.startNewProject()
        projectState.startNewProject()

        let currentId = projectState.currentProject?.id
        #expect(currentId != nil)

        // Delete current project
        projectState.deleteProjects([currentId!])

        // Wait for async deletion
        try await Task.sleep(for: .milliseconds(500))

        // Current project should have changed
        #expect(projectState.currentProject?.id != currentId)
    }

    @Test("Clear all projects removes all and creates new")
    func clearAllProjectsRemovesAllAndCreatesNew() async throws {
        let projectState = ProjectState()

        // Create multiple projects
        projectState.startNewProject()
        projectState.startNewProject()
        projectState.startNewProject()

        #expect(projectState.projects.count >= 3)

        // Clear all
        projectState.clearAllProjects()

        // Wait for async deletion
        try await Task.sleep(for: .milliseconds(500))

        // Should have exactly 1 new project
        #expect(projectState.projects.count == 1)
        #expect(projectState.currentProject != nil)
    }

    @Test("Delete empty selection does nothing")
    func deleteEmptySelectionDoesNothing() async throws {
        let projectState = ProjectState()

        projectState.startNewProject()
        let initialCount = projectState.projects.count

        // Delete empty set
        projectState.deleteProjects([])

        // Wait a bit
        try await Task.sleep(for: .milliseconds(100))

        // Count should be unchanged
        #expect(projectState.projects.count == initialCount)
    }
}
