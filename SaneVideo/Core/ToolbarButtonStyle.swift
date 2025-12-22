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
            .foregroundColor(isEnabled ? .white : .secondary)
            .padding(.horizontal, isPrimary ? 12 : 10)
            .padding(.vertical, 7)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(isEnabled ? Material.regular : Material.ultraThin)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(isEnabled ? Color.white.opacity(0.15) : Color.clear, lineWidth: 1)
            )
            .scaleEffect(configuration.isPressed ? 0.96 : 1.0)
            .animation(.spring(response: 0.2, dampingFraction: 0.6), value: configuration.isPressed)
            .opacity(isEnabled ? 1.0 : 0.5)
    }
}

/// Destructive action button (Delete)
struct DestructiveToolbarStyle: ButtonStyle {
    var isEnabled: Bool = true

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 13, weight: .medium))
            .foregroundColor(isEnabled ? .white : .secondary)
            .frame(width: 32, height: 28)
            .background(
                RoundedRectangle(cornerRadius: 6)
                    .fill(isEnabled ? Theme.Colors.destructive.opacity(0.8) : Color.gray.opacity(0.2))
            )
            .scaleEffect(configuration.isPressed ? 0.92 : 1.0)
            .animation(.spring(response: 0.2, dampingFraction: 0.6), value: configuration.isPressed)
    }
}
