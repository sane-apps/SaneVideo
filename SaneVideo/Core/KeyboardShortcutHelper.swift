import SwiftUI

enum KeyboardShortcutHelper {
    static func helpWithShortcut(_ description: String, key: String, modifiers: EventModifiers = []) -> String {
        let shortcut = shortcutString(key: key, modifiers: modifiers)
        return "\(description) (\(shortcut))"
    }

    static func helpWithShortcut(_ description: String, key: KeyEquivalent, modifiers: EventModifiers = []) -> String {
        let keyString = String(key.character)
        return helpWithShortcut(description, key: keyString, modifiers: modifiers)
    }

    private static func shortcutString(key: String, modifiers: EventModifiers) -> String {
        var parts: [String] = []

        if modifiers.contains(.control) {
            parts.append("⌃")
        }
        if modifiers.contains(.option) {
            parts.append("⌥")
        }
        if modifiers.contains(.shift) {
            parts.append("⇧")
        }
        if modifiers.contains(.command) {
            parts.append("⌘")
        }

        let keyName: String
        switch key.lowercased() {
        case "delete", "⌫":
            keyName = "Delete"
        case "return", "⏎":
            keyName = "Return"
        case "space", " ":
            keyName = "Space"
        case "escape", "esc":
            keyName = "Esc"
        case "tab", "⇥":
            keyName = "Tab"
        default:
            keyName = key.uppercased()
        }

        parts.append(keyName)
        return parts.joined()
    }
}
