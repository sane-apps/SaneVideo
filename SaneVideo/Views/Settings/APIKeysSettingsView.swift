import SaneUI
import SwiftUI

struct APIKeysSettingsView: View {
    private var keyManager = ServiceContainer.shared.apiKeyManager
    @State private var youtubeClientID = ""
    @State private var youtubeClientSecret = ""
    @State private var showYouTubeSecret = false
    @State private var showingClearAlert = false
    @State private var saveError: String?
    @State private var showingSaveSuccess = false

    var body: some View {
        SaneSettingsPage {
            CompactSection("YouTube Upload", icon: "play.rectangle", iconColor: .red) {
                VStack(alignment: .leading, spacing: 12) {
                    if YouTubeService.uploadFeatureEnabled {
                        Text("Add your Google OAuth credentials to upload directly to YouTube.")
                            .saneReadableSupportText()
                            .fixedSize(horizontal: false, vertical: true)
                        credentialFields
                        Button(String(localized: "settings.youtube.action.save", defaultValue: "Save YouTube Credentials")) {
                            saveYouTubeCredentials()
                        }
                        .buttonStyle(SaneActionButtonStyle())
                        .disabled(youtubeClientID.isEmpty || youtubeClientSecret.isEmpty)
                        .accessibilityIdentifier("settings.youtube.save")
                        .help("Save YouTube credentials in your Mac Keychain.")

                        if keyManager.hasYouTubeCredentials {
                            Button(String(localized: "settings.youtube.action.clear", defaultValue: "Clear"), role: .destructive) {
                                clearYouTubeCredentials()
                            }
                            .buttonStyle(SaneActionButtonStyle(destructive: true))
                            .accessibilityIdentifier("settings.youtube.clear")
                            .help("Remove saved YouTube credentials.")
                        }
                    } else {
                        Text("Direct upload is not available in this version.")
                            .saneReadableBodyStrong()
                            .fixedSize(horizontal: false, vertical: true)
                        Text("Choose File > Export Video, then upload the saved file to YouTube.")
                            .saneReadableSupportText()
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(12)
            }

            CompactSection("Saved Credentials", icon: "key", iconColor: .yellow) {
                VStack(alignment: .leading, spacing: 12) {
                    Text("Previously saved keys stay in your Mac Keychain until you remove them. No keys are needed for local recording or export.")
                        .saneReadableSupportText()
                        .fixedSize(horizontal: false, vertical: true)
                    Button(String(localized: "settings.action.clear_all", defaultValue: "Clear All API Keys"), role: .destructive) {
                        showingClearAlert = true
                    }
                    .buttonStyle(SaneActionButtonStyle(destructive: true))
                    .help("Remove stored API credentials after confirmation.")
                    .accessibilityIdentifier("settings.keys.clear_all")
                }
                .padding(12)
            }

            if showingSaveSuccess {
                Label(String(localized: "settings.save_success", defaultValue: "Saved successfully"), systemImage: "checkmark.circle.fill")
                    .saneReadableBodyStrong()
            }
        }
        .alert(String(localized: "settings.clear_all.title", defaultValue: "Clear All API Keys?"), isPresented: $showingClearAlert) {
            Button(String(localized: "settings.action.cancel", defaultValue: "Cancel"), role: .cancel) {}
            Button(String(localized: "settings.action.clear_all_confirm", defaultValue: "Clear All"), role: .destructive) {
                clearAllKeys()
            }
            .accessibilityIdentifier("settings.keys.clear_all_confirm")
        } message: {
            Text("This removes saved API credentials from your Mac Keychain. Your projects and media stay intact.")
        }
        .alert(String(localized: "settings.error.title", defaultValue: "Error"), isPresented: .init(
            get: { saveError != nil },
            set: { if !$0 { saveError = nil } }
        )) {
            Button(String(localized: "settings.action.ok", defaultValue: "OK")) { saveError = nil }
                .accessibilityIdentifier("settings.save_error.ok")
        } message: {
            if let saveError { Text(saveError) }
        }
        .task {
            guard YouTubeService.uploadFeatureEnabled else { return }
            await keyManager.refreshStatus()
        }
    }

    private var credentialFields: some View {
        VStack(alignment: .leading, spacing: 12) {
            TextField(String(localized: "settings.youtube.client_id_placeholder", defaultValue: "Enter Client ID"), text: $youtubeClientID)
                .textFieldStyle(.roundedBorder)
                .accessibilityLabel("Client ID")
                .accessibilityIdentifier("settings.youtube.client_id")
                .help("Paste the OAuth client ID from Google Cloud Console.")
            HStack {
                Group {
                    if showYouTubeSecret {
                        TextField(String(localized: "settings.youtube.client_secret_placeholder", defaultValue: "Enter Client Secret"), text: $youtubeClientSecret)
                    } else {
                        SecureField(String(localized: "settings.youtube.client_secret_placeholder", defaultValue: "Enter Client Secret"), text: $youtubeClientSecret)
                    }
                }
                .textFieldStyle(.roundedBorder)
                .accessibilityLabel("Client Secret")
                .accessibilityIdentifier("settings.youtube.client_secret")
                Button { showYouTubeSecret.toggle() } label: {
                    Image(systemName: showYouTubeSecret ? "eye.slash" : "eye")
                }
                .buttonStyle(SaneActionButtonStyle())
                .help(showYouTubeSecret ? "Hide the client secret." : "Show the client secret.")
                .accessibilityIdentifier("settings.youtube.toggle_secret")
            }
        }
    }

    private func saveYouTubeCredentials() {
        Task {
            do {
                try await keyManager.saveYouTubeCredentials(clientID: youtubeClientID, clientSecret: youtubeClientSecret)
                youtubeClientID = ""
                youtubeClientSecret = ""
                showingSaveSuccess = true
            } catch {
                saveError = error.localizedDescription
            }
        }
    }

    private func clearYouTubeCredentials() {
        Task {
            do {
                try await keyManager.clearYouTubeCredentials()
                showingSaveSuccess = false
            } catch {
                saveError = error.localizedDescription
            }
        }
    }

    private func clearAllKeys() {
        Task {
            do {
                try await keyManager.clearAllKeys()
                showingSaveSuccess = false
            } catch {
                saveError = error.localizedDescription
            }
        }
    }
}

#Preview {
    APIKeysSettingsView()
        .frame(width: 540, height: 600)
}
