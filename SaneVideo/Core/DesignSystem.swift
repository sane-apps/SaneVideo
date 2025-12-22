//
//  DesignSystem.swift
//  SaneVideo
//
//  Created by SaneVideo Refactor
//

import SwiftUI

enum Theme {

    // UNIFIED COLOR PALETTE - Professional Dark Mode optimized
    // Primary: Purple/Indigo family (brand color)
    // Secondary: Blue family (actions)
    // Accent: Teal for highlights
    enum Colors {
        // Semantic Application Colors (Adaptive)
        static let background = Color(nsColor: .windowBackgroundColor)
        static let secondaryBackground = Color(nsColor: .controlBackgroundColor)

        // BRAND COLORS (System Integrated)
        static let accent = Color.accentColor
        
        static let accentGradient = Color.accentColor // Effectively 1:1 with system for snappiness

        // SECONDARY (System Integrated)
        static let action = Color.accentColor
        
        static let secondaryGradient = Color.accentColor
        
        // SEMANTIC COLORS (System Integrated)
        static let warning = Color.orange
        static let destructive = Color.red

        // Semantic Text (Adapts to Light/Dark mode)
        static let textPrimary = Color.primary
        static let textSecondary = Color.secondary

        // UI ELEMENT COLORS
        static let cardBackground = Color.white.opacity(0.05)
        static let border = Color.white.opacity(0.1)
        static let divider = Color.white.opacity(0.08)

    }

    enum Dimensions {
        static let cornerRadius: CGFloat = 8
        static let smallCornerRadius: CGFloat = 4
        static let padding: CGFloat = 12
    }
}

// Helper for Hex Colors
extension Color {
    init(hex: UInt, alpha: Double = 1) {
        self.init(
            .sRGB,
            red: Double((hex >> 16) & 0xFF) / 255,
            green: Double((hex >> 08) & 0xFF) / 255,
            blue: Double((hex >> 00) & 0xFF) / 255,
            opacity: alpha
        )
    }

    init(hex: String) {
        let hex = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var int: UInt64 = 0
        Scanner(string: hex).scanHexInt64(&int)
        let a, r, g, b: UInt64
        switch hex.count {
        case 3: // RGB (12-bit)
            (a, r, g, b) = (255, (int >> 8) * 17, (int >> 4 & 0xF) * 17, (int & 0xF) * 17)
        case 6: // RGB (24-bit)
            (a, r, g, b) = (255, int >> 16, int >> 8 & 0xFF, int & 0xFF)
        case 8: // ARGB (32-bit)
            (a, r, g, b) = (int >> 24, int >> 16 & 0xFF, int >> 8 & 0xFF, int & 0xFF)
        default:
            (a, r, g, b) = (1, 1, 1, 0)
        }

        self.init(
            .sRGB,
            red: Double(r) / 255,
            green: Double(g) / 255,
            blue: Double(b) / 255,
            opacity: Double(a) / 255
        )
    }
}

// Reusable Button Styles (Active)

// MARK: - Icon Button Style (Circular)

/// A circular button style for icon-only actions (Recording, Timeline toolbar)
struct IconButtonStyle: ButtonStyle {
    enum Size {
        case small, medium, large

        var diameter: CGFloat {
            switch self {
            case .small: return 36
            case .medium: return 48
            case .large: return 64
            }
        }

        var iconSize: CGFloat {
            switch self {
            case .small: return 14
            case .medium: return 18
            case .large: return 24
            }
        }
    }

    var size: Size = .medium
    var isActive: Bool = false
    var activeColor: Color = Theme.Colors.action

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: size.iconSize, weight: .semibold))
            .foregroundColor(isActive ? .white : .primary)
            .frame(width: size.diameter, height: size.diameter)
            .background(
                Circle()
                    .fill(isActive ? activeColor : Color.white.opacity(0.1))
            )
            .scaleEffect(configuration.isPressed ? 0.96 : 1.0)
            .animation(.easeInOut(duration: 0.1), value: configuration.isPressed)
    }
}
