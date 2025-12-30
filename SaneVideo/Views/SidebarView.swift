//
//  SidebarView.swift
//  SaneVideo
//
//  Main sidebar with rail navigation and contextual content
//

import SwiftUI

struct SidebarView: View {
    @Environment(AppState.self) var appState
    @Binding var selectedClip: VideoClip?
    @State private var selectedTab = 0

    var body: some View {
        HStack(spacing: 0) {
            // RAIL: 3-tab navigation (Media, Script, Projects)
            VStack(spacing: 20) {
                SidebarRailItem(icon: "film", label: "Media", tag: 0, selection: $selectedTab)
                SidebarRailItem(icon: "doc.text", label: "Script", tag: 1, selection: $selectedTab)
                SidebarRailItem(icon: "folder", label: "Projects", tag: 2, selection: $selectedTab)

                Spacer()
                
                // Help link at bottom (non-intrusive)
                Button {
                    if let url = URL(string: "https://sanevideo.app/help") {
                        NSWorkspace.shared.open(url)
                    }
                } label: {
                    Image(systemName: "questionmark.circle")
                        .font(.system(size: 16))
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .help("Get Help")
            }
            .frame(width: 50)
            .padding(.vertical, 16)
            .background(.ultraThinMaterial)

            Divider()

            // CONTENT: Contextual Sidebar Content
            VStack(spacing: 0) {
                Group {
                    if selectedTab == 0 {
                        LibraryView(selectedClip: $selectedClip)
                    } else if selectedTab == 1 {
                        // Script tab = text-based editing (Descript-style)
                        TranscriptionEditorView(selectedClip: $selectedClip)
                    } else {
                        // Projects tab = compact project browser
                        CompactProjectBrowserView()
                    }
                }
                .transition(.asymmetric(
                    insertion: .opacity.combined(with: .move(edge: .trailing)),
                    removal: .opacity
                ))
            }
            .frame(maxWidth: .infinity)
        }
        .frame(minWidth: 240, idealWidth: 300, maxWidth: 450)
        .animation(.spring(response: 0.3, dampingFraction: 0.7), value: selectedTab)
    }
}

// MARK: - Sidebar Rail Item

private struct SidebarRailItem: View {
    let icon: String
    let label: String
    let tag: Int
    @Binding var selection: Int

    var isSelected: Bool { selection == tag }

    var body: some View {
        Button {
            selection = tag
        } label: {
            VStack(spacing: 4) {
                Image(systemName: isSelected ? "\(icon).fill" : icon)
                    .font(.system(size: 18))
                    .foregroundStyle(isSelected ? Color.accentColor : Color.secondary)

                Text(label)
                    .font(.system(size: 9, weight: .medium))
                    .foregroundColor(isSelected ? Color.accentColor : .secondary)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 8)
            .background {
                if isSelected {
                    Capsule()
                        .fill(Color.accentColor.opacity(0.1))
                        .padding(.horizontal, 4)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .hoverScale(1.1)
        .animation(.smoothUI, value: isSelected)
        .help(label)
    }
}
