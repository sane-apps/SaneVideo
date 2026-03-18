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
            .font(.system(size: Theme.Typography.fontSizeSM, weight: isPrimary ? .semibold : .medium))
            .foregroundColor(isEnabled ? Theme.Colors.textPrimary : Theme.Colors.textSecondary)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(
                RoundedRectangle(cornerRadius: 6)
                    .fill(configuration.isPressed ? Theme.Colors.secondaryBackground.opacity(0.9) : Theme.Colors.secondaryBackground.opacity(0.65))
            )
            .opacity(isEnabled ? 1.0 : 0.5)
    }
}

/// Destructive action button (Delete)
struct DestructiveToolbarStyle: ButtonStyle {
    var isEnabled: Bool = true

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: Theme.Typography.fontSizeSM, weight: .medium))
            .foregroundColor(isEnabled ? .red : Theme.Colors.textSecondary)
            .frame(width: 28, height: 24)
            .background(
                RoundedRectangle(cornerRadius: 4)
                    .fill(configuration.isPressed ? Color.red.opacity(0.2) : Color.clear)
            )
    }
}
