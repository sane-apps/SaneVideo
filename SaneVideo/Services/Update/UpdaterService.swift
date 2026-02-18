//
//  UpdaterService.swift
//  SaneVideo
//
//  Sparkle auto-update integration with Swift 6 strict concurrency
//

#if !APP_STORE
    import Combine
    import Sparkle
    import SwiftUI

    /// Sparkle updater wrapper with @MainActor isolation for Swift 6 compatibility
    @MainActor
    @Observable
    final class UpdaterService {
        private let updaterController: SPUStandardUpdaterController
        private var cancellable: AnyCancellable?

        private(set) var canCheckForUpdates = false

        init() {
            updaterController = SPUStandardUpdaterController(
                startingUpdater: false,
                updaterDelegate: nil,
                userDriverDelegate: nil
            )
            cancellable = updaterController.updater.publisher(for: \.canCheckForUpdates)
                .sink { [weak self] value in
                    self?.canCheckForUpdates = value
                }
        }

        func checkForUpdates() {
            updaterController.checkForUpdates(nil)
        }
    }
#else
    import SwiftUI

    /// No-op stub — App Store handles updates.
    @MainActor
    @Observable
    final class UpdaterService {
        private(set) var canCheckForUpdates = false
        init() {}
        func checkForUpdates() {}
    }
#endif
