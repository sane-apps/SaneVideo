//
//  SyncManager.swift
//  SaneVideo
//
//  Manages project sync between Mac devices via iCloud Drive
//  Uses ubiquity containers for document sync (simpler than CloudKit for file-based projects)
//

import Combine
import Foundation

/// Sync status for a project
enum SyncStatus: String, Codable, Sendable {
    case local = "Local Only"
    case syncing = "Syncing..."
    case synced = "Synced"
    case conflict = "Conflict"
    case error = "Sync Error"

    var icon: String {
        switch self {
        case .local: return "externaldrive"
        case .syncing: return "arrow.triangle.2.circlepath"
        case .synced: return "checkmark.icloud"
        case .conflict: return "exclamationmark.icloud"
        case .error: return "xmark.icloud"
        }
    }
}

/// Sync event for UI updates
struct SyncEvent: Sendable {
    let projectId: UUID
    let status: SyncStatus
    let message: String?
    let timestamp: Date
}

/// Actor for coordinating project sync via iCloud Drive
actor SyncManager {

    // MARK: - Properties

    /// iCloud Documents container
    private let iCloudDocumentsURL: URL?

    /// Local projects directory
    private let localProjectsURL: URL

    /// Media asset manager for file handling
    private let mediaAssetManager: MediaAssetManager

    /// Debounce timer for sync operations
    private var syncDebounceTask: Task<Void, Never>?

    /// Current sync status per project
    private var projectSyncStatus: [UUID: SyncStatus] = [:]

    /// Projects pending sync
    private var pendingSyncs: Set<UUID> = []

    /// Publisher for sync events
    nonisolated(unsafe) let syncEventsSubject = PassthroughSubject<SyncEvent, Never>()

    // OPTIMIZATION: NSMetadataQuery for real-time iCloud change detection
    // Using nonisolated(unsafe) because NSMetadataQuery must be accessed from main thread
    nonisolated(unsafe) private var metadataQuery: NSMetadataQuery?
    nonisolated(unsafe) private var queryObservers: [NSObjectProtocol] = []

    /// Is iCloud sync enabled
    private var isSyncEnabled: Bool {
        get { UserDefaults.standard.bool(forKey: "iCloudSyncEnabled") }
        set { UserDefaults.standard.set(newValue, forKey: "iCloudSyncEnabled") }
    }

    init() {
        // Get iCloud container URL
        self.iCloudDocumentsURL = FileManager.default.url(
            forUbiquityContainerIdentifier: nil
        )?.appendingPathComponent("Documents/Projects", isDirectory: true)

        // Local projects directory
        self.localProjectsURL = FileManager.default.urls(
            for: .moviesDirectory,
            in: .userDomainMask
        ).first!.appendingPathComponent("SaneVideo/Projects", isDirectory: true)

        self.mediaAssetManager = MediaAssetManager()

        // Setup directories
        Task {
            await setupDirectories()
        }
    }

    // MARK: - Setup

    private func setupDirectories() async {
        let fm = FileManager.default

        // Create local directory
        try? fm.createDirectory(at: localProjectsURL, withIntermediateDirectories: true)

        // Create iCloud directory if available
        if let iCloudURL = iCloudDocumentsURL {
            try? fm.createDirectory(at: iCloudURL, withIntermediateDirectories: true)
        }
    }

    // MARK: - Sync Control

    /// Enable or disable iCloud sync
    func setSyncEnabled(_ enabled: Bool) async {
        isSyncEnabled = enabled

        if enabled {
            // Start monitoring and initial sync
            await startMonitoring()
        } else {
            // Stop sync operations
            syncDebounceTask?.cancel()
            pendingSyncs.removeAll()
        }
    }

    /// Check if sync is enabled
    func isSyncCurrentlyEnabled() -> Bool {
        isSyncEnabled
    }

    // MARK: - Project Sync

    /// Sync a project to iCloud
    /// - Parameter project: Project to sync
    func syncProject(_ project: VideoProject) async throws {
        guard isSyncEnabled else { return }
        guard let iCloudURL = iCloudDocumentsURL else {
            throw SyncError.iCloudNotAvailable
        }

        let projectId = project.id
        updateStatus(for: projectId, status: .syncing, message: "Starting sync...")

        do {
            // 1. Create project package directory
            let projectDir = iCloudURL.appendingPathComponent("\(projectId.uuidString).sanevideoproject", isDirectory: true)
            try FileManager.default.createDirectory(at: projectDir, withIntermediateDirectories: true)

            // 2. Export project metadata
            let metadataURL = projectDir.appendingPathComponent("project.json")
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            let data = try encoder.encode(project)
            try data.write(to: metadataURL)

            // 3. Copy media assets
            for track in project.timeline.tracks {
                for clip in track.clips {
                    _ = try await mediaAssetManager.copyAssetToProjectFolder(
                        sourceURL: clip.url,
                        projectId: projectId
                    )
                    updateStatus(for: projectId, status: .syncing, message: "Syncing: \(clip.url.lastPathComponent)")
                }
            }

            // 4. Update sync timestamp
            let syncInfo = SyncInfo(
                projectId: projectId,
                lastSynced: Date(),
                deviceName: Host.current().localizedName ?? "Unknown Mac",
                version: 1  // Version tracking not implemented yet
            )
            let syncInfoURL = projectDir.appendingPathComponent("sync_info.json")
            let syncData = try encoder.encode(syncInfo)
            try syncData.write(to: syncInfoURL)

            updateStatus(for: projectId, status: .synced, message: "Synced successfully")

        } catch {
            updateStatus(for: projectId, status: .error, message: error.localizedDescription)
            throw error
        }
    }

    /// Download a project from iCloud
    /// - Parameter projectId: Project ID to download
    /// - Returns: Downloaded project
    func downloadProject(projectId: UUID) async throws -> VideoProject {
        guard let iCloudURL = iCloudDocumentsURL else {
            throw SyncError.iCloudNotAvailable
        }

        updateStatus(for: projectId, status: .syncing, message: "Downloading...")

        let projectDir = iCloudURL.appendingPathComponent("\(projectId.uuidString).sanevideoproject", isDirectory: true)
        let metadataURL = projectDir.appendingPathComponent("project.json")

        // Ensure file is downloaded from iCloud
        if let resourceValues = try? metadataURL.resourceValues(forKeys: [.ubiquitousItemDownloadingStatusKey]),
           resourceValues.ubiquitousItemDownloadingStatus != .current {
            try FileManager.default.startDownloadingUbiquitousItem(at: metadataURL)

            // Wait for download
            var downloaded = false
            let timeout = Date().addingTimeInterval(60)
            while !downloaded && Date() < timeout {
                try await Task.sleep(nanoseconds: 500_000_000)
                if let values = try? metadataURL.resourceValues(forKeys: [.ubiquitousItemDownloadingStatusKey]) {
                    downloaded = values.ubiquitousItemDownloadingStatus == .current
                }
            }
        }

        let data = try Data(contentsOf: metadataURL)
        let project = try JSONDecoder().decode(VideoProject.self, from: data)

        updateStatus(for: projectId, status: .synced, message: "Downloaded successfully")

        return project
    }

    /// Queue a project for sync (debounced)
    func queueProjectForSync(_ projectId: UUID) async {
        guard isSyncEnabled else { return }

        pendingSyncs.insert(projectId)
        updateStatus(for: projectId, status: .syncing, message: "Pending sync...")

        // Debounce: wait 5 seconds after last change before syncing
        syncDebounceTask?.cancel()
        syncDebounceTask = Task {
            try? await Task.sleep(nanoseconds: 5_000_000_000)  // 5 seconds

            if !Task.isCancelled {
                await processPendingSyncs()
            }
        }
    }

    private func processPendingSyncs() async {
        let projectsToSync = pendingSyncs
        pendingSyncs.removeAll()

        // Get current projects from ProjectState
        // Note: In production, this would access the shared project store
        for projectId in projectsToSync {
            // Sync each project
            // Implementation would fetch project from store and call syncProject
            await MainActor.run {
                AppLogger.general.info("SyncManager: Would sync project \(projectId)")
            }
        }
    }

    // MARK: - Conflict Resolution

    /// Resolve sync conflict between local and remote versions
    func resolveConflict(
        projectId: UUID,
        localProject: VideoProject,
        remoteProject: VideoProject
    ) async -> VideoProject {
        // Simple strategy: most recent modification wins
        // Keep both versions by creating a backup

        if localProject.modifiedAt > remoteProject.modifiedAt {
            // Local is newer - keep local, backup remote
            await backupProject(remoteProject, suffix: "cloud-backup")
            updateStatus(for: projectId, status: .synced, message: "Conflict resolved: kept local version")
            return localProject
        } else {
            // Remote is newer - keep remote, backup local
            await backupProject(localProject, suffix: "local-backup")
            updateStatus(for: projectId, status: .synced, message: "Conflict resolved: updated from cloud")
            return remoteProject
        }
    }

    private func backupProject(_ project: VideoProject, suffix: String) async {
        let backupURL = localProjectsURL.appendingPathComponent(
            "\(project.id.uuidString)-\(suffix).sanevideoproject"
        )
        do {
            let encoder = JSONEncoder()
            encoder.outputFormatting = .prettyPrinted
            let data = try encoder.encode(project)
            try data.write(to: backupURL)
        } catch {
            await MainActor.run {
                AppLogger.general.error("Failed to backup project: \(error.localizedDescription)")
            }
        }
    }

    // MARK: - Monitoring

    private func startMonitoring() async {
        guard let iCloudURL = iCloudDocumentsURL else { return }

        // OPTIMIZATION: Use NSMetadataQuery for real-time iCloud change detection
        // This replaces polling and is more battery-efficient
        await MainActor.run { [weak self] in
            guard let self = self else { return }

            // Stop any existing query
            self.stopMetadataQuery()

            // Create and configure the query
            let query = NSMetadataQuery()
            query.searchScopes = [NSMetadataQueryUbiquitousDocumentsScope]

            // Match .sanevideoproject directories in iCloud
            query.predicate = NSPredicate(format: "%K LIKE '*.sanevideoproject'", NSMetadataItemFSNameKey)

            // Observe query updates - extract Sendable data on main thread, then update actor
            let updateObserver = NotificationCenter.default.addObserver(
                forName: .NSMetadataQueryDidUpdate,
                object: query,
                queue: .main
            ) { [weak self] _ in
                guard let self = self, let query = self.metadataQuery else { return }
                let updates = self.extractQueryResults(from: query)
                Task { await self.applyMetadataUpdates(updates) }
            }

            let finishObserver = NotificationCenter.default.addObserver(
                forName: .NSMetadataQueryDidFinishGathering,
                object: query,
                queue: .main
            ) { [weak self] _ in
                guard let self = self, let query = self.metadataQuery else { return }
                let updates = self.extractQueryResults(from: query)
                Task { await self.applyMetadataUpdates(updates) }
            }

            self.queryObservers = [updateObserver, finishObserver]
            self.metadataQuery = query

            // Start the query
            query.start()

            AppLogger.general.info("SyncManager: Started NSMetadataQuery monitoring for iCloud changes at \(iCloudURL.path)")
        }
    }

    /// Stop the metadata query and clean up observers
    nonisolated private func stopMetadataQuery() {
        metadataQuery?.stop()
        metadataQuery = nil

        for observer in queryObservers {
            NotificationCenter.default.removeObserver(observer)
        }
        queryObservers.removeAll()
    }

    /// Sendable update extracted from NSMetadataQuery results
    private struct MetadataUpdate: Sendable {
        let projectId: UUID
        let status: SyncStatus
        let message: String?
    }

    /// Extract Sendable data from query results (called on main thread)
    nonisolated private func extractQueryResults(from query: NSMetadataQuery) -> [MetadataUpdate] {
        query.disableUpdates()
        defer { query.enableUpdates() }

        var updates: [MetadataUpdate] = []

        for i in 0..<query.resultCount {
            guard let item = query.result(at: i) as? NSMetadataItem else { continue }
            guard let url = item.value(forAttribute: NSMetadataItemURLKey) as? URL else { continue }

            let filename = url.deletingPathExtension().lastPathComponent
            guard let projectId = UUID(uuidString: filename) else { continue }

            // Check for conflicts
            if let isConflicted = item.value(forAttribute: NSMetadataUbiquitousItemHasUnresolvedConflictsKey) as? Bool,
               isConflicted {
                updates.append(MetadataUpdate(projectId: projectId, status: .conflict, message: "Sync conflict detected"))
                continue
            }

            // Check upload status first (takes priority)
            if let isUploading = item.value(forAttribute: NSMetadataUbiquitousItemIsUploadingKey) as? Bool,
               isUploading {
                let percentUploaded = item.value(forAttribute: NSMetadataUbiquitousItemPercentUploadedKey) as? Double ?? 0
                updates.append(MetadataUpdate(projectId: projectId, status: .syncing, message: "Uploading \(Int(percentUploaded))%..."))
                continue
            }

            // Check download status
            if let downloadStatus = item.value(forAttribute: NSMetadataUbiquitousItemDownloadingStatusKey) as? String {
                if downloadStatus == NSMetadataUbiquitousItemDownloadingStatusCurrent ||
                   downloadStatus == NSMetadataUbiquitousItemDownloadingStatusDownloaded {
                    updates.append(MetadataUpdate(projectId: projectId, status: .synced, message: nil))
                } else {
                    updates.append(MetadataUpdate(projectId: projectId, status: .syncing, message: "Downloading from iCloud..."))
                }
            }
        }

        return updates
    }

    /// Apply metadata updates to actor state
    private func applyMetadataUpdates(_ updates: [MetadataUpdate]) {
        for update in updates {
            if update.status == .conflict {
                Task { @MainActor in
                    AppLogger.general.warning("SyncManager: Conflict detected for project \(update.projectId)")
                }
            }
            updateStatus(for: update.projectId, status: update.status, message: update.message)
        }
    }

    // MARK: - Status

    /// Get sync status for a project
    func getStatus(for projectId: UUID) -> SyncStatus {
        projectSyncStatus[projectId] ?? .local
    }

    private func updateStatus(for projectId: UUID, status: SyncStatus, message: String?) {
        projectSyncStatus[projectId] = status

        let event = SyncEvent(
            projectId: projectId,
            status: status,
            message: message,
            timestamp: Date()
        )

        // Publish to subscribers
        syncEventsSubject.send(event)
    }

    // MARK: - Discovery

    /// List projects available in iCloud
    func listCloudProjects() async throws -> [SyncInfo] {
        guard let iCloudURL = iCloudDocumentsURL else {
            throw SyncError.iCloudNotAvailable
        }

        var projects: [SyncInfo] = []

        let contents = try FileManager.default.contentsOfDirectory(
            at: iCloudURL,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        )

        for url in contents where url.pathExtension == "sanevideoproject" {
            let syncInfoURL = url.appendingPathComponent("sync_info.json")
            if let data = try? Data(contentsOf: syncInfoURL),
               let syncInfo = try? JSONDecoder().decode(SyncInfo.self, from: data) {
                projects.append(syncInfo)
            }
        }

        return projects.sorted { $0.lastSynced > $1.lastSynced }
    }

    /// Check if iCloud is available
    var isICloudAvailable: Bool {
        iCloudDocumentsURL != nil
    }
}

// MARK: - Supporting Types

/// Information about a synced project
struct SyncInfo: Codable, Sendable {
    let projectId: UUID
    let lastSynced: Date
    let deviceName: String
    let version: Int

    var formattedLastSynced: String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        return formatter.localizedString(for: lastSynced, relativeTo: Date())
    }
}

// MARK: - Errors

enum SyncError: LocalizedError {
    case iCloudNotAvailable
    case projectNotFound
    case syncFailed(Error)
    case conflictUnresolved
    case downloadFailed

    var errorDescription: String? {
        switch self {
        case .iCloudNotAvailable:
            return "iCloud is not available. Please sign in to iCloud in System Settings."
        case .projectNotFound:
            return "Project not found in iCloud."
        case .syncFailed(let error):
            return "Sync failed: \(error.localizedDescription)"
        case .conflictUnresolved:
            return "A sync conflict could not be resolved automatically."
        case .downloadFailed:
            return "Failed to download project from iCloud."
        }
    }
}
