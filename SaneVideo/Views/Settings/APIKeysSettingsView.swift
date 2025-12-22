//
//  APIKeysSettingsView.swift
//  SaneVideo
//
//  Settings UI for configuring API keys securely
//

import SwiftUI

struct APIKeysSettingsView: View {
    private var keyManager = ServiceContainer.shared.apiKeyManager

    // YouTube credentials
    @State private var youtubeClientID = ""
    @State private var youtubeClientSecret = ""
    @State private var showYouTubeSecret = false

    // OpenAI
    @State private var openAIKey = ""
    @State private var showOpenAIKey = false

    // Gemini
    @State private var geminiKey = ""
    @State private var showGeminiKey = false

    // UI State
    @State private var showingClearAlert = false
    @State private var saveError: String?
    @State private var showingSaveSuccess = false

    var body: some View {
        Form {
            // YouTube Section
            Section {
                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        Image(systemName: "play.rectangle.fill")
                            .foregroundColor(.red)
                        Text(String(localized: "settings.youtube.header", defaultValue: "YouTube Upload"))
                            .font(.headline)
                        Spacer()
                        statusBadge(configured: keyManager.hasYouTubeCredentials)
                    }

                    Text(String(localized: "settings.youtube.description", defaultValue: "Required for uploading videos directly to YouTube. Get credentials from [Google Cloud Console](https://console.cloud.google.com/apis/credentials)."))
                        .font(.caption)
                        .foregroundColor(.secondary)

                    VStack(spacing: 8) {
                        HStack {
                            Text(String(localized: "settings.youtube.client_id_label", defaultValue: "Client ID"))
                                .frame(width: 100, alignment: .leading)
                            TextField(String(localized: "settings.youtube.client_id_placeholder", defaultValue: "Enter Client ID"), text: $youtubeClientID)
                                .textFieldStyle(.roundedBorder)
                                .accessibilityIdentifier("settings.youtube.client_id")
                        }

                        HStack {
                            Text(String(localized: "settings.youtube.client_secret_label", defaultValue: "Client Secret"))
                                .frame(width: 100, alignment: .leading)
                            Group {
                                if showYouTubeSecret {
                                    TextField(String(localized: "settings.youtube.client_secret_placeholder", defaultValue: "Enter Client Secret"), text: $youtubeClientSecret)
                                } else {
                                    SecureField(String(localized: "settings.youtube.client_secret_placeholder", defaultValue: "Enter Client Secret"), text: $youtubeClientSecret)
                                }
                            }
                            .textFieldStyle(.roundedBorder)
                            .accessibilityIdentifier("settings.youtube.client_secret")

                            Button(action: { showYouTubeSecret.toggle() }, label: {
                                Image(systemName: showYouTubeSecret ? "eye.slash" : "eye")
                            })
                            .buttonStyle(.borderless)
                            .accessibilityIdentifier("settings.youtube.toggle_secret")
                        }
                    }

                    HStack {
                        Button(String(localized: "settings.youtube.action.save", defaultValue: "Save YouTube Credentials")) {
                            saveYouTubeCredentials()
                        }
                        .disabled(youtubeClientID.isEmpty || youtubeClientSecret.isEmpty)
                        .accessibilityIdentifier("settings.youtube.save")

                        if keyManager.hasYouTubeCredentials {
                            Button(String(localized: "settings.youtube.action.clear", defaultValue: "Clear"), role: .destructive) {
                                clearYouTubeCredentials()
                            }
                            .buttonStyle(.borderless)
                            .accessibilityIdentifier("settings.youtube.clear")
                        }
                    }
                }
                .padding(.vertical, 4)
            }

            // OpenAI Section
            Section {
                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        Image(systemName: "brain")
                            .foregroundColor(.green)
                        Text(String(localized: "settings.openai.header", defaultValue: "OpenAI"))
                            .font(.headline)
                        Spacer()
                        statusBadge(configured: keyManager.hasOpenAIKey)
                    }

                    Text(String(localized: "settings.openai.description", defaultValue: "Used for AI-powered video title and description suggestions. Get your key from [OpenAI Platform](https://platform.openai.com/api-keys)."))
                        .font(.caption)
                        .foregroundColor(.secondary)

                    HStack {
                        Text(String(localized: "settings.openai.key_label", defaultValue: "API Key"))
                            .frame(width: 100, alignment: .leading)
                        Group {
                            if showOpenAIKey {
                                TextField("sk-...", text: $openAIKey)
                            } else {
                                SecureField("sk-...", text: $openAIKey)
                            }
                        }
                        .textFieldStyle(.roundedBorder)
                        .accessibilityIdentifier("settings.openai.key")

                        Button(action: { showOpenAIKey.toggle() }, label: {
                            Image(systemName: showOpenAIKey ? "eye.slash" : "eye")
                        })
                        .buttonStyle(.borderless)
                        .accessibilityIdentifier("settings.openai.toggle_secret")
                    }

                    HStack {
                        Button(String(localized: "settings.openai.action.save", defaultValue: "Save OpenAI Key")) {
                            saveOpenAIKey()
                        }
                        .disabled(openAIKey.isEmpty)
                        .accessibilityIdentifier("settings.openai.save")

                        if keyManager.hasOpenAIKey {
                            Button(String(localized: "settings.openai.action.clear", defaultValue: "Clear"), role: .destructive) {
                                clearOpenAIKey()
                            }
                            .buttonStyle(.borderless)
                            .accessibilityIdentifier("settings.openai.clear")
                        }
                    }
                }
                .padding(.vertical, 4)
            }

            // Gemini Section
            Section {
                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        Image(systemName: "sparkles")
                            .foregroundColor(.blue)
                        Text(String(localized: "settings.gemini.header", defaultValue: "Google Gemini"))
                            .font(.headline)
                        Spacer()
                        statusBadge(configured: keyManager.hasGeminiKey)
                    }

                    Text(String(localized: "settings.gemini.description", defaultValue: "Alternative AI provider for title/description generation. Get your key from [Google AI Studio](https://aistudio.google.com/app/apikey)."))
                        .font(.caption)
                        .foregroundColor(.secondary)

                    HStack {
                        Text(String(localized: "settings.gemini.key_label", defaultValue: "API Key"))
                            .frame(width: 100, alignment: .leading)
                        Group {
                            if showGeminiKey {
                                TextField(String(localized: "settings.gemini.key_placeholder", defaultValue: "Enter API Key"), text: $geminiKey)
                            } else {
                                SecureField(String(localized: "settings.gemini.key_placeholder", defaultValue: "Enter API Key"), text: $geminiKey)
                            }
                        }
                        .textFieldStyle(.roundedBorder)
                        .accessibilityIdentifier("settings.gemini.key")

                        Button(action: { showGeminiKey.toggle() }, label: {
                            Image(systemName: showGeminiKey ? "eye.slash" : "eye")
                        })
                        .buttonStyle(.borderless)
                        .accessibilityIdentifier("settings.gemini.toggle_secret")
                    }

                    HStack {
                        Button(String(localized: "settings.gemini.action.save", defaultValue: "Save Gemini Key")) {
                            saveGeminiKey()
                        }
                        .disabled(geminiKey.isEmpty)
                        .accessibilityIdentifier("settings.gemini.save")

                        if keyManager.hasGeminiKey {
                            Button(String(localized: "settings.gemini.action.clear", defaultValue: "Clear"), role: .destructive) {
                                clearGeminiKey()
                            }
                            .buttonStyle(.borderless)
                            .accessibilityIdentifier("settings.gemini.clear")
                        }
                    }
                }
                .padding(.vertical, 4)
            }

            // Security Info & Clear All
            Section {
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Image(systemName: "lock.shield.fill")
                            .foregroundColor(.blue)
                        Text(String(localized: "settings.security.header", defaultValue: "Security"))
                            .font(.headline)
                    }

                    Text(String(localized: "settings.security.description", defaultValue: "All API keys are stored securely in your Mac's Keychain. They never leave your device and are encrypted at rest."))
                        .font(.caption)
                        .foregroundColor(.secondary)

                    Button(String(localized: "settings.action.clear_all", defaultValue: "Clear All API Keys"), role: .destructive) {
                        showingClearAlert = true
                    }
                    .padding(.top, 4)
                    .accessibilityIdentifier("settings.keys.clear_all")
                }
                .padding(.vertical, 4)
            }
        }
        .formStyle(.grouped)
        .padding()
        .alert(String(localized: "settings.clear_all.title", defaultValue: "Clear All API Keys?"), isPresented: $showingClearAlert) {
            Button(String(localized: "settings.action.cancel", defaultValue: "Cancel"), role: .cancel) {}
            Button(String(localized: "settings.action.clear_all_confirm", defaultValue: "Clear All"), role: .destructive) {
                clearAllKeys()
            }
            .accessibilityIdentifier("settings.keys.clear_all_confirm")
        } message: {
            Text(String(localized: "settings.clear_all.message", defaultValue: "This will remove all stored API credentials. You'll need to re-enter them to use YouTube upload and AI features."))
        }
        .alert(String(localized: "settings.error.title", defaultValue: "Error"), isPresented: .init(
            get: { saveError != nil },
            set: { if !$0 { saveError = nil } }
        )) {
            Button(String(localized: "settings.action.ok", defaultValue: "OK")) { saveError = nil }
                .accessibilityIdentifier("settings.save_error.ok")
        } message: {
            if let error = saveError {
                Text(String(localized: "settings.error.message", defaultValue: "Error") + ": \(error)")
            }
        }
        .overlay(alignment: .top) {
            if showingSaveSuccess {
                HStack {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundColor(.green)
                    Text(String(localized: "settings.save_success", defaultValue: "Saved successfully"))
                }
                .padding()
                .background(Color(NSColor.controlBackgroundColor))
                .cornerRadius(Theme.Dimensions.cornerRadius)
                .overlay(
                    RoundedRectangle(cornerRadius: Theme.Dimensions.cornerRadius)
                        .stroke(Color.secondary.opacity(0.2), lineWidth: 1)
                ).onAppear {
                    DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                        withAnimation {
                            showingSaveSuccess = false
                        }
                    }
                }
            }
        }
        .animation(.easeInOut, value: showingSaveSuccess)
    }

    // MARK: - Helper Views

    @ViewBuilder
    private func statusBadge(configured: Bool) -> some View {
        if configured {
            Label(String(localized: "settings.status.configured", defaultValue: "Configured"), systemImage: "checkmark.circle.fill")
                .font(.caption)
                .foregroundColor(.green)
        } else {
            Label(String(localized: "settings.status.not_set", defaultValue: "Not Set"), systemImage: "circle.dashed")
                .font(.caption)
                .foregroundColor(.secondary)
        }
    }

    // MARK: - Actions

    private func saveYouTubeCredentials() {
        Task {
            do {
                try await keyManager.saveYouTubeCredentials(
                    clientID: youtubeClientID,
                    clientSecret: youtubeClientSecret
                )
                youtubeClientID = ""
                youtubeClientSecret = ""
                withAnimation { showingSaveSuccess = true }
            } catch {
                saveError = error.localizedDescription
            }
        }
    }

    private func clearYouTubeCredentials() {
        Task {
            try? await keyManager.clearYouTubeCredentials()
        }
    }

    private func saveOpenAIKey() {
        Task {
            do {
                try await keyManager.saveOpenAIKey(openAIKey)
                openAIKey = ""
                withAnimation { showingSaveSuccess = true }
            } catch {
                saveError = error.localizedDescription
            }
        }
    }

    private func clearOpenAIKey() {
        Task {
            try? await keyManager.clearOpenAIKey()
        }
    }

    private func saveGeminiKey() {
        Task {
            do {
                try await keyManager.saveGeminiKey(geminiKey)
                geminiKey = ""
                withAnimation { showingSaveSuccess = true }
            } catch {
                saveError = error.localizedDescription
            }
        }
    }

    private func clearGeminiKey() {
        Task {
            try? await keyManager.clearGeminiKey()
        }
    }

    private func clearAllKeys() {
        Task {
            try? await keyManager.clearAllKeys()
        }
    }
}

#Preview {
    APIKeysSettingsView()
        .frame(width: 500, height: 600)
}
