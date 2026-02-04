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

    var body: some View {
        VStack(spacing: 0) {
            // P1 FIX: Enhanced header with visual hierarchy
            Button(action: {
                withAnimation(.easeInOut(duration: 0.2)) {
                    isExpanded.toggle()
                }
            }, label: {
                HStack(spacing: Theme.Dimensions.spacingSM) {
                    Image(systemName: icon)
                        .font(.system(size: isPrimary ? Theme.Typography.iconSizeSM : Theme.Typography.iconSizeXS, weight: isPrimary ? .bold : .regular))
                        .foregroundColor(isPrimary ? Theme.Colors.accent : Color.stone)
                        .frame(width: isPrimary ? 22 : 20)
                    Text(title)
                        .font(.system(size: isPrimary ? Theme.Typography.fontSizeMD : Theme.Typography.fontSizeSM, weight: isPrimary ? .bold : .semibold))
                        .foregroundColor(.primary)

                    // Badge (shows count when applicable)
                    if let badge = badge {
                        Text(badge)
                            .font(.system(size: Theme.Typography.fontSizeXS, weight: .bold))
                            .foregroundColor(.white)
                            .padding(.horizontal, Theme.Dimensions.spacingSM)
                            .padding(.vertical, Theme.Dimensions.spacingXS)
                            .background(Capsule().fill(Theme.Colors.accent))
                    }

                    Spacer()
                    Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                        .font(.system(size: Theme.Typography.fontSizeXS, weight: .semibold))
                        .foregroundColor(Color.stone)
                }
                .padding(.horizontal, Theme.Dimensions.paddingMD)
                .padding(.vertical, isPrimary ? Theme.Dimensions.paddingMD : Theme.Dimensions.paddingSM)
                .background(isPrimary ? Theme.Colors.accent.opacity(Theme.Opacity.subtle) : Color.stone.opacity(Theme.Opacity.subtle))
            })
            .buttonStyle(.plain)
            // P0 FIX: Enhanced accessibility
            .accessibilityIdentifier("\(title)SectionButton")
            .accessibilityLabel("\(title) section")
            .accessibilityHint(isExpanded ? "Collapse \(title) section" : "Expand \(title) section")
            .accessibilityValue(isExpanded ? "Expanded" : "Collapsed")
            // P0 FIX: Keyboard navigation support
            .keyboardShortcut(.defaultAction) // Space/Enter to toggle

            // Content (collapsible)
            if isExpanded {
                content()
                    .padding(.horizontal, Theme.Dimensions.paddingMD)
                    .padding(.vertical, Theme.Dimensions.paddingSM)
                    .transition(.smoothScale)
                    // REMOVED: .focusable() - was causing yellow focus ring on Inspector panel
            }
        }
    }
}

// MARK: - Subsection Header

struct SubsectionHeader: View {
    let title: String

    var body: some View {
        Text(title.uppercased())
            .font(.system(size: Theme.Typography.fontSizeXS, weight: .semibold))
            .foregroundColor(Color.stone)
            .tracking(0.5)
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

            Spacer()

            // MOVED HERE: Privacy badge always visible at top of inspector
            PrivacyBadge()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .background(.ultraThinMaterial)
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
                .foregroundColor(Color.stone.opacity(0.3))
            
            VStack(spacing: 12) {
                Text("Nothing Selected")
                    .font(.system(size: 14, weight: .bold))
                
                Text("Select a clip in the timeline\nto view and edit properties.")
                    .font(.system(size: 12))
                    .foregroundColor(Color.stone)
                    .multilineTextAlignment(.center)
                    .lineSpacing(4)
                
                // CRITICAL FIX: Add actionable hints
                VStack(spacing: 6) {
                    HStack(spacing: 4) {
                        Image(systemName: "hand.point.up.left.fill")
                            .font(.caption2)
                            .foregroundColor(Color.stone)
                        Text("Click a clip in the timeline")
                            .font(.caption2)
                            .foregroundColor(Color.stone)
                    }
                    
                    HStack(spacing: 4) {
                        Image(systemName: "keyboard")
                            .font(.caption2)
                            .foregroundColor(Color.stone)
                        Text("Or use Cmd+Click to select")
                            .font(.caption2)
                            .foregroundColor(Color.stone)
                    }
                }
                .padding(.top, 8)
            }
            .padding(.horizontal, 20)
            
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
                .foregroundColor(Color.stone)
            Spacer()
            Text(value)
                .font(.caption)
                .lineLimit(1)
                .truncationMode(.middle)
        }
        .font(.caption)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(label): \(value)")
    }
}
