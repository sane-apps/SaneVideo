import SwiftUI

// MARK: - Collapsible Section Component

/// Flat inspector section: a header row and its content, separated from the next by a hairline.
struct CollapsibleSection<Content: View>: View {
    let title: String
    let icon: String
    @Binding var isExpanded: Bool
    var badge: String?
    var isPrimary: Bool = false
    @ViewBuilder let content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Button {
                withAnimation(.easeInOut(duration: 0.2)) { isExpanded.toggle() }
            } label: {
                HStack(spacing: 10) {
                    Image(systemName: icon)
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(isExpanded || isPrimary ? Theme.Colors.accent : Theme.Colors.textPrimary)
                        .frame(width: 20)
                    Text(title)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(Theme.Colors.textPrimary)
                    if let badge {
                        Text(badge)
                            .font(.system(size: 13, weight: .medium))
                            .foregroundStyle(Theme.Colors.accent)
                    }
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(Theme.Colors.textPrimary.opacity(0.7))
                        .rotationEffect(.degrees(isExpanded ? 90 : 0))
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("\(title)SectionButton")
            .accessibilityLabel("\(title) section")
            .accessibilityHint(isExpanded ? "Collapse \(title) section" : "Expand \(title) section")
            .accessibilityValue(isExpanded ? "Expanded" : "Collapsed")

            if isExpanded {
                content()
                    .padding(.horizontal, 16)
                    .padding(.bottom, 16)
                    .transition(.opacity)
            }

            Rectangle()
                .fill(Theme.Colors.divider)
                .frame(height: 1)
        }
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
        .help(isLoading ? "Operation in progress..." : subtitle)
        .accessibilityIdentifier(id)
        .accessibilityLabel(title)
        .accessibilityHint(subtitle)
        .accessibilityValue(isLoading ? "Loading" : "")
        // No .focusable(): it draws a yellow focus ring.
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
        // No .focusable(): it draws a yellow focus ring.
        .smoothAppear()
    }
}

// MARK: - Inspector Header

struct InspectorHeader: View {
    var body: some View {
        HStack {
            Text(String(localized: "inspector.header.title", defaultValue: "Edit"))
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(Theme.Colors.textPrimary)

            Spacer()

            PrivacyBadge()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .accessibilityLabel("Inspector panel")
        .accessibilityHint("View and edit properties of the selected clip")
    }
}

// MARK: - Empty Selection View

struct EmptySelectionView: View {
    var body: some View {
        VStack(spacing: 10) {
            Image(systemName: "rectangle.on.rectangle")
                .font(.system(size: 28))
                .foregroundStyle(Theme.Colors.textPrimary.opacity(0.6))
            Text("Select a clip")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(Theme.Colors.textPrimary)
            Text("Click a clip in the timeline to clean it up, add captions or change its look.")
                .font(.system(size: 13))
                .foregroundStyle(Theme.Colors.textPrimary.opacity(0.85))
                .multilineTextAlignment(.center)
        }
        .padding(24)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
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
