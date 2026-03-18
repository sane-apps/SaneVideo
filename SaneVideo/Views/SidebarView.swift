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
            // RAIL: 3-tab navigation (Media, Transcript, Projects) + Quick Actions
            VStack(spacing: 12) {
                SidebarRailItem(icon: "film", label: "Media", tag: 0, selection: $selectedTab)
                SidebarRailItem(icon: "text.quote", label: "Transcript", tag: 1, selection: $selectedTab)
                SidebarRailItem(icon: "folder", label: "Projects", tag: 2, selection: $selectedTab)

                Divider()
                    .padding(.vertical, 8)

                // Quick Actions (2025-12-31: Magic Fix moved to Inspector Smart Tools)
                Text("Create")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(Theme.Colors.textSecondary)
                    .textCase(.uppercase)
                    .padding(.top, 4)

                QuickActionButton(icon: "photo", label: "Thumbnail", action: {
                    NotificationCenter.default.post(name: NSNotification.Name("GenerateThumbnail"), object: nil)
                })
                .help("Generate AI Thumbnail (⌘T)")

                QuickActionButton(icon: "waveform", label: "Voiceover", action: {
                    NotificationCenter.default.post(name: NSNotification.Name("GenerateVoiceover"), object: nil)
                })
                .help("Generate Voiceover")

                QuickActionButton(icon: "square.stack.3d.up", label: "Shorts", action: {
                    NotificationCenter.default.post(name: NSNotification.Name("ShowRepurposingSheet"), object: nil)
                })
                .help("Create Shorts (⇧⌘R)")

                Spacer()
                
                // Help link at bottom (non-intrusive)
                Button {
                    NotificationCenter.default.post(
                        name: NSNotification.Name("ShowKeyboardShortcuts"), object: nil
                    )
                } label: {
                    Image(systemName: "questionmark.circle")
                        .font(.system(size: 16))
                        .foregroundStyle(Theme.Colors.accentSoft)
                }
                .buttonStyle(.plain)
                .help("Open local help and keyboard shortcuts")
            }
            .frame(width: 64)
            .padding(.vertical, 16)
            .background(
                LinearGradient(
                    colors: [
                        Color.deepNavy.opacity(0.92),
                        Color.navy.opacity(0.88),
                        Theme.Colors.accentDeep.opacity(0.55)
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )
            )

            Divider()

            // CONTENT: Contextual Sidebar Content
            VStack(spacing: 0) {
                Group {
                    if selectedTab == 0 {
                        LibraryView(selectedClip: $selectedClip)
                    } else if selectedTab == 1 {
                        // Transcript tab = text-based editing (Descript-style)
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
        .onReceive(NotificationCenter.default.publisher(for: NSNotification.Name("ShowSidebarProjects"))) { _ in
            selectedTab = 2
        }
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
                    .foregroundStyle(isSelected ? Theme.Colors.accent : Color.white.opacity(0.72))

                Text(label)
                    .font(.system(size: 10, weight: .medium))
                    .foregroundColor(isSelected ? Theme.Colors.accent : Color.white.opacity(0.72))
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 8)
            .background {
                if isSelected {
                    Capsule()
                        .fill(Theme.Colors.accent.opacity(0.18))
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

// MARK: - Quick Action Button

private struct QuickActionButton: View {
    let icon: String
    let label: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 4) {
                Image(systemName: icon)
                    .font(.system(size: 16))
                    .foregroundStyle(Theme.Colors.accent)

                Text(label)
                    .font(.system(size: 10, weight: .medium))
                    .foregroundColor(Color.white.opacity(0.72))
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 6)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .hoverScale(1.1)
    }
}
