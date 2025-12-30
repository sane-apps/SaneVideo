//
//  ProjectStateUndoRedoTests.swift
//  SaneVideoTests
//
//  Comprehensive tests for ProjectState undo/redo functionality
//

import Testing
import Foundation
@testable import SaneVideo

@Suite("ProjectState Undo/Redo Tests")
@MainActor
struct ProjectStateUndoRedoTests {

    // MARK: - Basic Undo/Redo Tests

    @Test("UndoManager nil does not crash on registerUndo")
    func undoManagerNilDoesNotCrash() {
        // Arrange
        let projectState = ProjectState()
        projectState.currentProject = VideoProject(name: "Test")
        // undoManager is nil by default

        // Act - should not crash
        projectState.registerUndo("Test Action")

        // Assert - no crash occurred, project still valid
        #expect(projectState.currentProject?.name == "Test")
    }

    @Test("UndoManager nil does not crash on beginUndoGroup")
    func undoManagerNilDoesNotCrashOnGroup() {
        // Arrange
        let projectState = ProjectState()
        projectState.currentProject = VideoProject(name: "Test")

        // Act - should not crash
        projectState.beginUndoGroup("Test Group")
        projectState.endUndoGroup()

        // Assert - no crash occurred
        #expect(projectState.currentProject != nil)
    }

    @Test("Basic undo restores previous state")
    func basicUndoRestoresPreviousState() {
        // Arrange
        let projectState = ProjectState()
        projectState.currentProject = VideoProject(name: "Original")
        let undoManager = UndoManager()
        projectState.undoManager = undoManager

        let originalName = projectState.currentProject?.name

        // Act
        projectState.renameProject("Renamed")
        #expect(projectState.currentProject?.name == "Renamed")

        undoManager.undo()

        // Assert
        #expect(projectState.currentProject?.name == originalName)
    }

    @Test("Basic redo restores undone state")
    func basicRedoRestoresUndoneState() {
        // Arrange
        let projectState = ProjectState()
        projectState.currentProject = VideoProject(name: "Original")
        let undoManager = UndoManager()
        projectState.undoManager = undoManager

        // Act
        projectState.renameProject("Renamed")
        undoManager.undo()
        undoManager.redo()

        // Assert
        #expect(projectState.currentProject?.name == "Renamed")
    }

    // MARK: - Multiple Undo Operations

    @Test("Multiple undo operations restore in correct order")
    func multipleUndoOperationsRestoreInOrder() {
        // Arrange
        let projectState = ProjectState()
        projectState.currentProject = VideoProject(name: "Name1")
        let undoManager = UndoManager()
        projectState.undoManager = undoManager

        // Act - perform 3 renames
        projectState.renameProject("Name2")
        projectState.renameProject("Name3")
        projectState.renameProject("Name4")

        // Assert - undo in reverse order
        #expect(projectState.currentProject?.name == "Name4")

        undoManager.undo()
        #expect(projectState.currentProject?.name == "Name3")

        undoManager.undo()
        #expect(projectState.currentProject?.name == "Name2")

        undoManager.undo()
        #expect(projectState.currentProject?.name == "Name1")
    }

    @Test("Undo then new action clears redo stack")
    func undoThenNewActionClearsRedoStack() {
        // Arrange
        let projectState = ProjectState()
        projectState.currentProject = VideoProject(name: "Original")
        let undoManager = UndoManager()
        projectState.undoManager = undoManager

        // Act
        projectState.renameProject("First")
        projectState.renameProject("Second")
        undoManager.undo() // back to "First"

        // New action should clear redo stack
        projectState.renameProject("NewBranch")

        // Assert - redo should not work (stack cleared)
        #expect(undoManager.canRedo == false)
        #expect(projectState.currentProject?.name == "NewBranch")
    }

    // MARK: - Undo Groups

    @Test("Undo group combines multiple operations")
    func undoGroupCombinesOperations() {
        // Arrange
        let projectState = ProjectState()
        projectState.currentProject = VideoProject(name: "Original")
        let undoManager = UndoManager()
        projectState.undoManager = undoManager

        let originalOffset = projectState.currentProject?.captionOffset ?? .zero

        // Act - multiple operations in one group
        projectState.beginUndoGroup("Batch Edit")
        projectState.updateCaptionOffset(CGSize(width: 10, height: 20))
        projectState.updateCaptionFont("Helvetica")
        projectState.endUndoGroup()

        // Single undo should revert all changes
        undoManager.undo()

        // Assert
        #expect(projectState.currentProject?.captionOffset == originalOffset)
        #expect(projectState.currentProject?.captionFontName == nil)
    }

    // MARK: - Edge Cases

    @Test("Undo with no project does not crash")
    func undoWithNoProjectDoesNotCrash() {
        // Arrange
        let projectState = ProjectState()
        // currentProject is nil
        let undoManager = UndoManager()
        projectState.undoManager = undoManager

        // Act - should not crash
        projectState.registerUndo("Test")

        // Assert
        #expect(projectState.currentProject == nil)
    }

    @Test("Rapid sequential edits all tracked for undo")
    func rapidSequentialEditsTracked() {
        // Arrange
        let projectState = ProjectState()
        projectState.currentProject = VideoProject(name: "Start")
        let undoManager = UndoManager()
        projectState.undoManager = undoManager

        // Act - 10 rapid edits
        for i in 1...10 {
            projectState.renameProject("Edit\(i)")
        }

        // Assert - can undo all 10
        #expect(projectState.currentProject?.name == "Edit10")

        for i in stride(from: 9, through: 0, by: -1) {
            undoManager.undo()
            let expected = i == 0 ? "Start" : "Edit\(i)"
            #expect(projectState.currentProject?.name == expected)
        }
    }

    // MARK: - Caption Offset Tests (verify existing functionality)

    @Test("Caption offset undo restores zero offset")
    func captionOffsetUndoRestoresZero() {
        // Arrange
        let projectState = ProjectState()
        projectState.currentProject = VideoProject(name: "Test")
        let undoManager = UndoManager()
        projectState.undoManager = undoManager

        let newOffset = CGSize(width: 100, height: 200)

        // Act
        projectState.updateCaptionOffset(newOffset)
        #expect(projectState.currentProject?.captionOffset == newOffset)

        undoManager.undo()

        // Assert
        #expect(projectState.currentProject?.captionOffset == .zero)
    }

    // MARK: - Transaction Interaction Tests

    @Test("Undo registration during transaction succeeds")
    func undoRegistrationDuringTransactionSucceeds() {
        // Arrange
        let projectState = ProjectState()
        projectState.currentProject = VideoProject(name: "Original")
        let undoManager = UndoManager()
        projectState.undoManager = undoManager

        // Act - start transaction, make change with undo, end transaction
        let transactionId = projectState.beginTransaction()
        projectState.renameProject("During Transaction")
        projectState.endTransaction(transactionId)

        // Assert - undo should work even for changes made during transaction
        #expect(projectState.currentProject?.name == "During Transaction")
        undoManager.undo()
        #expect(projectState.currentProject?.name == "Original")
    }

    @Test("Transaction does not block undo")
    func transactionDoesNotBlockUndo() {
        // Arrange
        let projectState = ProjectState()
        projectState.currentProject = VideoProject(name: "Original")
        let undoManager = UndoManager()
        projectState.undoManager = undoManager

        // Make a change before transaction
        projectState.renameProject("Before Transaction")

        // Act - start transaction (simulating long operation)
        let transactionId = projectState.beginTransaction()

        // Undo should still work during transaction
        undoManager.undo()

        projectState.endTransaction(transactionId)

        // Assert
        #expect(projectState.currentProject?.name == "Original")
    }

    // MARK: - UndoManager State Tests

    @Test("canUndo returns true after operation")
    func canUndoReturnsTrueAfterOperation() {
        // Arrange
        let projectState = ProjectState()
        projectState.currentProject = VideoProject(name: "Test")
        let undoManager = UndoManager()
        projectState.undoManager = undoManager

        #expect(undoManager.canUndo == false)

        // Act
        projectState.renameProject("Changed")

        // Assert
        #expect(undoManager.canUndo == true)
    }

    @Test("canRedo returns true after undo")
    func canRedoReturnsTrueAfterUndo() {
        // Arrange
        let projectState = ProjectState()
        projectState.currentProject = VideoProject(name: "Test")
        let undoManager = UndoManager()
        projectState.undoManager = undoManager

        projectState.renameProject("Changed")
        #expect(undoManager.canRedo == false)

        // Act
        undoManager.undo()

        // Assert
        #expect(undoManager.canRedo == true)
    }

    @Test("undoActionName returns registered action name")
    func undoActionNameReturnsRegisteredName() {
        // Arrange
        let projectState = ProjectState()
        projectState.currentProject = VideoProject(name: "Test")
        let undoManager = UndoManager()
        projectState.undoManager = undoManager

        // Act
        projectState.renameProject("NewName")

        // Assert - action name should be set
        // Note: renameProject registers "Rename Project" as action name
        #expect(undoManager.undoActionName == "Rename Project")
    }

    // MARK: - Stress Tests

    @Test("Many undo operations do not cause memory issues")
    func manyUndoOperationsMemoryStable() {
        // Arrange
        let projectState = ProjectState()
        projectState.currentProject = VideoProject(name: "Start")
        let undoManager = UndoManager()
        // Set a reasonable levels limit to prevent unbounded memory growth
        undoManager.levelsOfUndo = 50
        projectState.undoManager = undoManager

        // Act - perform 100 edits (only last 50 should be undoable)
        for i in 1...100 {
            projectState.renameProject("Edit\(i)")
        }

        // Assert - can undo up to 50 times
        var undoCount = 0
        while undoManager.canUndo {
            undoManager.undo()
            undoCount += 1
        }

        // Should have been able to undo approximately levelsOfUndo times
        #expect(undoCount <= 50)
        #expect(undoCount > 0)
    }
}
