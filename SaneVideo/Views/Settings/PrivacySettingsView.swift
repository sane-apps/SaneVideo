//
//  PrivacySettingsView.swift
//  SaneVideo
//
//  Privacy and AI settings view
//

import SwiftUI

struct PrivacySettingsView: View {
    var body: some View {
        Form {
            Section {
                InformationBox(
                    text: "SaneVideo is local-first. Recording, editing, teleprompter, and export work on your Mac without sending media to SaneApps servers.",
                    color: Theme.Colors.accent,
                    icon: "lock.shield.fill"
                )
            }

            Section(header: Text(String(localized: "settings.privacy.header", defaultValue: "Privacy & AI")).saneReadableSectionTitle()) {
                VStack(alignment: .leading, spacing: 12) {
                    Text(String(localized: "settings.privacy.description", defaultValue: "SaneVideo prioritizes your privacy. All core AI features run 100% on your Mac, ensuring your data never leaves your device."))
                        .saneReadableSupportText()
                    
                    PrivacyBadge()
                        .padding(.vertical, 4)
                    
                    Text(String(localized: "settings.privacy.cloud_note", defaultValue: "All AI features run 100% on-device using Apple Intelligence. No cloud services required."))
                        .saneReadableSupportText()

                    HelperText(
                        text: "If you choose optional cloud-connected features like direct upload or third-party APIs, they stay separate from the normal local demo workflow.",
                        icon: "externaldrive.badge.icloud"
                    )

                    Divider()
                        .padding(.vertical, 4)

                    NavigationLink {
                        APIKeysSettingsView()
                    } label: {
                        Label(String(localized: "settings.privacy.manage_api_keys", defaultValue: "Manage API Keys"), systemImage: "key.fill")
                    }
                    .help("Open optional API key settings for direct upload and cloud-powered extras.")
                    .accessibilityIdentifier("settings.privacy.manage_api_keys_button")
                    
                    Button {
                        // Try to open PRIVACY.md from bundle, fallback to web
                        if let privacyURL = Bundle.main.url(forResource: "PRIVACY", withExtension: "md") {
                            NSWorkspace.shared.open(privacyURL)
                        } else if let webURL = URL(string: "https://sanevideo.app/privacy") {
                            NSWorkspace.shared.open(webURL)
                        }
                    } label: {
                        Label(String(localized: "settings.privacy.view_policy", defaultValue: "View Privacy Policy"), systemImage: "doc.text.fill")
                    }
                    .buttonStyle(.link)
                    .help("Open the full privacy policy.")
                    
                    Button {
                        // Try to open TERMS.md from bundle, fallback to web
                        if let termsURL = Bundle.main.url(forResource: "TERMS", withExtension: "md") {
                            NSWorkspace.shared.open(termsURL)
                        } else if let webURL = URL(string: "https://sanevideo.app/terms") {
                            NSWorkspace.shared.open(webURL)
                        }
                    } label: {
                        Label(String(localized: "settings.privacy.view_terms", defaultValue: "View Terms of Service"), systemImage: "doc.text.fill")
                    }
                    .buttonStyle(.link)
                    .help("Open the full terms of service.")
                }
            }
        }
        .padding()
    }
}
