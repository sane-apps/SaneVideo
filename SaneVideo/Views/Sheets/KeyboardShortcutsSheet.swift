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
                        .foregroundColor(Color.stone)
                }
                .buttonStyle(.plain)
                .keyboardShortcut(.cancelAction)
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
                        ("Step Forward", "→"),
                        ("Seek Back 10s", "⇧←"),
                        ("Seek Forward 10s", "⇧→")
                    ])

                    ShortcutSection(title: "Navigation", shortcuts: [
                        ("Go to Start", "Home"),
                        ("Go to End", "End"),
                        ("Mark In Point", "I"),
                        ("Mark Out Point", "O"),
                        ("Clear In/Out", "⇧⌘X"),
                        ("Fit Timeline", "⇧Z")
                    ])

                    ShortcutSection(title: "Selection", shortcuts: [
                        ("Select All Clips", "⌘A"),
                        ("Deselect All", "Esc"),
                        ("Select at Playhead", "D"),
                        ("Toggle Selection", "⌘+Click"),
                        ("Range Selection", "⇧+Click"),
                        ("Next Clip", "↓"),
                        ("Previous Clip", "↑"),
                        ("Extend Selection", "⇧↑/↓")
                    ])

                    ShortcutSection(title: "Editing", shortcuts: [
                        ("Copy Clip", "⌘C"),
                        ("Cut Clip", "⌘X"),
                        ("Paste Clip", "⌘V"),
                        ("Duplicate Clip", "⌘D"),
                        ("Split Clip", "⌘B"),
                        ("Delete Clip", "⌫")
                    ])

                    ShortcutSection(title: "Timeline", shortcuts: [
                        ("Zoom In", "⌘+"),
                        ("Zoom Out", "⌘-"),
                        ("Fit to View", "⌘0"),
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
                        ("Toggle Inspector", "⌥⌘I"),
                        ("Toggle Captions", "⌥⌘T"),
                        ("Open Library", "⌘L")
                    ])

                    ShortcutSection(title: "Export", shortcuts: [
                        ("Export Video", "⌘E"),
                        ("Export GIF", "⇧⌘G")
                    ])
                }
                .padding()
            }
        }
        .frame(width: 500, height: 800)
        .subtleGlass(radius: 12)
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
                .foregroundColor(Color.stone)

            ForEach(shortcuts, id: \.0) { label, key in
                HStack {
                    Text(label)
                        .foregroundColor(.primary)
                    Spacer()
                    Text(key)
                        .font(.system(.body, design: .monospaced))
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(Color.stone.opacity(0.1))
                        .cornerRadius(4)
                }
            }
        }
    }
}

#Preview {
    KeyboardShortcutsSheet()
}
