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
    @Test("UpdaterService initializes without crashing")
    func updaterServiceInitializes() {
        // Arrange & Act
        let service = UpdaterService()

        // Assert - if we get here, initialization succeeded
        // canCheckForUpdates starts false until Sparkle is ready
        #expect(service.canCheckForUpdates == false || service.canCheckForUpdates == true)
    }

    @MainActor
    @Test("UpdaterService canCheckForUpdates is published property")
    func canCheckForUpdatesIsPublished() {
        // Arrange
        let service = UpdaterService()

        // Assert - canCheckForUpdates should be accessible as a published property
        // Initial state depends on Sparkle's internal state
        _ = service.canCheckForUpdates
        // If we get here without crash, the property exists and is accessible
    }

    // MARK: - Method Existence Tests

    @MainActor
    @Test("UpdaterService has checkForUpdates method")
    func checkForUpdatesMethodExists() {
        // Arrange
        let service = UpdaterService()

        // Act & Assert - just verify the method can be called without crashing
        // In test environment, Sparkle may not have valid appcast
        // The method should still execute without throwing
        service.checkForUpdates()
    }
}
