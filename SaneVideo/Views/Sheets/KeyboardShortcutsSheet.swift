//
//  KeyboardShortcutsSheet.swift
//  SaneVideo
//
//  Created by SaneVideo Refactor
//

import SwiftUI

struct KeyboardShortcutsSheet: View {
    @Environment(\.dismiss) var dismiss

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Text("Keyboard Shortcuts")
                    .font(.headline)
                Spacer()
                Button {
                    dismiss()
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundColor(.secondary)
                }
                .buttonStyle(.plain)
            }
            .padding()
            .background(Color(NSColor.controlBackgroundColor))

            Divider()

            // Content
            ScrollView {
                VStack(spacing: 24) {
                    ShortcutSection(title: "General", shortcuts: [
                        ("New Recording", "⌘N"),
                        ("Open Project", "⌘O"),
                        ("Save Project", "⌘S"),
                        ("Import Media", "⌘I"),
                        ("Share Project", "⇧⌘S"),
                        ("Undo", "⌘Z"),
                        ("Redo", "⇧⌘Z")
                    ])

                    ShortcutSection(title: "Playback", shortcuts: [
                        ("Play / Pause", "Space"),
                        ("Pause", "K"),
                        ("Shuttle Backward", "J"),
                        ("Shuttle Forward", "L"),
                        ("Step Backward", "←"),
                        ("Step Forward", "→")
                    ])

                    ShortcutSection(title: "Timeline", shortcuts: [
                        ("Zoom In", "⌘+"),
                        ("Zoom Out", "⌘-"),
                        ("Fit to View", "⌘0"),
                        ("Split Clip", "⌘B"),
                        ("Delete Clip", "⌫"),
                        ("Toggle Snapping", "N"),
                        ("Toggle Magnetic", "M")
                    ])

                    ShortcutSection(title: "AI Tools", shortcuts: [
                        ("Super Magic Fix", "⇧⌘M"),
                        ("Refine Captions", "⇧⌘T"),
                        ("Smart Thumbnail", "⌘T")
                    ])

                    ShortcutSection(title: "View", shortcuts: [
                        ("Toggle Sidebar", "⌥⌘S"),
                        ("Toggle Inspector", "⌥⌘I")
                    ])

                    ShortcutSection(title: "Export", shortcuts: [
                        ("Export Video", "⌘E"),
                        ("Export GIF", "⇧⌘G")
                    ])
                }
                .padding()
            }
        }
        .frame(width: 500, height: 600)
    }
}

struct ShortcutSection: View {
    let title: String
    let shortcuts: [(String, String)]

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title)
                .font(.subheadline)
                .fontWeight(.bold)
                .foregroundColor(.secondary)

            ForEach(shortcuts, id: \.0) { label, key in
                HStack {
                    Text(label)
                        .foregroundColor(.primary)
                    Spacer()
                    Text(key)
                        .font(.system(.body, design: .monospaced))
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(Color.secondary.opacity(0.1))
                        .cornerRadius(4)
                }
            }
        }
    }
}

#Preview {
    KeyboardShortcutsSheet()
}
