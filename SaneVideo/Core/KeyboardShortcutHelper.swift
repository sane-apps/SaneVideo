//
//  KeyboardShortcutHelper.swift
//  SaneVideo
//
//  Helper for displaying keyboard shortcuts in tooltips and help
//

import SwiftUI

/// Generates consistent help text with keyboard shortcuts
enum KeyboardShortcutHelper {
    /// Generate help text with shortcut notation
    static func helpWithShortcut(_ description: String, key: String, modifiers: EventModifiers = []) -> String {
        let shortcut = shortcutString(key: key, modifiers: modifiers)
        return "\(description) (\(shortcut))"
    }

    static func helpWithShortcut(_ description: String, key: KeyEquivalent, modifiers: EventModifiers = []) -> String {
        let keyString = String(key.character)
        return helpWithShortcut(description, key: keyString, modifiers: modifiers)
    }

    /// Format shortcut for display
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

        // Special key names
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
