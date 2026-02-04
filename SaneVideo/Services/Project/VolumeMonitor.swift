//
//  VolumeMonitor.swift
//  SaneVideo
//
//  Monitors external drive mount/unmount events to warn users when media becomes unavailable.
//  Critical for projects with clips stored on external drives.
//

import AppKit
import Foundation
import Observation

/// Monitors volume mount/unmount events to protect user data.
/// Warns when external drives containing project media are unmounted.
@MainActor
@Observable
final class VolumeMonitor {
    /// Shared singleton instance.
    static let shared = VolumeMonitor()

    /// Currently mounted volume paths.
    private(set) var mountedVolumes: Set<String> = []

    /// URLs of clips that became unavailable due to unmount.
    private(set) var unavailableClipURLs: Set<URL> = []

    /// Whether any project clips are currently unavailable.
    var hasUnavailableClips: Bool {
        !unavailableClipURLs.isEmpty
    }

    /// Callback triggered when volumes change (for external observers).
    var onVolumeChange: ((VolumeChangeEvent) -> Void)?

    // MARK: - Volume Change Events

    enum VolumeChangeEvent: Sendable {
        case mounted(path: String)
        case unmounted(path: String)
        case clipsUnavailable(urls: [URL])
        case clipsRestored(urls: [URL])
    }

    // MARK: - Initialization

    private init() {
        refreshMountedVolumes()
        setupMonitoring()
    }

    // MARK: - Public API

    /// Check if a URL is on an external (removable) volume.
    nonisolated func isOnExternalVolume(_ url: URL) -> Bool {
        // Resolve symlinks and get the actual path
        let resolvedPath = url.resolvingSymlinksInPath().path

        // Check if path starts with /Volumes/ (external drives)
        // Exclude /Volumes/Macintosh HD which is the boot volume
        if resolvedPath.hasPrefix("/Volumes/") {
            let components = resolvedPath.split(separator: "/")
            if components.count >= 2 {
                let volumeName = String(components[1])
                // Boot volume is typically "Macintosh HD" but can vary
                // Check if it's actually removable
                return isRemovableVolume(volumeName)
            }
        }
        return false
    }

    /// Check if a specific volume is currently mounted.
    func isVolumeMounted(_ volumePath: String) -> Bool {
        mountedVolumes.contains(volumePath)
    }

    /// Register clip URLs to monitor for availability.
    /// Call this when loading a project to track which clips might become unavailable.
    func registerClipURLs(_ urls: [URL]) {
        for url in urls where isOnExternalVolume(url) {
            let volumePath = extractVolumePath(from: url)
            if !mountedVolumes.contains(volumePath) {
                unavailableClipURLs.insert(url)
            }
        }
    }

    /// Clear all tracked clip URLs (call when closing project).
    func clearTrackedClips() {
        unavailableClipURLs.removeAll()
    }

    // MARK: - Private Implementation

    private func setupMonitoring() {
        let workspace = NSWorkspace.shared

        // Monitor volume mounts
        workspace.notificationCenter.addObserver(
            forName: NSWorkspace.didMountNotification,
            object: nil,
            queue: nil
        ) { [weak self] notification in
            // Extract Sendable values before crossing concurrency boundary
            guard let volumeURL = notification.userInfo?[NSWorkspace.volumeURLUserInfoKey] as? URL else { return }
            let path = volumeURL.path
            Task { @MainActor in
                self?.handleVolumeMount(path: path)
            }
        }

        // Monitor volume unmounts
        workspace.notificationCenter.addObserver(
            forName: NSWorkspace.didUnmountNotification,
            object: nil,
            queue: nil
        ) { [weak self] notification in
            // Extract Sendable values before crossing concurrency boundary
            guard let volumeURL = notification.userInfo?[NSWorkspace.volumeURLUserInfoKey] as? URL else { return }
            let path = volumeURL.path
            Task { @MainActor in
                self?.handleVolumeUnmount(path: path)
            }
        }

        // Monitor upcoming unmounts (gives us warning before unmount completes)
        workspace.notificationCenter.addObserver(
            forName: NSWorkspace.willUnmountNotification,
            object: nil,
            queue: nil
        ) { [weak self] notification in
            // Extract Sendable values before crossing concurrency boundary
            guard let volumeURL = notification.userInfo?[NSWorkspace.volumeURLUserInfoKey] as? URL else { return }
            let path = volumeURL.path
            let volumeName = volumeURL.lastPathComponent
            Task { @MainActor in
                self?.handleVolumeWillUnmount(path: path, volumeName: volumeName)
            }
        }
    }

    private func handleVolumeMount(path: String) {
        mountedVolumes.insert(path)
        AppLogger.project.info("📀 VolumeMonitor: Volume mounted: \(path)")

        // Check if any unavailable clips are now available
        let restoredClips = unavailableClipURLs.filter { clipURL in
            clipURL.path.hasPrefix(path)
        }

        if !restoredClips.isEmpty {
            unavailableClipURLs.subtract(restoredClips)
            AppLogger.project.info("📀 VolumeMonitor: \(restoredClips.count) clips restored")
            onVolumeChange?(.clipsRestored(urls: Array(restoredClips)))

            // Notify user (already on MainActor)
            ServiceContainer.shared.toastManager.show(
                "External drive reconnected - \(restoredClips.count) clip(s) restored",
                type: .success
            )
        }

        onVolumeChange?(.mounted(path: path))
    }

    private func handleVolumeUnmount(path: String) {
        mountedVolumes.remove(path)
        AppLogger.project.warning("📀 VolumeMonitor: Volume unmounted: \(path)")

        onVolumeChange?(.unmounted(path: path))
    }

    private func handleVolumeWillUnmount(path: String, volumeName: String) {
        AppLogger.project.warning("📀 VolumeMonitor: Volume will unmount: \(path)")

        // Check if any tracked project clips will become unavailable
        // This would require integration with ProjectState to get current clip URLs
        // For now, log a warning - full integration happens in ProjectState

        // Notify UI that a volume is about to unmount
        ServiceContainer.shared.toastManager.show(
            "External drive '\(volumeName)' is being ejected",
            type: .info
        )
    }

    private func refreshMountedVolumes() {
        let fileManager = FileManager.default
        guard let volumeURLs = fileManager.mountedVolumeURLs(
            includingResourceValuesForKeys: [.volumeIsRemovableKey, .volumeIsEjectableKey],
            options: [.skipHiddenVolumes]
        ) else {
            return
        }

        mountedVolumes = Set(volumeURLs.map { $0.path })
        AppLogger.project.info("📀 VolumeMonitor: Initialized with \(mountedVolumes.count) mounted volumes")
    }

    private nonisolated func isRemovableVolume(_ volumeName: String) -> Bool {
        let volumeURL = URL(fileURLWithPath: "/Volumes/\(volumeName)")
        do {
            let resourceValues = try volumeURL.resourceValues(forKeys: [.volumeIsRemovableKey, .volumeIsEjectableKey])
            return (resourceValues.volumeIsRemovable ?? false) || (resourceValues.volumeIsEjectable ?? false)
        } catch {
            // If we can't determine, assume external if in /Volumes/
            return true
        }
    }

    private func extractVolumePath(from url: URL) -> String {
        let path = url.path
        if path.hasPrefix("/Volumes/") {
            let components = path.split(separator: "/")
            if components.count >= 2 {
                return "/Volumes/\(components[1])"
            }
        }
        return path
    }
}
