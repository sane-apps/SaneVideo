//
//  UpdaterServiceTests.swift
//  SaneVideoTests
//
//  Tests for UpdaterService - Sparkle auto-update integration
//

import Testing
import Foundation
@testable import SaneVideo

@Suite("UpdaterService Tests")
struct UpdaterServiceTests {

    // MARK: - Initialization Tests

    @MainActor
    @Test("UpdaterService initializes with canCheckForUpdates false")
    func updaterServiceInitializes() {
        // Arrange & Act
        let service = UpdaterService()

        // Assert - canCheckForUpdates starts false until Sparkle is ready
        // This is the expected initial state per UpdaterService.swift:21
        #expect(service.canCheckForUpdates == false, "canCheckForUpdates should be false initially")
    }

    @MainActor
    @Test("UpdaterService checkForUpdates can be called")
    func checkForUpdatesCanBeCalled() {
        // Arrange
        let service = UpdaterService()

        // Act - call checkForUpdates (in test environment, no actual update check happens)
        service.checkForUpdates()

        // Assert - after calling checkForUpdates, canCheckForUpdates should still be accessible
        // In test environment without valid appcast, it remains false
        #expect(service.canCheckForUpdates == false, "canCheckForUpdates should remain false in test environment")
    }
}
