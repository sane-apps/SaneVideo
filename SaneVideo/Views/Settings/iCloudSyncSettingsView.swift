//
//  iCloudSyncSettingsView.swift
//  SaneVideo
//
//  Settings view for iCloud project sync configuration
//

import SwiftUI

// swiftlint:disable:next type_name
struct iCloudSyncSettingsView: View {
    @State private var isSyncEnabled: Bool = UserDefaults.standard.bool(forKey: "iCloudSyncEnabled")
    @State private var isCloudAvailable = false
    @State private var cloudProjects: [SyncInfo] = []
    @State private var isLoading = false
    @State private var lastSyncDate: Date?
    @State private var syncError: String?

    private let syncManager = SyncManager()

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            InformationBox(
                text: "iCloud sync is optional. It keeps projects in your own iCloud Drive across Macs without adding SaneApps hosting costs. Recording and export still work offline when this is off.",
                color: Theme.Colors.accent,
                icon: "icloud.fill"
            )

            // Header
            HStack {
                Image(systemName: "icloud.fill")
                    .font(.title)
                    .foregroundStyle(Theme.Colors.accent)
                VStack(alignment: .leading, spacing: 2) {
                    Text("iCloud Sync")
                        .saneReadableSectionTitle()
                    Text("Sync projects across your Mac devices")
                        .saneReadableSupportText()
                }
                Spacer()
            }

            Divider()

            // Availability Status
            HStack {
                Circle()
                    .fill(isCloudAvailable ? Color.green : Color.red)
                    .frame(width: 8, height: 8)
                Text(isCloudAvailable ? "iCloud Available" : "iCloud Unavailable")
                    .saneReadableMeta()

                Spacer()

                if let lastSync = lastSyncDate {
                    Text("Last sync: \(lastSync, style: .relative)")
                        .saneReadableMeta()
                }
            }

            // Main Toggle
            Toggle(isOn: $isSyncEnabled) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Enable iCloud Sync")
                        .saneReadableBodyStrong()
                    Text("Projects will sync automatically when saved")
                        .saneReadableSupportText()
                }
            }
            .help("Turn this on to keep project packages in your own iCloud Drive across Macs.")
            .disabled(!isCloudAvailable)
            .accessibilityIdentifier("settings.sync.enable_toggle")
            .onChange(of: isSyncEnabled) { _, newValue in
                Task {
                    await syncManager.setSyncEnabled(newValue)
                    UserDefaults.standard.set(newValue, forKey: "iCloudSyncEnabled")
                }
            }

            HelperText(
                text: "Use this if you move between Macs. Leave it off if you want a strictly local-only setup on one machine.",
                icon: "arrow.triangle.2.circlepath.icloud"
            )

            if isSyncEnabled && isCloudAvailable {
                Divider()

                // Cloud Projects Section
                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        Text("Projects in iCloud")
                            .saneReadableLabel()
                        Spacer()
                        Button {
                            Task { await loadCloudProjects() }
                        } label: {
                            Image(systemName: "arrow.clockwise")
                        }
                        .buttonStyle(.borderless)
                        .help("Refresh the list of projects currently visible in iCloud.")
                        .disabled(isLoading)
                    }

                    HelperText(
                        text: "This list shows the copies already synced to your iCloud Drive.",
                        icon: "folder.badge.gearshape"
                    )

                    if isLoading {
                        HStack {
                            ProgressView()
                                .controlSize(.small)
                            Text("Loading...")
                                .saneReadableSupportText()
                        }
                    } else if cloudProjects.isEmpty {
                        HStack {
                            Image(systemName: "cloud")
                                .foregroundStyle(Theme.Colors.textSecondary)
                            Text("No projects synced yet")
                                .saneReadableSupportText()
                        }
                        .padding(.vertical, 8)
                    } else {
                        ScrollView {
                            LazyVStack(spacing: 8) {
                                ForEach(cloudProjects, id: \.projectId) { syncInfo in
                                    CloudProjectRow(syncInfo: syncInfo)
                                }
                            }
                        }
                        .frame(maxHeight: 200)
                    }
                }

                Divider()

                // Sync Options
                VStack(alignment: .leading, spacing: 12) {
                    Text("Sync Options")
                        .saneReadableLabel()

                    Toggle("Sync media files", isOn: .constant(true))
                        .disabled(true)
                        .help("Media files are included so your projects open correctly on your other Mac.")
                        .accessibilityIdentifier("settings.sync.media")

                    Toggle("Sync captions", isOn: .constant(true))
                        .disabled(true)
                        .help("Captions and transcript assets stay with the project package.")
                        .accessibilityIdentifier("settings.sync.captions")

                    Text("Media files are stored in iCloud Drive and may count against your storage quota.")
                        .saneReadableSupportText()
                }

                // Manual Sync Button
                HStack {
                    Button {
                        performManualSync()
                    } label: {
                        Label("Sync Now", systemImage: "arrow.triangle.2.circlepath")
                    }
                    .help("Refresh project sync status now instead of waiting for the next save.")
                    .disabled(isLoading)
                    .accessibilityIdentifier("settings.sync.sync_now")

                    Spacer()

                    if let error = syncError {
                        Text(error)
                            .saneReadableSupportText()
                            .foregroundStyle(.red)
                    }
                }
            }

            // Help Text
            GroupBox {
                VStack(alignment: .leading, spacing: 8) {
                    Label("About iCloud Sync", systemImage: "info.circle")
                        .saneReadableLabel()

                    Text("""
                    iCloud Sync keeps your SaneVideo projects synchronized across all your Mac computers. \
                    Projects are automatically synced when you save changes.

                    Note: Sync is currently available for Mac-to-Mac only. iPad and iPhone support is coming in a future update.
                    """)
                    .saneReadableSupportText()
                }
            }
            .sanePanel(radius: 12, accent: Theme.Colors.accentSoft)

            Spacer()
        }
        .padding()
        .task {
            await checkCloudAvailability()
            if isSyncEnabled && isCloudAvailable {
                await loadCloudProjects()
            }
        }
    }

    // MARK: - Actions

    private func checkCloudAvailability() async {
        isCloudAvailable = await syncManager.isICloudAvailable
    }

    private func loadCloudProjects() async {
        isLoading = true
        syncError = nil

        do {
            cloudProjects = try await syncManager.listCloudProjects()
        } catch {
            syncError = error.localizedDescription
        }

        isLoading = false
    }

    private func performManualSync() {
        isLoading = true
        syncError = nil

        Task {
            // In production, this would sync all current projects
            do {
                await loadCloudProjects()
                lastSyncDate = Date()
            }
            isLoading = false
        }
    }
}

// MARK: - Cloud Project Row

private struct CloudProjectRow: View {
    let syncInfo: SyncInfo

    var body: some View {
        HStack {
            Image(systemName: "folder.fill")
                .foregroundStyle(Theme.Colors.accent)

            VStack(alignment: .leading, spacing: 2) {
                Text("Project \(syncInfo.projectId.uuidString.prefix(8))...")
                    .saneReadableBodyStrong()
                    .lineLimit(1)

                HStack(spacing: 8) {
                    Text(syncInfo.formattedLastSynced)
                    Text("•")
                    Text(syncInfo.deviceName)
                }
                .saneReadableSupportText()
            }

            Spacer()

            Image(systemName: "checkmark.icloud.fill")
                .foregroundStyle(.green)
                .font(.caption)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .sanePanel(radius: 10, accent: Theme.Colors.accentSoft)
    }
}

#Preview {
    iCloudSyncSettingsView()
        .frame(width: 400, height: 600)
}
