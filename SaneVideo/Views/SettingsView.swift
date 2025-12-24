//
//  SettingsView.swift
//  SaneVideo
//
//  Created by SaneVideo Refactor
//

import AVFoundation
import SwiftUI

struct SettingsView: View {
    var prefs = ServiceContainer.shared.userPreferences

    var body: some View {
        TabView {
            GeneralSettingsView()
                .tabItem {
                    Label(String(localized: "settings.tab.general", defaultValue: "General"), systemImage: "gear")
                }
                .tag("general")

            ExportSettingsView()
                .tabItem {
                    Label(String(localized: "settings.tab.export", defaultValue: "Export"), systemImage: "arrow.up.circle")
                }
                .tag("export")

            PrivacySettingsView()
                .tabItem {
                    Label(String(localized: "settings.tab.privacy", defaultValue: "Privacy & AI"), systemImage: "lock.shield")
                }
                .tag("privacy")
            
            APIKeysSettingsView()
                .tabItem {
                    Label("API Keys", systemImage: "key.fill")
                }
                .tag("apikeys")

            DebugSettingsView()
                .tabItem {
                    Label(String(localized: "settings.tab.debug", defaultValue: "Debug"), systemImage: "ladybug")
                }
                .tag("debug")
        }
        .frame(width: 500, height: 400)
        .padding()
    }
}

// MARK: - General Settings

struct GeneralSettingsView: View {
    @Bindable var prefs = ServiceContainer.shared.userPreferences
    @State private var showingCacheAlert = false

    var body: some View {
        Form {
            Section(header: Text(String(localized: "settings.appearance.header", defaultValue: "Appearance")).font(.headline)) {
                Picker(String(localized: "settings.appearance.theme", defaultValue: "Theme"), selection: $prefs.appTheme) {
                    ForEach(AppTheme.allCases) { theme in
                        Text(theme.rawValue).tag(theme)
                    }
                }
                .pickerStyle(.radioGroup)
                .accessibilityIdentifier("settings.theme_picker")
            }
            .padding(.bottom, 20)

            Section(header: Text(String(localized: "settings.transcription.header", defaultValue: "Transcription Engine")).font(.headline)) {
                TranscriptionEnginePicker()
            }
            .padding(.bottom, 20)
            
            Section(header: Text(String(localized: "settings.storage.header", defaultValue: "Storage & Performance")).font(.headline)) {
                HStack {
                    VStack(alignment: .leading) {
                        Text(String(localized: "settings.storage.temp_files", defaultValue: "Temporary Files"))
                            .font(.body)
                        Text(String(localized: "settings.storage.description", defaultValue: "Clear cached previews and temporary recordings to free up space."))
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    Spacer()
                    Button(String(localized: "settings.action.clear_cache", defaultValue: "Clear Cache")) {
                        prefs.clearCache()
                        showingCacheAlert = true
                    }
                    .accessibilityIdentifier("settings.clear_cache")
                }
            }
            .padding(.bottom, 20)
            
            // MARK: - Privacy Section
            Section(header: Text("Privacy & AI").font(.headline)) {
                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        CompactPrivacyBadge()
                        Spacer()
                    }
                    
                    Text("SaneVideo processes all AI features on-device using Apple Intelligence. Your videos never leave your Mac.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    
                    HStack {
                        Text("Cloud AI:")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        Spacer()
                        Text("Optional (your API keys)")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    
                    Button("Configure API Keys") {
                        // Open API keys settings
                        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy") {
                            NSWorkspace.shared.open(url)
                        }
                    }
                    .font(.caption)
                    .buttonStyle(.link)
                }
            }
        }
        .padding()
        .alert(String(localized: "settings.cache_cleared.title", defaultValue: "Cache Cleared"), isPresented: $showingCacheAlert) {
            Button(String(localized: "settings.action.ok", defaultValue: "OK"), role: .cancel) {}
                .accessibilityIdentifier("settings.cache_cleared_ok")
        }
    }
}

// MARK: - Export Settings

struct ExportSettingsView: View {
    @Bindable var prefs = ServiceContainer.shared.userPreferences

    var body: some View {
        Form {
            Section(header: Text(String(localized: "settings.export.header", defaultValue: "Default Export Configuration")).font(.headline)) {
                Text(String(localized: "settings.export.description", defaultValue: "These settings will be used as the default for new exports."))
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .padding(.bottom, 8)

                Picker(String(localized: "settings.export.resolution", defaultValue: "Resolution"), selection: $prefs.defaultResolution) {
                    Text(String(localized: "settings.export.resolution.1080p", defaultValue: "1080p HD")).tag(SaneExportSettings.ExportResolution.hd1080)
                    Text(String(localized: "settings.export.resolution.4k", defaultValue: "4K UHD")).tag(SaneExportSettings.ExportResolution.uhd4K)
                }
                .accessibilityIdentifier("settings.resolution_picker")

                Picker(String(localized: "settings.export.codec", defaultValue: "Codec"), selection: $prefs.defaultAVCodec) {
                    Text(String(localized: "settings.export.codec.hevc", defaultValue: "HEVC (H.265)")).tag(AVVideoCodecType.hevc)
                    Text(String(localized: "settings.export.codec.h264", defaultValue: "H.264")).tag(AVVideoCodecType.h264)
                }
                .accessibilityIdentifier("settings.codec_picker")
            }
        }
        .padding()
    }
}

// MARK: - Debug Settings

struct DebugSettingsView: View {
    private var runner = ServiceContainer.shared.stressTestRunner

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(String(localized: "settings.debug.header", defaultValue: "Stress Testing & Limits"))
                .font(.headline)

            Text(String(localized: "settings.debug.description", defaultValue: "Run automated stress tests to identify performance bottlenecks and breaking points."))
                .font(.caption)
                .foregroundColor(.secondary)

            HStack {
                Button(action: {
                    runner.runAllTests(appState: ServiceContainer.shared.appState)
                }, label: {
                    if runner.isRunning {
                        ProgressView().controlSize(.small)
                        Text(String(localized: "settings.debug.running", defaultValue: "Running..."))
                    } else {
                        Image(systemName: "play.fill")
                        Text(String(localized: "settings.debug.run_tests", defaultValue: "Run Stress Tests"))
                    }
                })
                .disabled(runner.isRunning)
                .accessibilityIdentifier("settings.run_stress_tests")

                Spacer()

                Text(runner.statusMessage)
                    .font(.caption)
                    .foregroundColor(.gray)
            }

            Divider()

            Text(String(localized: "settings.debug.logs", defaultValue: "Logs:"))
                .font(.subheadline)

            ScrollView {
                VStack(alignment: .leading) {
                    ForEach(runner.logs, id: \.self) { log in
                        Text(log)
                            .font(.system(.caption, design: .monospaced))
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
                .padding(8)
            }
            .background(Color(NSColor.textBackgroundColor))
            .cornerRadius(4)
            .border(Color.gray.opacity(0.3), width: 1)
        }
        .padding()
    }
}
