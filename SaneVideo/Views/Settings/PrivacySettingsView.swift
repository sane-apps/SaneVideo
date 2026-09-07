import SaneUI
import SwiftUI

struct PrivacySettingsView: View {
    @Binding var selectedTab: String

    var body: some View {
        SaneSettingsPage {
            CompactSection("Your Media", icon: "lock.shield", iconColor: .green) {
                Text("Recording, editing, and export stay on your Mac. SaneVideo does not send your media to SaneApps servers.")
                    .saneReadableSupportText()
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(12)
            }

            CompactSection("Captions & Transcripts", icon: "captions.bubble", iconColor: .cyan) {
                TranscriptionEnginePicker()
                    .padding(12)
            }

            CompactSection("Services & Policies", icon: "doc.text", iconColor: .blue) {
                VStack(alignment: .leading, spacing: 12) {
                    Button {
                        selectedTab = "apikeys"
                    } label: {
                        Label(String(localized: "settings.privacy.manage_api_keys", defaultValue: "Manage API Keys"), systemImage: "key.fill")
                    }
                    .buttonStyle(SaneActionButtonStyle())
                    .help("View optional upload settings and saved credential controls.")
                    .accessibilityIdentifier("settings.privacy.manage_api_keys_button")

                    Button {
                        if let webURL = URL(string: "https://sanevideo.com/privacy") {
                            NSWorkspace.shared.open(webURL)
                        }
                    } label: {
                        Label(String(localized: "settings.privacy.view_policy", defaultValue: "View Privacy Policy"), systemImage: "doc.text.fill")
                    }
                    .buttonStyle(SaneActionButtonStyle())
                    .help("Open the full privacy policy.")

                    Button {
                        if let webURL = URL(string: "https://github.com/sane-apps/SaneVideo/blob/main/LICENSE") {
                            NSWorkspace.shared.open(webURL)
                        }
                    } label: {
                        Label(String(localized: "settings.privacy.view_license", defaultValue: "View License"), systemImage: "doc.text.fill")
                    }
                    .buttonStyle(SaneActionButtonStyle())
                    .help("Open SaneVideo’s MIT license.")
                }
                .padding(12)
            }
        }
    }
}
