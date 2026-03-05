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
    @Test("UpdaterService initializes with canCheckForUpdates ready")
    func updaterServiceInitializes() {
        // Arrange & Act
        let service = UpdaterService()

        // Assert - startingUpdater:true should make Sparkle ready immediately in direct builds
        #expect(service.canCheckForUpdates == true, "canCheckForUpdates should be true once Sparkle starts immediately")
    }

    @MainActor
    @Test("UpdaterService checkForUpdates can be called")
    func checkForUpdatesCanBeCalled() {
        // Arrange
        let service = UpdaterService()

        // Act - call checkForUpdates (in test environment, no actual update check happens)
        service.checkForUpdates()

        // Assert - in the test environment Sparkle becomes briefly ready, then unavailable again
        // after a manual check because there is no real update feed/session to keep active.
        #expect(service.canCheckForUpdates == false, "canCheckForUpdates should fall back to false after a manual check in tests")
    }
}
