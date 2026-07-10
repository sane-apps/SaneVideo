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

    enum SaneVideoUpdateCheckFrequency: String, CaseIterable, Identifiable, Sendable {
        case daily
        case weekly

        var id: String { rawValue }

        var title: String {
            switch self {
            case .daily: "Daily"
            case .weekly: "Weekly"
            }
        }

        var interval: TimeInterval {
            switch self {
            case .daily: 60 * 60 * 24
            case .weekly: 60 * 60 * 24 * 7
            }
        }

        static func resolve(updateCheckInterval: TimeInterval) -> Self {
            let threshold = (Self.daily.interval + Self.weekly.interval) / 2
            return updateCheckInterval >= threshold ? .weekly : .daily
        }

        static func normalizedInterval(from updateCheckInterval: TimeInterval) -> TimeInterval {
            resolve(updateCheckInterval: updateCheckInterval).interval
        }
    }

    /// Sparkle updater wrapper with @MainActor isolation for Swift 6 compatibility
    @MainActor
    @Observable
    final class UpdaterService {
        private let updateFeedURL = Bundle.main.object(forInfoDictionaryKey: "SUFeedURL")
            .flatMap { $0 as? String }
            .flatMap(URL.init(string:))
        private let updaterController: SPUStandardUpdaterController
        private var cancellable: AnyCancellable?

        private(set) var canCheckForUpdates = false

        init() {
            updaterController = SPUStandardUpdaterController(
                startingUpdater: true,
                updaterDelegate: nil,
                userDriverDelegate: nil
            )
            updaterController.updater.updateCheckInterval = SaneVideoUpdateCheckFrequency.normalizedInterval(from: updaterController.updater.updateCheckInterval)
            cancellable = updaterController.updater.publisher(for: \.canCheckForUpdates)
                .sink { [weak self] value in
                    self?.canCheckForUpdates = value
                }
        }

        func checkForUpdates() {
            Task { @MainActor in
                guard await hasLiveAppcastFeed() else {
                    ServiceContainer.shared.toastManager.show(
                        "Automatic updates are not configured for this build yet. Install newer builds manually for now.",
                        type: .info
                    )
                    return
                }

                updaterController.checkForUpdates(nil)
            }
        }

        var automaticallyChecksForUpdates: Bool {
            get { updaterController.updater.automaticallyChecksForUpdates }
            set { updaterController.updater.automaticallyChecksForUpdates = newValue }
        }

        var updateCheckFrequency: SaneVideoUpdateCheckFrequency {
            get { SaneVideoUpdateCheckFrequency.resolve(updateCheckInterval: updaterController.updater.updateCheckInterval) }
            set { updaterController.updater.updateCheckInterval = newValue.interval }
        }

        private func hasLiveAppcastFeed() async -> Bool {
            guard let updateFeedURL else { return false }

            var request = URLRequest(url: updateFeedURL)
            request.timeoutInterval = 4
            request.setValue("application/xml,text/xml,application/rss+xml,*/*;q=0.1", forHTTPHeaderField: "Accept")

            do {
                let (data, response) = try await URLSession.shared.data(for: request)
                guard let httpResponse = response as? HTTPURLResponse,
                      (200..<300).contains(httpResponse.statusCode) else {
                    return false
                }

                return Self.looksLikeAppcastFeed(data)
            } catch {
                return false
            }
        }

        nonisolated static func looksLikeAppcastFeed(_ data: Data) -> Bool {
            let preview = String(bytes: data.prefix(2048), encoding: .utf8)?.lowercased() ?? ""
            return preview.contains("<rss") || preview.contains("<channel") || preview.contains("<item")
        }
    }
#else
    import SwiftUI

    /// No-op stub — App Store handles updates.
    @MainActor
    @Observable
    final class UpdaterService {
        private(set) var canCheckForUpdates = true
        init() {}
        func checkForUpdates() {
            ServiceContainer.shared.toastManager.show(
                "Automatic updates are handled through the App Store for this build.",
                type: .info
            )
        }
        var automaticallyChecksForUpdates: Bool {
            get { false }
            set { _ = newValue }
        }
    }
#endif
