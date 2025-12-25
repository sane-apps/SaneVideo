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
                HStack {
                    Image(systemName: icon)
                        .font(.system(size: isPrimary ? 14 : 12, weight: isPrimary ? .bold : .regular))
                        .foregroundColor(isPrimary ? Theme.Colors.accent : .secondary)
                        .frame(width: 20)
                    Text(title)
                        .font(.system(size: isPrimary ? 13 : 12, weight: isPrimary ? .bold : .semibold))
                        .foregroundColor(.primary)

                    // Badge (shows count when applicable)
                    if let badge = badge {
                        Text(badge)
                            .font(.system(size: 9, weight: .bold))
                            .foregroundColor(.white)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Capsule().fill(Theme.Colors.accent))
                    }

                    Spacer()
                    Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundColor(.secondary)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, isPrimary ? 12 : 10)
                .background(isPrimary ? Theme.Colors.accent.opacity(0.05) : Color.secondary.opacity(0.05))
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
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .transition(.smoothScale)
                    // P0 FIX: Focus management for keyboard navigation
                    .focusable()
            }
        }
    }
}

// MARK: - Subsection Header

struct SubsectionHeader: View {
    let title: String

    var body: some View {
        Text(title.uppercased())
            .font(.system(size: 10, weight: .semibold))
            .foregroundColor(.secondary)
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
            HStack(spacing: 8) {
                Image(systemName: icon)
                    .font(.system(size: 12))
                    .foregroundColor(color)
                    .frame(width: 20)

                VStack(alignment: .leading, spacing: 1) {
                    Text(title)
                        .font(.caption.bold())
                        .foregroundColor(.primary)
                    Text(subtitle)
                        .font(.system(size: 9))
                        .foregroundColor(.secondary)
                }

                Spacer()

                if isLoading {
                    ProgressView().scaleEffect(0.6)
                } else {
                    Image(systemName: "chevron.right")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
            }
            .padding(8)
            .background(color.opacity(0.1))
            .cornerRadius(6)
            .overlay(
                RoundedRectangle(cornerRadius: 6)
                    .stroke(color.opacity(0.3), lineWidth: 1)
            )
        })
        .buttonStyle(.plain)
        .hoverScale(1.02)
        .pressScale()
        .disabled(isLoading)
        // P0 FIX: Enhanced accessibility
        .accessibilityIdentifier(id)
        .accessibilityLabel(title)
        .accessibilityHint(subtitle)
        .accessibilityValue(isLoading ? "Loading" : "")
        // P0 FIX: Keyboard navigation
        .focusable()
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
            HStack(spacing: 10) {
                Image(systemName: icon)
                    .font(.system(size: 14))
                    .foregroundColor(color)
                    .frame(width: 24)

                VStack(alignment: .leading, spacing: 1) {
                    Text(title)
                        .font(.caption.bold())
                        .foregroundColor(.primary)
                    Text(subtitle)
                        .font(.system(size: 9))
                        .foregroundColor(.secondary)
                }

                Spacer()

                Image(systemName: "chevron.right")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .background(color.opacity(0.1))
            .cornerRadius(8)
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(color.opacity(0.3), lineWidth: 1)
            )
        })
        .buttonStyle(.plain)
        .hoverScale(1.02)
        .pressScale()
        .accessibilityIdentifier(id)
        .smoothAppear()
    }
}

// MARK: - Inspector Header

struct InspectorHeader: View {
    var body: some View {
        Text(String(localized: "inspector.header.title", defaultValue: "Inspector"))
            .font(.system(.headline, design: .rounded))
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
                .foregroundColor(.secondary.opacity(0.3))
            
            VStack(spacing: 12) {
                Text("Nothing Selected")
                    .font(.system(size: 14, weight: .bold))
                
                Text("Select a clip in the timeline\nto view and edit properties.")
                    .font(.system(size: 12))
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
                    .lineSpacing(4)
                
                // CRITICAL FIX: Add actionable hints
                VStack(spacing: 6) {
                    HStack(spacing: 4) {
                        Image(systemName: "hand.point.up.left.fill")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                        Text("Click a clip in the timeline")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    }
                    
                    HStack(spacing: 4) {
                        Image(systemName: "keyboard")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                        Text("Or use Cmd+Click to select")
                            .font(.caption2)
                            .foregroundColor(.secondary)
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
                .foregroundColor(.secondary)
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
