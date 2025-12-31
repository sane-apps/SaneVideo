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
                SidebarRailItem(icon: "film", label: "Library", tag: 0, selection: $selectedTab)
                SidebarRailItem(icon: "text.quote", label: "Transcript", tag: 1, selection: $selectedTab)
                SidebarRailItem(icon: "folder", label: "Projects", tag: 2, selection: $selectedTab)

                Divider()
                    .padding(.vertical, 8)

                // Quick Actions (commonly hidden features)
                Text("QUICK")
                    .font(.system(size: 7, weight: .bold))
                    .foregroundStyle(.tertiary)
                    .textCase(.uppercase)
                    .padding(.top, 4)

                QuickActionButton(icon: "wand.and.stars", label: "Magic Fix", action: {
                    NotificationCenter.default.post(name: NSNotification.Name("TriggerMagicFix"), object: nil)
                })
                .help("Magic Fix Selected Clip (⇧⌘M)")

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
            // CONSISTENCY: Use controlBackgroundColor to match main editor
            .background(Color(nsColor: .controlBackgroundColor))

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
                    .foregroundStyle(Color.accentColor)

                Text(label)
                    .font(.system(size: 8, weight: .medium))
                    .foregroundColor(.secondary)
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
