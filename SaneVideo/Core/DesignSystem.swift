//
//  DesignSystem.swift
//  SaneVideo
//
//  Created by SaneVideo Refactor
//

import SwiftUI
import SaneUI

private enum SaneVideoPalette {
    static let accent = Color(red: 0.22, green: 0.45, blue: 1.00)
    static let accentSoft = Color(red: 0.57, green: 0.76, blue: 1.00)
    static let accentDeep = Color(red: 0.10, green: 0.24, blue: 0.78)
    static let accentEdge = Color(red: 0.76, green: 0.90, blue: 1.00)
    static let ambientDeep = Color(red: 0.03, green: 0.08, blue: 0.24)
    static let ambientMid = Color(red: 0.07, green: 0.17, blue: 0.48)
    static let ambientGlow = Color(red: 0.12, green: 0.29, blue: 0.76)
}

enum Theme {

    // UNIFIED COLOR PALETTE - Professional Dark Mode optimized
    // Brand palette: SaneUI Navy + SaneBar-leaning blue
    // Action/Accent: blue-led, with only a small cool edge highlight
    enum Colors {
        // Semantic Application Colors (Adaptive)
        static let background = Color(nsColor: .windowBackgroundColor)
        static let secondaryBackground = Color(nsColor: .controlBackgroundColor)

        // BRAND COLORS (Local SaneVideo override)
        static let accent = SaneVideoPalette.accent
        static let accentSoft = SaneVideoPalette.accentSoft
        static let accentDeep = SaneVideoPalette.accentDeep
        static let accentEdge = SaneVideoPalette.accentEdge

        static let accentGradient = accent

        // SECONDARY (System Integrated)
        static let action = accent

        static let secondaryGradient = accentSoft

        // SEMANTIC COLORS (System Integrated)
        static let warning = Color.orange
        static let destructive = Color.red

        // Semantic Text (Adapts to Light/Dark mode)
        static let textPrimary = Color(nsColor: .labelColor)
        static let textSecondary = Color(nsColor: .secondaryLabelColor)
        static let textTertiary = Color(nsColor: .tertiaryLabelColor)

        // UI ELEMENT COLORS
        static let cardBackground = Color.white.opacity(0.05)
        static let border = Color.white.opacity(0.1)
        static let divider = Color.white.opacity(0.08)
        static let helperBackground = Color(nsColor: .controlBackgroundColor)
        static let helperTint = SaneVideoPalette.ambientGlow.opacity(0.30)
        static let helperTintStrong = accentDeep.opacity(0.46)
        static let accentGlow = accent.opacity(0.28)
        static let accentGlowStrong = accentSoft.opacity(0.40)
        static let ambientDeep = SaneVideoPalette.ambientDeep
        static let ambientMid = SaneVideoPalette.ambientMid
        static let editorBase = Color(red: 0.04, green: 0.06, blue: 0.13)
        static let editorPanel = Color(red: 0.06, green: 0.10, blue: 0.21)
        static let editorPanelElevated = Color(red: 0.08, green: 0.13, blue: 0.28)
        static let editorStroke = accentSoft.opacity(0.22)

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
        // Readability floor: body/supporting text should never feel cramped.
        static let fontSizeXS: CGFloat = 13
        static let fontSizeSM: CGFloat = 14
        static let fontSizeMD: CGFloat = 15
        static let fontSizeLG: CGFloat = 16
        static let fontSizeXL: CGFloat = 18
        static let fontSizeXXL: CGFloat = 22

        static let sectionTitle = Font.system(size: fontSizeLG, weight: .semibold)
        static let label = Font.system(size: fontSizeSM, weight: .semibold)
        static let body = Font.system(size: fontSizeMD)
        static let bodyStrong = Font.system(size: fontSizeMD, weight: .medium)
        static let support = Font.system(size: fontSizeSM)
        static let meta = Font.system(size: fontSizeSM, weight: .medium)
        static let metaMonospaced = Font.system(size: fontSizeSM, weight: .medium, design: .monospaced)
        static let badge = Font.system(size: fontSizeXS, weight: .semibold)

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

    static let navy = SanePalette.navy
    static let deepNavy = SanePalette.navyDeep
    static let glowingTeal = Theme.Colors.accent
    static let silver = Color(red: 0.72, green: 0.80, blue: 0.88)
    static let void = Color(hex: "0a0a0a")
    static let carbon = Color(hex: "141414")
    static let smoke = Color(hex: "222222")
    static let stone = Color(nsColor: .secondaryLabelColor)
    static let cloud = Color(nsColor: .labelColor)
    static let successGreen = Color(hex: "22c55e")
    static let warningOrange = Color(hex: "f59e0b")
    static let errorRed = Color(hex: "ef4444")
}

extension View {
    func saneReadableSectionTitle() -> some View {
        font(Theme.Typography.sectionTitle)
            .foregroundStyle(Theme.Colors.textPrimary)
    }

    func saneReadableLabel() -> some View {
        font(Theme.Typography.label)
            .foregroundStyle(Theme.Colors.textSecondary)
    }

    func saneReadableBody() -> some View {
        font(Theme.Typography.body)
            .foregroundStyle(Theme.Colors.textPrimary)
    }

    func saneReadableBodyStrong() -> some View {
        font(Theme.Typography.bodyStrong)
            .foregroundStyle(Theme.Colors.textPrimary)
    }

    func saneReadableSupportText() -> some View {
        font(Theme.Typography.support)
            .foregroundStyle(Theme.Colors.textSecondary)
    }

    func saneReadableMeta(monospaced: Bool = false) -> some View {
        font(monospaced ? Theme.Typography.metaMonospaced : Theme.Typography.meta)
            .foregroundStyle(Theme.Colors.textSecondary)
    }

    func sanePanel(radius: CGFloat = 14, emphasized: Bool = false, accent: Color? = nil) -> some View {
        modifier(SanePanelModifier(radius: radius, emphasized: emphasized, accent: accent))
    }
}

private struct SanePanelModifier: ViewModifier {
    let radius: CGFloat
    let emphasized: Bool
    let accent: Color?

    private var accentColor: Color {
        accent ?? Theme.Colors.accent
    }

    func body(content: Content) -> some View {
        content
            .background {
                ZStack {
                    RoundedRectangle(cornerRadius: radius, style: .continuous)
                        .fill(.ultraThinMaterial)

                    RoundedRectangle(cornerRadius: radius, style: .continuous)
                        .fill(
                            LinearGradient(
                                colors: [
                                    Theme.Colors.secondaryBackground.opacity(0.96),
                                    Theme.Colors.ambientDeep.opacity(emphasized ? 0.70 : 0.52),
                                    accentColor.opacity(emphasized ? 0.16 : 0.08)
                                ],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )

                    RoundedRectangle(cornerRadius: radius, style: .continuous)
                        .fill(
                            RadialGradient(
                                colors: [
                                    accentColor.opacity(emphasized ? 0.42 : 0.22),
                                    .clear
                                ],
                                center: .topLeading,
                                startRadius: 8,
                                endRadius: emphasized ? 250 : 160
                            )
                        )

                    RoundedRectangle(cornerRadius: radius, style: .continuous)
                        .fill(
                            LinearGradient(
                                colors: [
                                    Color.white.opacity(emphasized ? 0.10 : 0.06),
                                    .clear,
                                    Theme.Colors.accentEdge.opacity(emphasized ? 0.10 : 0.04)
                                ],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: radius, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: radius, style: .continuous)
                    .strokeBorder(
                        LinearGradient(
                            colors: [
                                Color.white.opacity(emphasized ? 0.24 : 0.14),
                                accentColor.opacity(emphasized ? 0.42 : 0.24),
                                Theme.Colors.accentEdge.opacity(emphasized ? 0.16 : 0.08)
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        lineWidth: emphasized ? 1.1 : 1
                    )
            }
            .shadow(
                color: accentColor.opacity(emphasized ? 0.22 : 0.10),
                radius: emphasized ? 22 : 12,
                x: 0,
                y: emphasized ? 12 : 7
            )
    }
}

struct FeatureCallout: View {
    enum Tone {
        case accent
        case info
        case success
        case warning

        var color: Color {
            switch self {
            case .accent:
                return Theme.Colors.accent
            case .info:
                return Theme.Colors.accentSoft
            case .success:
                return .green
            case .warning:
                return .orange
            }
        }
    }

    let title: String
    let message: String
    var icon: String = "sparkles"
    var tone: Tone = .accent

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            ZStack {
                Circle()
                    .fill(
                        LinearGradient(
                            colors: [tone.color.opacity(0.95), Theme.Colors.accentDeep.opacity(0.85)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )

                Image(systemName: icon)
                    .font(.system(size: Theme.Typography.iconSizeMD, weight: .semibold))
                    .foregroundStyle(.white)
            }
            .frame(width: 34, height: 34)

            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .saneReadableBodyStrong()
                Text(message)
                    .saneReadableSupportText()
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 0)
        }
        .padding(14)
        .sanePanel(radius: 16, emphasized: true, accent: tone.color)
    }
}

struct HelperText: View {
    let text: String
    var icon: String = "info.circle.fill"
    var color: Color = Theme.Colors.accent

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: icon)
                .font(.system(size: Theme.Typography.iconSizeSM, weight: .semibold))
                .foregroundStyle(color)
                .padding(.top, 1)

            Text(text)
                .saneReadableSupportText()
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct LabeledToggleRow: View {
    let title: String
    let message: String
    @Binding var isOn: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Toggle(title, isOn: $isOn)
                .help(message)
            HelperText(text: message, icon: "questionmark.circle.fill")
        }
    }
}

struct FeatureBadge: View {
    let label: String
    var icon: String
    var accent: Color = Theme.Colors.accent

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: icon)
                .font(.system(size: Theme.Typography.iconSizeXS, weight: .semibold))
            Text(label)
                .font(Theme.Typography.badge)
        }
        .foregroundStyle(Theme.Colors.textPrimary)
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(
            Capsule()
                .fill(accent.opacity(0.14))
        )
        .overlay(
            Capsule()
                .stroke(accent.opacity(0.32), lineWidth: 1)
        )
    }
}

struct SaneVideoAmbientBackground: View {
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        ZStack {
            SaneGradientBackground()

            LinearGradient(
                colors: [
                    Color.deepNavy.opacity(colorScheme == .dark ? 0.82 : 0.08),
                    Theme.Colors.ambientDeep.opacity(colorScheme == .dark ? 0.74 : 0.04),
                    Theme.Colors.ambientMid.opacity(colorScheme == .dark ? 0.62 : 0.02)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )

            LinearGradient(
                colors: colorScheme == .dark
                    ? [
                        Color.deepNavy.opacity(0.52),
                        Theme.Colors.ambientDeep.opacity(0.60),
                        Theme.Colors.ambientMid.opacity(0.46)
                    ]
                    : [
                        Theme.Colors.accentSoft.opacity(0.10),
                        Theme.Colors.accent.opacity(0.06),
                        Color.white.opacity(0.0)
                    ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )

            RadialGradient(
                colors: [
                    Theme.Colors.accentGlowStrong.opacity(colorScheme == .dark ? 0.98 : 0.45),
                    Theme.Colors.accent.opacity(colorScheme == .dark ? 0.16 : 0.08),
                    .clear
                ],
                center: .topTrailing,
                startRadius: 18,
                endRadius: 520
            )

            RadialGradient(
                colors: [
                    Theme.Colors.ambientMid.opacity(colorScheme == .dark ? 0.42 : 0.12),
                    .clear
                ],
                center: .center,
                startRadius: 48,
                endRadius: 640
            )

            RadialGradient(
                colors: [
                    Theme.Colors.accentEdge.opacity(colorScheme == .dark ? 0.12 : 0.06),
                    .clear
                ],
                center: .bottomLeading,
                startRadius: 24,
                endRadius: 300
            )
        }
        .ignoresSafeArea()
    }
}

struct SaneVideoEditorChromeBackground: View {
    var body: some View {
        LinearGradient(
            colors: [
                Theme.Colors.editorBase,
                Theme.Colors.editorPanel
            ],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }
}

struct SaneVideoEditorPanelBackground: View {
    var emphasized: Bool = false

    var body: some View {
        LinearGradient(
            colors: emphasized
                ? [
                    Theme.Colors.editorPanelElevated,
                    Theme.Colors.editorPanel
                ]
                : [
                    Theme.Colors.editorPanel,
                    Theme.Colors.editorBase
                ],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }
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
