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
            // Header
            HStack {
                Image(systemName: "icloud.fill")
                    .font(.title)
                    .foregroundStyle(.blue)
                VStack(alignment: .leading, spacing: 2) {
                    Text("iCloud Sync")
                        .font(.headline)
                    Text("Sync projects across your Mac devices")
                        .font(.caption)
                        .foregroundStyle(Color.stone)
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
                    .font(.caption)
                    .foregroundStyle(Color.stone)

                Spacer()

                if let lastSync = lastSyncDate {
                    Text("Last sync: \(lastSync, style: .relative)")
                        .font(.caption)
                        .foregroundStyle(Color.stone)
                }
            }

            // Main Toggle
            Toggle(isOn: $isSyncEnabled) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Enable iCloud Sync")
                        .font(.body)
                    Text("Projects will sync automatically when saved")
                        .font(.caption)
                        .foregroundStyle(Color.stone)
                }
            }
            .disabled(!isCloudAvailable)
            .accessibilityIdentifier("settings.sync.enable_toggle")
            .onChange(of: isSyncEnabled) { _, newValue in
                Task {
                    await syncManager.setSyncEnabled(newValue)
                    UserDefaults.standard.set(newValue, forKey: "iCloudSyncEnabled")
                }
            }

            if isSyncEnabled && isCloudAvailable {
                Divider()

                // Cloud Projects Section
                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        Text("Projects in iCloud")
                            .font(.subheadline.weight(.medium))
                        Spacer()
                        Button {
                            Task { await loadCloudProjects() }
                        } label: {
                            Image(systemName: "arrow.clockwise")
                        }
                        .buttonStyle(.borderless)
                        .disabled(isLoading)
                    }

                    if isLoading {
                        HStack {
                            ProgressView()
                                .controlSize(.small)
                            Text("Loading...")
                                .font(.caption)
                                .foregroundStyle(Color.stone)
                        }
                    } else if cloudProjects.isEmpty {
                        HStack {
                            Image(systemName: "cloud")
                                .foregroundStyle(Color.stone)
                            Text("No projects synced yet")
                                .font(.caption)
                                .foregroundStyle(Color.stone)
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
                        .font(.subheadline.weight(.medium))

                    Toggle("Sync media files", isOn: .constant(true))
                        .disabled(true)
                        .accessibilityIdentifier("settings.sync.media")

                    Toggle("Sync captions", isOn: .constant(true))
                        .disabled(true)
                        .accessibilityIdentifier("settings.sync.captions")

                    Text("Media files are stored in iCloud Drive and may count against your storage quota.")
                        .font(.caption2)
                        .foregroundStyle(Color.stone)
                }

                // Manual Sync Button
                HStack {
                    Button {
                        performManualSync()
                    } label: {
                        Label("Sync Now", systemImage: "arrow.triangle.2.circlepath")
                    }
                    .disabled(isLoading)
                    .accessibilityIdentifier("settings.sync.sync_now")

                    Spacer()

                    if let error = syncError {
                        Text(error)
                            .font(.caption)
                            .foregroundStyle(.red)
                    }
                }
            }

            // Help Text
            GroupBox {
                VStack(alignment: .leading, spacing: 8) {
                    Label("About iCloud Sync", systemImage: "info.circle")
                        .font(.caption.weight(.medium))

                    Text("""
                    iCloud Sync keeps your SaneVideo projects synchronized across all your Mac computers. \
                    Projects are automatically synced when you save changes.

                    Note: Sync is currently available for Mac-to-Mac only. iPad and iPhone support is coming in a future update.
                    """)
                    .font(.caption2)
                    .foregroundStyle(Color.stone)
                }
            }

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
                .foregroundStyle(.blue)

            VStack(alignment: .leading, spacing: 2) {
                Text("Project \(syncInfo.projectId.uuidString.prefix(8))...")
                    .font(.caption)
                    .lineLimit(1)

                HStack(spacing: 8) {
                    Text(syncInfo.formattedLastSynced)
                    Text("•")
                    Text(syncInfo.deviceName)
                }
                .font(.caption2)
                .foregroundStyle(Color.stone)
            }

            Spacer()

            Image(systemName: "checkmark.icloud.fill")
                .foregroundStyle(.green)
                .font(.caption)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .background(Color.stone.opacity(0.05))
        .cornerRadius(6)
    }
}

#Preview {
    iCloudSyncSettingsView()
        .frame(width: 400, height: 600)
}
