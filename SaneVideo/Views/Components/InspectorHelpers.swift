//
//  InspectorHelpers.swift
//  SaneVideo
//
//  Extracted from StylesInspectorView.swift
//  Contains generic, reusable inspector components
//

import SwiftUI

// MARK: - Collapsible Section Component

struct CollapsibleSection<Content: View>: View {
    let title: String
    let icon: String
    @Binding var isExpanded: Bool
    var badge: String? // Optional badge (e.g., caption count)
    var isPrimary: Bool = false // P1 FIX: Mark primary sections
    @ViewBuilder let content: () -> Content

    private var accentColor: Color {
        isPrimary ? Theme.Colors.accent : Theme.Colors.accentSoft
    }

    var body: some View {
        VStack(spacing: 0) {
            Button(action: {
                withAnimation(.easeInOut(duration: 0.2)) {
                    isExpanded.toggle()
                }
            }, label: {
                HStack(spacing: Theme.Dimensions.spacingSM) {
                    Image(systemName: icon)
                        .font(.system(size: isPrimary ? Theme.Typography.iconSizeSM : Theme.Typography.iconSizeXS, weight: isPrimary ? .bold : .semibold))
                        .foregroundStyle(isExpanded ? accentColor : Theme.Colors.textSecondary)
                        .frame(width: isPrimary ? 22 : 20)
                    Text(title)
                        .font(.system(size: isPrimary ? Theme.Typography.fontSizeMD : Theme.Typography.fontSizeSM, weight: .semibold))
                        .foregroundStyle(Theme.Colors.textPrimary)

                    if let badge = badge {
                        Text(badge)
                            .font(.system(size: Theme.Typography.fontSizeXS, weight: .bold))
                            .foregroundColor(.white)
                            .padding(.horizontal, Theme.Dimensions.spacingSM)
                            .padding(.vertical, Theme.Dimensions.spacingXS)
                            .background(
                                Capsule()
                                    .fill(
                                        LinearGradient(
                                            colors: [accentColor, Theme.Colors.accentDeep],
                                            startPoint: .topLeading,
                                            endPoint: .bottomTrailing
                                        )
                                    )
                            )
                    }

                    Spacer()
                    Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                        .font(.system(size: Theme.Typography.fontSizeXS, weight: .semibold))
                        .foregroundStyle(isExpanded ? accentColor : Theme.Colors.textSecondary)
                }
                .padding(.horizontal, Theme.Dimensions.paddingMD)
                .padding(.vertical, isPrimary ? Theme.Dimensions.paddingMD : Theme.Dimensions.paddingSM)
                .background(
                    LinearGradient(
                        colors: [
                            accentColor.opacity(isExpanded ? 0.18 : 0.08),
                            Color.white.opacity(isExpanded ? 0.04 : 0.015)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
            })
            .buttonStyle(.plain)
            .accessibilityIdentifier("\(title)SectionButton")
            .accessibilityLabel("\(title) section")
            .accessibilityHint(isExpanded ? "Collapse \(title) section" : "Expand \(title) section")
            .accessibilityValue(isExpanded ? "Expanded" : "Collapsed")
            .keyboardShortcut(.defaultAction) // Space/Enter to toggle

            if isExpanded {
                Divider()
                    .overlay(accentColor.opacity(0.18))
                    .padding(.horizontal, Theme.Dimensions.paddingMD)

                content()
                    .padding(.horizontal, Theme.Dimensions.paddingMD)
                    .padding(.vertical, Theme.Dimensions.paddingMD)
                    .transition(.smoothScale)
            }
        }
        .sanePanel(radius: 16, emphasized: isExpanded, accent: accentColor)
    }
}

// MARK: - Subsection Header

struct SubsectionHeader: View {
    let title: String

    var body: some View {
        Text(title.uppercased())
            .font(.system(size: Theme.Typography.fontSizeXS, weight: .bold))
            .foregroundStyle(Theme.Colors.accentSoft)
            .tracking(0.8)
    }
}

// MARK: - Smart Tool Button

struct SmartToolButton: View {
    let title: String
    let subtitle: String
    let icon: String
    let color: Color
    let isLoading: Bool
    let id: String
    let action: () -> Void

    var body: some View {
        Button(action: action, label: {
            HStack(spacing: Theme.Dimensions.spacingSM) {
                Image(systemName: icon)
                    .font(.system(size: Theme.Typography.iconSizeXS))
                    .foregroundColor(color)
                    .frame(width: 20)

                VStack(alignment: .leading, spacing: Theme.Dimensions.spacingXS) {
                    Text(title)
                        .font(.system(size: Theme.Typography.fontSizeSM, weight: .bold))
                        .foregroundColor(.primary)
                    Text(subtitle)
                        .font(.system(size: Theme.Typography.fontSizeXS))
                        .foregroundColor(Color.stone)
                }

                Spacer()

                if isLoading {
                    ProgressView().scaleEffect(0.6)
                } else {
                    Image(systemName: "chevron.right")
                        .font(.system(size: Theme.Typography.fontSizeXS))
                        .foregroundStyle(.tertiary)
                }
            }
            .padding(Theme.Dimensions.paddingSM)
            .background(color.opacity(Theme.Opacity.light))
            .cornerRadius(Theme.Dimensions.smallCornerRadius)
            .overlay(
                RoundedRectangle(cornerRadius: Theme.Dimensions.smallCornerRadius)
                    .stroke(color.opacity(Theme.Opacity.strong), lineWidth: 1)
            )
        })
        .buttonStyle(.plain)
        .hoverScale(1.02)
        .pressScale()
        .disabled(isLoading)
        .help(isLoading ? "Operation in progress..." : subtitle) // CRITICAL FIX: Help text for disabled state
        // P0 FIX: Enhanced accessibility
        .accessibilityIdentifier(id)
        .accessibilityLabel(title)
        .accessibilityHint(subtitle)
        .accessibilityValue(isLoading ? "Loading" : "")
        // REMOVED: .focusable() - was causing yellow focus ring
        .smoothAppear()
    }
}

// MARK: - AI Tool Button

struct AIToolButton: View {
    let title: String
    let subtitle: String
    let icon: String
    let color: Color
    let id: String
    let action: () -> Void

    var body: some View {
        Button(action: action, label: {
            HStack(spacing: Theme.Dimensions.spacingMD) {
                Image(systemName: icon)
                    .font(.system(size: Theme.Typography.iconSizeSM))
                    .foregroundColor(color)
                    .frame(width: 24)

                VStack(alignment: .leading, spacing: Theme.Dimensions.spacingXS) {
                    Text(title)
                        .font(.system(size: Theme.Typography.fontSizeSM, weight: .bold))
                        .foregroundColor(.primary)
                    Text(subtitle)
                        .font(.system(size: Theme.Typography.fontSizeXS))
                        .foregroundColor(Color.stone)
                }

                Spacer()

                Image(systemName: "chevron.right")
                    .font(.system(size: Theme.Typography.fontSizeXS))
                    .foregroundStyle(.tertiary)
            }
            .padding(.horizontal, Theme.Dimensions.paddingMD)
            .padding(.vertical, Theme.Dimensions.paddingSM)
            .background(color.opacity(Theme.Opacity.light))
            .cornerRadius(Theme.Dimensions.cornerRadius)
            .overlay(
                RoundedRectangle(cornerRadius: Theme.Dimensions.cornerRadius)
                    .stroke(color.opacity(Theme.Opacity.strong), lineWidth: 1)
            )
        })
        .buttonStyle(.plain)
        .hoverScale(1.02)
        .pressScale()
        .accessibilityIdentifier(id)
        .accessibilityLabel(title)
        .accessibilityHint(subtitle)
        // REMOVED: .focusable() - was causing yellow focus ring
        .smoothAppear()
    }
}

// MARK: - Inspector Header

struct InspectorHeader: View {
    var body: some View {
        HStack {
            Text(String(localized: "inspector.header.title", defaultValue: "Inspector"))
                .font(.system(.headline, design: .rounded))
                .foregroundStyle(Theme.Colors.textPrimary)

            Spacer()

            PrivacyBadge()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .background(
            LinearGradient(
                colors: [
                    Theme.Colors.ambientDeep.opacity(0.68),
                    Theme.Colors.accentDeep.opacity(0.24),
                    .clear
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        )
        .accessibilityLabel("Inspector panel")
        .accessibilityHint("View and edit properties of the selected clip")
    }
}

// MARK: - Empty Selection View

struct EmptySelectionView: View {
    var body: some View {
        VStack(spacing: 20) {
            Spacer().frame(height: 60)
            
            Image(systemName: "selection.pin.in.out")
                .font(.system(size: 40))
                .foregroundStyle(Theme.Colors.accentSoft.opacity(0.55))
            
            VStack(spacing: 12) {
                Text("Nothing Selected")
                    .saneReadableBodyStrong()
                
                Text("Select a clip in the timeline\nto view and edit properties.")
                    .saneReadableSupportText()
                    .multilineTextAlignment(.center)
                    .lineSpacing(4)
                
                VStack(spacing: 6) {
                    HStack(spacing: 4) {
                        Image(systemName: "hand.point.up.left.fill")
                            .font(.caption2)
                            .foregroundStyle(Theme.Colors.textSecondary)
                        Text("Click a clip in the timeline")
                            .saneReadableSupportText()
                    }
                    
                    HStack(spacing: 4) {
                        Image(systemName: "keyboard")
                            .font(.caption2)
                            .foregroundStyle(Theme.Colors.textSecondary)
                        Text("Or use Cmd+Click to select")
                            .saneReadableSupportText()
                    }
                }
                .padding(.top, 8)
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 16)
            .sanePanel(radius: 18, accent: Theme.Colors.accentSoft)
            
            Spacer()
        }
    }
}

// MARK: - Info Row

struct InfoRow: View {
    let label: String
    let value: String

    var body: some View {
        HStack {
            Text(label)
                .saneReadableSupportText()
            Spacer()
            Text(value)
                .saneReadableMeta()
                .lineLimit(1)
                .truncationMode(.middle)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(label): \(value)")
    }
}
