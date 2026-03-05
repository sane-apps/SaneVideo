//
//  UpdaterService.swift
//  SaneVideo
//
//  Sparkle auto-update integration with Swift 6 strict concurrency
//

#if !APP_STORE
    import Combine
    import Sparkle
    import SaneUI
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
                startingUpdater: true,
                updaterDelegate: nil,
                userDriverDelegate: nil
            )
            updaterController.updater.updateCheckInterval = SaneSparkleCheckFrequency.normalizedInterval(from: updaterController.updater.updateCheckInterval)
            cancellable = updaterController.updater.publisher(for: \.canCheckForUpdates)
                .sink { [weak self] value in
                    self?.canCheckForUpdates = value
                }
        }

        func checkForUpdates() {
            updaterController.checkForUpdates(nil)
        }

        var automaticallyChecksForUpdates: Bool {
            get { updaterController.updater.automaticallyChecksForUpdates }
            set { updaterController.updater.automaticallyChecksForUpdates = newValue }
        }

        var updateCheckFrequency: SaneSparkleCheckFrequency {
            get { SaneSparkleCheckFrequency.resolve(updateCheckInterval: updaterController.updater.updateCheckInterval) }
            set { updaterController.updater.updateCheckInterval = newValue.interval }
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
        var automaticallyChecksForUpdates: Bool {
            get { false }
            set {}
        }
    }
#endif
