import AVFoundation
import SaneUI
import SwiftUI

private enum VideoSettingsTab: String, SaneSettingsTab {
    case general, recording, export, privacy, apikeys, icloud, license, about
    #if DEBUG
        case debug
    #endif

    var title: String {
        switch self {
        case .general: String(localized: "settings.tab.general", defaultValue: "General")
        case .recording: "Recording"
        case .export: String(localized: "settings.tab.export", defaultValue: "Export")
        case .privacy: String(localized: "settings.tab.privacy", defaultValue: "Privacy & AI")
        case .apikeys: "API Keys"
        case .icloud: "iCloud Sync"
        case .license: "License"
        case .about: "About"
        #if DEBUG
            case .debug: String(localized: "settings.tab.debug", defaultValue: "Debug")
        #endif
        }
    }

    var icon: String {
        switch self {
        case .general: "gearshape"
        case .recording: "record.circle"
        case .export: "arrow.up.circle"
        case .privacy: "lock.shield"
        case .apikeys: "key.fill"
        case .icloud: "icloud"
        case .license: "checkmark.seal.fill"
        case .about: "info.circle"
        #if DEBUG
            case .debug: "ladybug"
        #endif
        }
    }

    var iconColor: Color {
        switch self {
        case .general: .orange
        case .recording: .red
        case .export: .cyan
        case .privacy: .green
        case .apikeys: .yellow
        case .icloud: .blue
        case .license: .mint
        case .about: .cyan
        #if DEBUG
            case .debug: .purple
        #endif
        }
    }
}

struct SettingsView: View {
    @Environment(LicenseService.self) private var licenseService
    @State private var selectedTab = "general"

    private var selection: Binding<VideoSettingsTab?> {
        Binding(
            get: { VideoSettingsTab(rawValue: selectedTab) ?? .general },
            set: { selectedTab = ($0 ?? .general).rawValue }
        )
    }

    var body: some View {
        SaneSettingsContainer(defaultTab: VideoSettingsTab.general, selection: selection) { tab in
            switch tab {
            case .general: GeneralSettingsView()
            case .recording: RecordingSettingsView()
            case .export: ExportSettingsView()
            case .privacy: PrivacySettingsView(selectedTab: $selectedTab)
            case .apikeys: APIKeysSettingsView()
            case .icloud: iCloudSyncSettingsView(isSelected: selectedTab == "icloud")
            case .license:
                SaneSettingsPage {
                    LicenseSettingsView(
                        licenseService: licenseService,
                        style: .panel,
                        donationURL: OpenSourceRelease.donationURL
                    )
                }
            case .about: AboutSettingsView()
            #if DEBUG
                case .debug: DebugSettingsView()
            #endif
            }
        }
        .preferredColorScheme(.dark)
    }
}

private struct AboutSettingsView: View {
    var body: some View {
        SaneAboutView(
            appName: "SaneVideo",
            githubRepo: "SaneVideo",
            diagnosticsService: SaneDiagnosticsService.shared,
            licenses: [
                SaneAboutLicenseCatalog.saneUI,
                SaneAboutLicenseCatalog.sparkle,
                SaneAboutLicenseCatalog.whisperKit
            ],
            feedbackExtraAttachments: [
                ("video.badge.waveform", "Recent recording, export, permission, and project state")
            ],
            identitySymbolName: "video.fill",
            identitySymbolColor: .cyan
        )
    }
}

// MARK: - General Settings

struct GeneralSettingsView: View {
    @Bindable var prefs = ServiceContainer.shared.userPreferences
    @State private var showingCacheAlert = false
    @State private var isClearingCache = false
    #if !APP_STORE
        @State private var automaticallyChecksForUpdates = false
        @State private var updateCheckFrequency = SaneVideoUpdateCheckFrequency.daily
    #endif

    var body: some View {
        SaneSettingsPage {
            CompactSection("Appearance", icon: "paintpalette", iconColor: .purple) {
                CompactRow("Theme") {
                    Picker("Theme", selection: $prefs.appTheme) {
                        ForEach(AppTheme.allCases) { theme in
                            Text(theme.rawValue).tag(theme)
                        }
                    }
                    .labelsHidden()
                    .help("Choose how SaneVideo looks on this Mac.")
                    .accessibilityIdentifier("settings.theme_picker")
                }
            }

            CompactSection("Preview Cache", icon: "internaldrive", iconColor: .orange) {
                VStack(alignment: .leading, spacing: 12) {
                    Text("Reset thumbnails and waveforms if previews look stale. Recordings and projects stay intact.")
                        .saneReadableSupportText()
                        .fixedSize(horizontal: false, vertical: true)
                    Button(String(localized: "settings.action.clear_cache", defaultValue: "Clear Cache")) {
                        isClearingCache = true
                        Task { @MainActor in
                            await prefs.clearCache(
                                thumbnailService: ServiceContainer.shared.thumbnailService,
                                waveformService: ServiceContainer.shared.waveformService
                            )
                            isClearingCache = false
                            showingCacheAlert = true
                        }
                    }
                    .buttonStyle(SaneActionButtonStyle())
                    .disabled(isClearingCache)
                    .help("Reset generated previews without removing media files.")
                    .accessibilityIdentifier("settings.clear_cache")
                }
                .padding(12)
            }

            #if !APP_STORE
                CompactSection("Software Updates", icon: "arrow.down.circle", iconColor: .blue) {
                    CompactToggle(
                        label: "Check automatically",
                        isOn: $automaticallyChecksForUpdates
                    )
                    .help("Let SaneVideo check for updates on this Mac.")
                    CompactDivider()
                    CompactRow("Check frequency") {
                        Picker("Check frequency", selection: $updateCheckFrequency) {
                            ForEach(SaneVideoUpdateCheckFrequency.allCases) { frequency in
                                Text(frequency.title).tag(frequency)
                            }
                        }
                        .labelsHidden()
                        .disabled(!automaticallyChecksForUpdates)
                    }
                    CompactDivider()
                    CompactRow("Available updates") {
                        Button("Check Now") {
                            ServiceContainer.shared.updaterService.checkForUpdates()
                        }
                        .buttonStyle(SaneActionButtonStyle())
                        .help("Check for an update now.")
                        .disabled(!ServiceContainer.shared.updaterService.canCheckForUpdates)
                    }
                }
            #endif
        }
        #if !APP_STORE
            .onAppear {
                automaticallyChecksForUpdates = ServiceContainer.shared.updaterService.automaticallyChecksForUpdates
                updateCheckFrequency = ServiceContainer.shared.updaterService.updateCheckFrequency
            }
            .onChange(of: automaticallyChecksForUpdates) { _, newValue in
                ServiceContainer.shared.updaterService.automaticallyChecksForUpdates = newValue
            }
            .onChange(of: updateCheckFrequency) { _, newValue in
                ServiceContainer.shared.updaterService.updateCheckFrequency = newValue
            }
        #endif
            .alert(
                String(localized: "settings.cache_cleared.title", defaultValue: "Preview Cache Cleared"),
                isPresented: $showingCacheAlert
            ) {
                Button(String(localized: "settings.action.ok", defaultValue: "OK"), role: .cancel) {}
                    .accessibilityIdentifier("settings.cache_cleared_ok")
            }
    }
}

// MARK: - Export Settings

struct ExportSettingsView: View {
    @Bindable var prefs = ServiceContainer.shared.userPreferences

    var body: some View {
        SaneSettingsPage {
            Text("Defaults for new exports. You can change them again when exporting.")
                .saneReadableSupportText()
                .fixedSize(horizontal: false, vertical: true)

            CompactSection("Video", icon: "film", iconColor: .cyan) {
                CompactRow("Resolution") {
                    Picker("Resolution", selection: $prefs.defaultResolution) {
                        Text("1080p HD").tag(SaneExportSettings.ExportResolution.hd1080)
                        Text("4K UHD").tag(SaneExportSettings.ExportResolution.uhd4K)
                    }
                    .labelsHidden()
                    .accessibilityIdentifier("settings.resolution_picker")
                    .help("Choose the default export resolution.")
                }
                HelperText(text: "1080p suits most videos. Choose 4K for extra detail.", icon: "viewfinder")
                    .padding(12)
                CompactDivider()
                CompactRow("Codec") {
                    Picker("Codec", selection: $prefs.defaultAVCodec) {
                        Text("HEVC (H.265)").tag(AVVideoCodecType.hevc)
                        Text("H.264").tag(AVVideoCodecType.h264)
                    }
                    .labelsHidden()
                    .accessibilityIdentifier("settings.codec_picker")
                    .help("Choose the default video codec.")
                }
                HelperText(text: "HEVC saves space. H.264 works with more players.", icon: "film.stack")
                    .padding(12)
            }
        }
    }
}

// MARK: - Debug Settings

struct DebugSettingsView: View {
    private var runner = ServiceContainer.shared.stressTestRunner

    var body: some View {
        SaneSettingsPage {
            CompactSection("Stress Tests", icon: "ladybug", iconColor: .purple) {
                VStack(alignment: .leading, spacing: 12) {
                    Text("Run diagnostics for recording and export performance.")
                        .saneReadableSupportText()
                        .fixedSize(horizontal: false, vertical: true)
                    Button {
                        runner.runAllTests(appState: ServiceContainer.shared.appState)
                    } label: {
                        if runner.isRunning {
                            ProgressView().controlSize(.small)
                            Text("Running…")
                        } else {
                            Label("Run Stress Tests", systemImage: "play.fill")
                        }
                    }
                    .buttonStyle(SaneActionButtonStyle())
                    .disabled(runner.isRunning)
                    .accessibilityIdentifier("settings.run_stress_tests")
                    Text(runner.statusMessage)
                        .saneReadableSupportText()
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(12)
            }
            CompactSection("Logs", icon: "text.alignleft", iconColor: .blue) {
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(runner.logs, id: \.self) { log in
                        Text(log)
                            .font(.system(size: 13, design: .monospaced))
                            .foregroundStyle(.white)
                            .fixedSize(horizontal: false, vertical: true)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
                .padding(12)
            }
        }
    }
}
