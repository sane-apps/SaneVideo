//
//  iCloudSyncSettingsView.swift
//  SaneVideo
//
//  Settings view for iCloud project sync configuration
//

import SaneUI
import SwiftUI

// swiftlint:disable:next type_name
struct iCloudSyncSettingsView: View {
    let isSelected: Bool

    private let syncFeatureEnabledInThisBuild = false

    @State private var isSyncEnabled = false
    @State private var isCloudAvailable = false
    @State private var cloudProjects: [SyncInfo] = []
    @State private var isLoading = false
    @State private var lastSyncDate: Date?
    @State private var syncError: String?
    @State private var syncManager: SyncManager?

    var body: some View {
        SaneSettingsPage {
            CompactSection("iCloud Sync", icon: "icloud", iconColor: .blue) {
                VStack(alignment: .leading, spacing: 12) {
                    Text("Project sync is not available in this version.")
                        .saneReadableBodyStrong()
                        .fixedSize(horizontal: false, vertical: true)

                    Toggle("Enable iCloud Sync", isOn: $isSyncEnabled)
                        .toggleStyle(.switch)
                        .disabled(!syncFeatureEnabledInThisBuild || !isCloudAvailable)
                        .help("iCloud project sync is unavailable in this version.")
                        .accessibilityIdentifier("settings.sync.enable_toggle")
                        .onChange(of: isSyncEnabled) { _, newValue in
                            guard syncFeatureEnabledInThisBuild else {
                                isSyncEnabled = false
                                UserDefaults.standard.set(false, forKey: "iCloudSyncEnabled")
                                return
                            }
                            Task {
                                await manager().setSyncEnabled(newValue)
                                UserDefaults.standard.set(newValue, forKey: "iCloudSyncEnabled")
                            }
                        }

                    Text("To share a finished video, choose File > Export Video and save it in the folder you want.")
                        .saneReadableSupportText()
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(12)
            }

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

        }
        .task(id: isSelected) {
            guard isSelected else { return }
            if !syncFeatureEnabledInThisBuild {
                isSyncEnabled = false
                isCloudAvailable = false
                UserDefaults.standard.set(false, forKey: "iCloudSyncEnabled")
                return
            }
            await checkCloudAvailability()
            if isSyncEnabled && isCloudAvailable {
                await loadCloudProjects()
            }
        }
    }

    // MARK: - Actions

    private func manager() -> SyncManager {
        if let syncManager {
            return syncManager
        }

        let manager = SyncManager()
        syncManager = manager
        return manager
    }

    private func checkCloudAvailability() async {
        guard syncFeatureEnabledInThisBuild else {
            isCloudAvailable = false
            return
        }

        let available = await manager().isICloudAvailable
        isCloudAvailable = available
    }

    private func loadCloudProjects() async {
        isLoading = true
        syncError = nil

        do {
            cloudProjects = try await manager().listCloudProjects()
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
    iCloudSyncSettingsView(isSelected: true)
        .frame(width: 400, height: 600)
}
