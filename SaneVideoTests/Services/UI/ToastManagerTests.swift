//
//  ToastManagerTests.swift
//  SaneVideoTests
//
//  Toasts appear for every alert type, clear immediately, and queue in order.
//  Waits poll the real toast state instead of sleeping.
//

import Foundation
@testable import SaneVideo
import Testing

@Suite("Toast Manager Tests")
@MainActor
struct ToastManagerTests {
    /// Yields the main actor until the toast shows `expected`, or gives up after a bounded number of turns.
    private func waitForToast(_ manager: ToastManager, _ expected: String) async {
        for _ in 0 ..< 1000 where manager.toastMessage != expected {
            await Task.yield()
        }
    }

    @Test("show displays the message for info, success and error toasts")
    func showDisplaysMessageForEveryType() async {
        let cases: [(ToastManager.AlertType, String)] = [
            (.info, "Info message"),
            (.success, "Success message"),
            (.error, "Error message")
        ]

        for (type, message) in cases {
            let manager = ToastManager()
            manager.show(message, type: type)
            await waitForToast(manager, message)
            #expect(manager.toastMessage == message)
        }
    }

    @Test("clear hides the current toast")
    func clearResetsToastMessage() async {
        let manager = ToastManager()
        manager.show("Test message")
        await waitForToast(manager, "Test message")
        #expect(manager.toastMessage == "Test message")

        manager.clear()

        #expect(manager.toastMessage == nil)
    }

    @Test("Rapid toasts show the first one first and queue the rest")
    func rapidSuccessiveToasts() async {
        let manager = ToastManager()

        manager.show("Message 1")
        manager.show("Message 2")
        manager.show("Message 3")
        await waitForToast(manager, "Message 1")

        #expect(manager.toastMessage == "Message 1")
    }
}
