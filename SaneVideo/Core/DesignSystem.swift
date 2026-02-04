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
        static let accent = Color.videoPurple

        static let accentGradient = Color.videoPurple // Effectively 1:1 with system for snappiness

        // SECONDARY (System Integrated)
        static let action = Color.accentColor

        static let secondaryGradient = Color.accentColor

        // SEMANTIC COLORS (System Integrated)
        static let warning = Color.orange
        static let destructive = Color.red

        // Semantic Text (Adapts to Light/Dark mode)
        static let textPrimary = Color.cloud
        static let textSecondary = Color.stone

        // UI ELEMENT COLORS
        static let cardBackground = Color.white.opacity(0.05)
        static let border = Color.white.opacity(0.1)
        static let divider = Color.white.opacity(0.08)

    }

    enum Dimensions {
        // Corner Radius
        static let cornerRadius: CGFloat = 8
        static let smallCornerRadius: CGFloat = 4
        static let largeCornerRadius: CGFloat = 12

        // Spacing System (8pt grid)
        static let spacingXS: CGFloat = 4
        static let spacingSM: CGFloat = 8
        static let spacingMD: CGFloat = 12
        static let spacingLG: CGFloat = 16
        static let spacingXL: CGFloat = 20
        static let spacingXXL: CGFloat = 24

        // Padding System
        static let paddingXS: CGFloat = 4
        static let paddingSM: CGFloat = 8
        static let paddingMD: CGFloat = 12
        static let paddingLG: CGFloat = 16
        static let paddingXL: CGFloat = 20

        // Legacy (for backward compatibility)
        static let padding: CGFloat = 12
    }

    enum Typography {
        // Font Sizes (consistent scale)
        static let fontSizeXS: CGFloat = 12
        static let fontSizeSM: CGFloat = 12
        static let fontSizeMD: CGFloat = 13
        static let fontSizeLG: CGFloat = 15
        static let fontSizeXL: CGFloat = 17
        static let fontSizeXXL: CGFloat = 20

        // Icon Sizes
        static let iconSizeXS: CGFloat = 12
        static let iconSizeSM: CGFloat = 14
        static let iconSizeMD: CGFloat = 16
        static let iconSizeLG: CGFloat = 18
        static let iconSizeXL: CGFloat = 24
    }

    enum Opacity {
        // Consistent opacity values
        static let subtle: Double = 0.05
        static let light: Double = 0.1
        static let medium: Double = 0.2
        static let strong: Double = 0.3
        static let heavy: Double = 0.5
        static let textSecondary: Double = 0.7
        static let textTertiary: Double = 0.8
    }
}

// Helper for Hex Colors
extension NSColor {
    convenience init?(hex: String) {
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
            return nil
        }

        self.init(
            srgbRed: CGFloat(r) / 255,
            green: CGFloat(g) / 255,
            blue: CGFloat(b) / 255,
            alpha: CGFloat(a) / 255
        )
    }
}

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

    static let videoPurple = Color(hex: "a855f7")
    static let navy = Color(hex: "1a2744")
    static let deepNavy = Color(hex: "0d1525")
    static let glowingTeal = Color(hex: "5fa8d3")
    static let silver = Color(hex: "a8b4c4")
    static let void = Color(hex: "0a0a0a")
    static let carbon = Color(hex: "141414")
    static let smoke = Color(hex: "222222")
    static let stone = Color(hex: "888888")
    static let cloud = Color(hex: "e5e5e5")
    static let successGreen = Color(hex: "22c55e")
    static let warningOrange = Color(hex: "f59e0b")
    static let errorRed = Color(hex: "ef4444")
}

// Reusable Button Styles (Active)

// MARK: - Icon Button Style (Circular)

/// A circular button style for icon-only actions (Recording, Timeline toolbar)
struct IconButtonStyle: ButtonStyle {
    enum Size {
        case small, medium, large
        case custom(CGFloat)

        var diameter: CGFloat {
            switch self {
            case .small: return 36
            case .medium: return 48
            case .large: return 64
            case .custom(let val): return val
            }
        }

        var iconSize: CGFloat {
            switch self {
            case .small: return 14
            case .medium: return 18
            case .large: return 24
            case .custom(let val): return val * 0.4
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
