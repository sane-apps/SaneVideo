import SaneUI
import SwiftUI

struct SidebarView: View {
    @Environment(AppState.self) var appState
    @Binding var selectedClip: VideoClip?
    @State private var selectedTab = 2

    var body: some View {
        VStack(spacing: 0) {
            Picker("Sidebar", selection: $selectedTab) {
                Text("Projects").tag(2)
                Text("Clips").tag(0)
                Text("Transcript").tag(1)
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .controlSize(.regular)
            .frame(maxWidth: .infinity)
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .accessibilityIdentifier("sidebar.tabs")

            Group {
                if selectedTab == 0 {
                    LibraryView(selectedClip: $selectedClip)
                } else if selectedTab == 1 {
                    TranscriptionEditorView(selectedClip: $selectedClip)
                } else {
                    CompactProjectBrowserView()
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            HStack(spacing: 12) {
                Button {
                    NotificationCenter.default.post(name: NSNotification.Name("ShowKeyboardShortcuts"), object: nil)
                } label: {
                    Image(systemName: "questionmark.circle")
                        .font(.system(size: 15))
                }
                .buttonStyle(.borderless)
                .help("Help and keyboard shortcuts")
                Spacer()
                SaneStickyDonateButton(url: OpenSourceRelease.donationURL)
            }
            .padding(12)
        }
        .onReceive(NotificationCenter.default.publisher(for: NSNotification.Name("ShowSidebarProjects"))) { _ in
            selectedTab = 2
        }
        .onReceive(NotificationCenter.default.publisher(for: NSNotification.Name("ShowSidebarTranscript"))) { _ in
            selectedTab = 1
        }
    }
}

