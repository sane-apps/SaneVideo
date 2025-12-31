//
//  UpdaterService.swift
//  SaneVideo
//
//  Sparkle auto-update integration with Swift 6 strict concurrency
//

import Combine
import Sparkle
import SwiftUI

/// Sparkle updater wrapper with @MainActor isolation for Swift 6 compatibility
/// SPUStandardUpdaterController must be accessed from main thread only
@MainActor
@Observable
final class UpdaterService {
    private let updaterController: SPUStandardUpdaterController
    private var cancellable: AnyCancellable?

    /// Whether the updater can currently check for updates
    private(set) var canCheckForUpdates = false

    init() {
        // Initialize Sparkle updater (manual-only to avoid blocking UI on startup)
        // startingUpdater: false = No automatic checks (user must click "Check for Updates")
        // CRITICAL: startingUpdater: true with invalid/placeholder SUPublicEDKey causes
        // modal error dialog that blocks camera initialization
        self.updaterController = SPUStandardUpdaterController(
            startingUpdater: false,
            updaterDelegate: nil,
            userDriverDelegate: nil
        )

        // Observe canCheckForUpdates changes via Combine sink
        cancellable = updaterController.updater.publisher(for: \.canCheckForUpdates)
            .sink { [weak self] value in
                self?.canCheckForUpdates = value
            }
    }

    /// Manually trigger an update check
    /// Shows standard Sparkle UI with update dialog or "no updates available" message
    func checkForUpdates() {
        updaterController.checkForUpdates(nil)
    }
}
