//
//  SettingsView.swift
//  SaneVideo
//
//  Created by SaneVideo Refactor
//

import AVFoundation
import SwiftUI
#if !APP_STORE
  import SaneUI
#endif

struct SettingsView: View {
  var prefs = ServiceContainer.shared.userPreferences
  @State private var selectedTab = "general"

  var body: some View {
    TabView(selection: $selectedTab) {
      GeneralSettingsView(selectedTab: $selectedTab)
        .tabItem {
          Label(
            String(localized: "settings.tab.general", defaultValue: "General"), systemImage: "gear")
        }
        .tag("general")

      ExportSettingsView()
        .tabItem {
          Label(
            String(localized: "settings.tab.export", defaultValue: "Export"),
            systemImage: "arrow.up.circle")
        }
        .tag("export")

      RecordingSettingsView()
        .tabItem {
          Label("Recording", systemImage: "record.circle")
        }
        .tag("recording")

      PrivacySettingsView()
        .tabItem {
          Label(
            String(localized: "settings.tab.privacy", defaultValue: "Privacy & AI"),
            systemImage: "lock.shield")
        }
        .tag("privacy")

      APIKeysSettingsView()
        .tabItem {
          Label("API Keys", systemImage: "key.fill")
        }
        .tag("apikeys")

      iCloudSyncSettingsView()
        .tabItem {
          Label("iCloud Sync", systemImage: "icloud")
        }
        .tag("icloud")

      DebugSettingsView()
        .tabItem {
          Label(
            String(localized: "settings.tab.debug", defaultValue: "Debug"), systemImage: "ladybug")
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
  @Binding var selectedTab: String
  @State private var showingCacheAlert = false
  #if !APP_STORE
    @State private var automaticallyChecksForUpdates = false
    @State private var updateCheckFrequency = SaneSparkleCheckFrequency.daily
  #endif

  var body: some View {
    Form {
      Section {
        InformationBox(
          text: "These settings change the defaults for this Mac. Your current projects keep their own project-specific recording, export, and Demo Studio settings.",
          color: Theme.Colors.accent,
          icon: "gearshape.fill"
        )
      }

      Section(
        header: Text(String(localized: "settings.appearance.header", defaultValue: "Appearance"))
          .saneReadableSectionTitle()
      ) {
        Picker(
          String(localized: "settings.appearance.theme", defaultValue: "Theme"),
          selection: $prefs.appTheme
        ) {
          ForEach(AppTheme.allCases) { theme in
            Text(theme.rawValue).tag(theme)
          }
        }
        .pickerStyle(.radioGroup)
        .help("Choose how SaneVideo looks on this Mac.")
        .accessibilityIdentifier("settings.theme_picker")

        HelperText(
          text: "Theme changes the app chrome only. It does not affect exported video colors.",
          icon: "paintpalette.fill"
        )
      }
      .padding(.bottom, 20)

      Section(
        header: Text(
          String(localized: "settings.transcription.header", defaultValue: "Transcription Engine")
        ).saneReadableSectionTitle()
      ) {
        TranscriptionEnginePicker()
        HelperText(
          text: "Pick the speech-to-text engine you want to use for captions and transcripts.",
          icon: "captions.bubble.fill"
        )
      }
      .padding(.bottom, 20)

      Section(
        header: Text(
          String(localized: "settings.storage.header", defaultValue: "Storage & Performance")
        ).saneReadableSectionTitle()
      ) {
        HStack {
          VStack(alignment: .leading) {
            Text(String(localized: "settings.storage.temp_files", defaultValue: "Temporary Files"))
              .saneReadableBodyStrong()
            Text(
              String(
                localized: "settings.storage.description",
                defaultValue: "Clear cached previews and temporary recordings to free up space.")
            )
            .saneReadableSupportText()
          }
          Spacer()
          Button(String(localized: "settings.action.clear_cache", defaultValue: "Clear Cache")) {
            prefs.clearCache()
            showingCacheAlert = true
          }
          .help("Remove cached previews and temporary files from this Mac.")
          .accessibilityIdentifier("settings.clear_cache")
        }

        HelperText(
          text: "Use this if the app is taking more disk space than expected or previews look stale.",
          icon: "internaldrive.fill"
        )
      }
      .padding(.bottom, 20)

      // MARK: - Privacy Section
      Section(header: Text("Privacy & AI").saneReadableSectionTitle()) {
        VStack(alignment: .leading, spacing: 12) {
          HStack {
            CompactPrivacyBadge()
            Spacer()
          }

          Text(
            "SaneVideo processes all AI features on-device using Apple Intelligence. Your videos never leave your Mac."
          )
          .saneReadableSupportText()

          HStack {
            Text("Cloud AI:")
              .saneReadableLabel()
            Spacer()
            Text("Optional (your API keys)")
              .saneReadableMeta()
          }

          Button("Configure API Keys") {
            selectedTab = "apikeys"
          }
          .buttonStyle(.link)
          .help("Open the optional API Keys tab inside SaneVideo.")

          HelperText(
            text: "You only need API keys for optional direct upload or cloud-powered extras. The normal local demo workflow does not depend on them.",
            icon: "lock.shield.fill"
          )
        }
      }

      #if !APP_STORE
        Section(header: Text("Software Updates").saneReadableSectionTitle()) {
          Toggle("Check for updates automatically", isOn: $automaticallyChecksForUpdates)
            .help("Let SaneVideo check for updates on this Mac.")

          Picker("Check frequency", selection: $updateCheckFrequency) {
            ForEach(SaneSparkleCheckFrequency.allCases) { frequency in
              Text(frequency.title).tag(frequency)
            }
          }
          .pickerStyle(.segmented)
          .help("Choose how often automatic update checks run.")
          .disabled(!automaticallyChecksForUpdates)

          Button("Check Now") {
            ServiceContainer.shared.updaterService.checkForUpdates()
          }
          .help("Check for an update right now.")
          .disabled(!ServiceContainer.shared.updaterService.canCheckForUpdates)

          HelperText(
            text: "Automatic updates do not upload your projects. This only checks whether a newer app build exists.",
            icon: "arrow.down.circle.fill"
          )
        }
      #endif
    }
    .padding()
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
      String(localized: "settings.cache_cleared.title", defaultValue: "Cache Cleared"),
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
    Form {
      Section {
        InformationBox(
          text: "These export defaults are the starting point for new exports. You can still override them per project or per export later.",
          color: Theme.Colors.accent,
          icon: "arrow.up.circle.fill"
        )
      }

      Section(
        header: Text(
          String(localized: "settings.export.header", defaultValue: "Default Export Configuration")
        ).saneReadableSectionTitle()
      ) {
        Text(
          String(
            localized: "settings.export.description",
            defaultValue: "These settings will be used as the default for new exports.")
        )
        .saneReadableSupportText()
        .padding(.bottom, 8)

        Picker(
          String(localized: "settings.export.resolution", defaultValue: "Resolution"),
          selection: $prefs.defaultResolution
        ) {
          Text(String(localized: "settings.export.resolution.1080p", defaultValue: "1080p HD")).tag(
            SaneExportSettings.ExportResolution.hd1080)
          Text(String(localized: "settings.export.resolution.4k", defaultValue: "4K UHD")).tag(
            SaneExportSettings.ExportResolution.uhd4K)
        }
        .help("Choose the default export resolution for new export jobs.")
        .accessibilityIdentifier("settings.resolution_picker")

        HelperText(
          text: "Use 1080p for the normal product-demo master. Use 4K when you want maximum detail or more room for crop/reframe work.",
          icon: "rectangle.compress.vertical"
        )

        Picker(
          String(localized: "settings.export.codec", defaultValue: "Codec"),
          selection: $prefs.defaultAVCodec
        ) {
          Text(String(localized: "settings.export.codec.hevc", defaultValue: "HEVC (H.265)")).tag(
            AVVideoCodecType.hevc)
          Text(String(localized: "settings.export.codec.h264", defaultValue: "H.264")).tag(
            AVVideoCodecType.h264)
        }
        .help("Choose the default video codec for new export jobs.")
        .accessibilityIdentifier("settings.codec_picker")

        HelperText(
          text: "HEVC makes smaller files at the same quality. H.264 is the safer compatibility default when you need broad support.",
          icon: "film.stack.fill"
        )
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
        .saneReadableSectionTitle()

      Text(
        String(
          localized: "settings.debug.description",
          defaultValue:
            "Run automated stress tests to identify performance bottlenecks and breaking points.")
      )
      .saneReadableSupportText()

      HelperText(
        text: "This is for validation and diagnostics. Normal recording and editing do not require it.",
        icon: "ladybug.fill"
      )

      HStack {
        Button(
          action: {
            runner.runAllTests(appState: ServiceContainer.shared.appState)
          },
          label: {
            if runner.isRunning {
              ProgressView().controlSize(.small)
              Text(String(localized: "settings.debug.running", defaultValue: "Running..."))
            } else {
              Image(systemName: "play.fill")
              Text(String(localized: "settings.debug.run_tests", defaultValue: "Run Stress Tests"))
            }
          }
        )
        .help("Run the built-in stress test suite for diagnostics.")
        .disabled(runner.isRunning)
        .accessibilityIdentifier("settings.run_stress_tests")

        Spacer()

        Text(runner.statusMessage)
          .saneReadableSupportText()
      }

      Divider()

      Text(String(localized: "settings.debug.logs", defaultValue: "Logs:"))
        .saneReadableLabel()

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
      .sanePanel(radius: 10, accent: Theme.Colors.accentDeep)
    }
    .padding()
  }
}
