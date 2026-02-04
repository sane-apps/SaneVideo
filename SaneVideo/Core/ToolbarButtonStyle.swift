//
//  ToolbarButtonStyle.swift
//  SaneVideo
//
//  Unified toolbar button styling for Timeline actions
//

import SwiftUI

/// A clean, glass-morphism style for toolbar action buttons
/// Replaces the "rainbow" gradient buttons with a cohesive look
struct ToolbarActionStyle: ButtonStyle {
    var isEnabled: Bool = true
    var isPrimary: Bool = false

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 12, weight: isPrimary ? .semibold : .medium))
            .foregroundColor(isEnabled ? .primary : Color.stone)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(
                RoundedRectangle(cornerRadius: 6)
                    .fill(configuration.isPressed ? Color.stone.opacity(0.2) : Color.stone.opacity(0.1))
            )
            .opacity(isEnabled ? 1.0 : 0.5)
    }
}

/// Destructive action button (Delete)
struct DestructiveToolbarStyle: ButtonStyle {
    var isEnabled: Bool = true

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 12, weight: .medium))
            .foregroundColor(isEnabled ? .red : Color.stone)
            .frame(width: 28, height: 24)
            .background(
                RoundedRectangle(cornerRadius: 4)
                    .fill(configuration.isPressed ? Color.red.opacity(0.2) : Color.clear)
            )
    }
}
