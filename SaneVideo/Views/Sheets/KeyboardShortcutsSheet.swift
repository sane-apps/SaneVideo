import SwiftUI

struct KeyboardShortcutsSheet: View {
    @Environment(\.dismiss) var dismiss

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Keyboard Shortcuts")
                    .saneReadableSectionTitle()
                Spacer()
                Button {
                    dismiss()
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: Theme.Typography.iconSizeLG, weight: .semibold))
                        .foregroundColor(Theme.Colors.textSecondary)
                }
                .buttonStyle(.plain)
                .keyboardShortcut(.cancelAction)
                .help("Close")
            }
            .padding()
            .background(Color(NSColor.controlBackgroundColor))

            Divider()

            ScrollView {
                VStack(spacing: 24) {
                    ShortcutSection(title: "Recording (works in any app)", shortcuts: [
                        ("Start / Stop Recording", "⌥⌘R"),
                        ("Pause / Resume", "⌥⌘P")
                    ])

                    ShortcutSection(title: "Project", shortcuts: [
                        ("New Recording", "⌘N"),
                        ("Show Projects", "⌘O"),
                        ("Save Project", "⌘S"),
                        ("Import Video", "⌘I"),
                        ("Share", "⇧⌘S"),
                        ("Toggle Sidebar", "⌥⌘S"),
                        ("Toggle Inspector", "⌥⌘I")
                    ])

                    ShortcutSection(title: "Playback", shortcuts: [
                        ("Play / Pause", "Space"),
                        ("Pause", "K"),
                        ("Play Backward / Forward", "J / L"),
                        ("Back / Forward One Frame", "← / →"),
                        ("Back / Forward 10 Seconds", "⇧← / ⇧→"),
                        ("Go to Start / End", "Home / End"),
                        ("Previous / Next Cut", "↑ / ↓")
                    ])

                    ShortcutSection(title: "Editing", shortcuts: [
                        ("Split at Playhead", "⌘B"),
                        ("Delete Clip", "⌫"),
                        ("Undo / Redo", "⌘Z / ⇧⌘Z"),
                        ("Copy / Cut / Paste Clip", "⌘C / ⌘X / ⌘V"),
                        ("Duplicate Clip", "⌘D"),
                        ("Clean Up Selected Clip", "⇧⌘M"),
                        ("Mark In / Out", "I / O"),
                        ("Clear In / Out", "⇧⌘X")
                    ])

                    ShortcutSection(title: "Selection", shortcuts: [
                        ("Select All Clips", "⌘A"),
                        ("Deselect All", "Esc"),
                        ("Select Clip at Playhead", "D"),
                        ("Add to Selection", "⌘-Click"),
                        ("Select a Range", "⇧-Click"),
                        ("Extend Selection", "⇧↑ / ⇧↓")
                    ])

                    ShortcutSection(title: "Timeline", shortcuts: [
                        ("Zoom In / Out", "⌘= / ⌘-"),
                        ("Fit Timeline", "⌘0"),
                        ("Toggle Snapping", "N"),
                        ("Toggle Magnetic", "M")
                    ])

                    ShortcutSection(title: "Export", shortcuts: [
                        ("Export Video", "⌘E"),
                        ("Create Shorts", "⇧⌘R"),
                        ("Export GIF", "⇧⌘G"),
                        ("Make Thumbnail", "⌘T"),
                        ("Export Transcript (PDF)", "⌥⌘T"),
                        ("Teleprompter Script", "⇧⌘D")
                    ])
                }
                .padding()
            }
        }
        .frame(width: 500, height: 800)
        .sanePanel(radius: 18, emphasized: true, accent: Theme.Colors.accentSoft)
        .subtleGlass(radius: 12)
    }
}

struct ShortcutSection: View {
    let title: String
    let shortcuts: [(String, String)]

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title)
                .saneReadableLabel()

            ForEach(shortcuts, id: \.0) { label, key in
                HStack {
                    Text(label)
                        .saneReadableBody()
                    Spacer()
                    Text(key)
                        .font(.system(size: Theme.Typography.fontSizeSM, weight: .medium, design: .monospaced))
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(Theme.Colors.editorPanelElevated)
                        .cornerRadius(4)
                }
            }
        }
    }
}

#Preview {
    KeyboardShortcutsSheet()
}
