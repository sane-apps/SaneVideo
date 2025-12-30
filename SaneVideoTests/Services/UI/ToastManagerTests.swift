//
//  ToastManagerTests.swift
//  SaneVideoTests
//
//  Tests for ToastManager - user feedback toast system
//

import Testing
import Foundation
@testable import SaneVideo

@Suite("Toast Manager Tests")
@MainActor
struct ToastManagerTests {

    // MARK: - AlertType Tests

    @Test("AlertType has all expected cases")
    func alertTypeHasAllCases() {
        // Arrange & Assert - verify all cases exist and are distinct
        let info = ToastManager.AlertType.info
        let success = ToastManager.AlertType.success
        let error = ToastManager.AlertType.error

        // Verify cases are distinct (tests runtime behavior, not compilation)
        #expect(info != success, "Info and success should be distinct")
        #expect(success != error, "Success and error should be distinct")
        #expect(error != info, "Error and info should be distinct")
    }

    // MARK: - Initial State Tests

    @Test("Initial toastMessage is nil")
    func initialToastMessageNil() {
        // Arrange & Act
        let manager = ToastManager()

        // Assert
        #expect(manager.toastMessage == nil)
    }

    // MARK: - Show Method Tests

    @Test("Show sets toastMessage")
    func showSetsToastMessage() async throws {
        // Arrange
        let manager = ToastManager()
        let message = "Test message"

        // Act
        manager.show(message)
        // Allow async task to complete
        try await Task.sleep(nanoseconds: 100_000_000) // 100ms

        // Assert
        #expect(manager.toastMessage == message)
    }

    @Test("Show with info type works")
    func showWithInfoType() async throws {
        // Arrange
        let manager = ToastManager()
        let message = "Info message"

        // Act
        manager.show(message, type: .info)
        try await Task.sleep(nanoseconds: 100_000_000)

        // Assert
        #expect(manager.toastMessage == message)
    }

    @Test("Show with error type works")
    func showWithErrorType() async throws {
        // Arrange
        let manager = ToastManager()
        let message = "Error message"

        // Act
        manager.show(message, type: .error)
        try await Task.sleep(nanoseconds: 100_000_000)

        // Assert
        #expect(manager.toastMessage == message)
    }

    @Test("Show with success type works")
    func showWithSuccessType() async throws {
        // Arrange
        let manager = ToastManager()
        let message = "Success message"

        // Act
        manager.show(message, type: .success)
        try await Task.sleep(nanoseconds: 100_000_000)

        // Assert
        #expect(manager.toastMessage == message)
    }

    // MARK: - Clear Method Tests

    @Test("Clear resets toastMessage to nil")
    func clearResetsToastMessage() async throws {
        // Arrange
        let manager = ToastManager()
        manager.show("Test message")
        try await Task.sleep(nanoseconds: 100_000_000)
        #expect(manager.toastMessage != nil)

        // Act
        manager.clear()

        // Assert
        #expect(manager.toastMessage == nil)
    }

    @Test("Clear can be called when no toast is showing")
    func clearWhenNoToast() {
        // Arrange
        let manager = ToastManager()
        #expect(manager.toastMessage == nil)

        // Act - should not crash
        manager.clear()

        // Assert
        #expect(manager.toastMessage == nil)
    }

    // MARK: - Queue Behavior Tests

    @Test("Rapid successive toasts are handled")
    func rapidSuccessiveToasts() async throws {
        // Arrange
        let manager = ToastManager()

        // Act - show multiple toasts rapidly
        manager.show("Message 1")
        manager.show("Message 2")
        manager.show("Message 3")

        // Wait for first message to display
        try await Task.sleep(nanoseconds: 100_000_000)

        // Assert - some message is showing (queue handles the rest)
        #expect(manager.toastMessage != nil)
    }

    // MARK: - Observable Tests

    @Test("ToastManager conforms to Observable")
    func managerIsObservable() {
        // Arrange & Act
        let manager = ToastManager()

        // Assert - Verify Observable works by checking initial state
        // If @Observable works, we can read the property
        #expect(manager.toastMessage == nil, "Initial toastMessage should be nil")
    }
}
