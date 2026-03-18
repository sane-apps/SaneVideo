//
//  FeatureDiscovery.swift
//  SaneVideo
//
//  Feature discovery system for first-time users
//

import Combine
import Foundation
import SwiftUI

/// Manages feature discovery tooltips and first-use hints
@MainActor
@Observable
class FeatureDiscovery {

    var shownTooltips: Set<String> = []

    init() {
        loadShownTooltips()
    }

    /// Check if a tooltip should be shown (first time only)
    func shouldShowTooltip(for feature: String) -> Bool {
        !shownTooltips.contains(feature)
    }

    /// Mark a tooltip as shown
    func markTooltipShown(for feature: String) {
        shownTooltips.insert(feature)
        saveShownTooltips()
    }

    /// Reset all tooltips (for testing or re-onboarding)
    func resetAllTooltips() {
        shownTooltips.removeAll()
        saveShownTooltips()
    }

    private func loadShownTooltips() {
        if let data = UserDefaults.standard.data(forKey: "shownTooltips"),
           let tooltips = try? JSONDecoder().decode(Set<String>.self, from: data) {
            shownTooltips = tooltips
        }
    }

    private func saveShownTooltips() {
        if let data = try? JSONEncoder().encode(shownTooltips) {
            UserDefaults.standard.set(data, forKey: "shownTooltips")
        }
    }
}

/// View modifier for showing contextual tooltips on first use
struct FeatureTooltip: ViewModifier {
    let feature: String
    let message: String
    @State private var discovery = ServiceContainer.shared.featureDiscovery
    @State private var showTooltip = false

    func body(content: Content) -> some View {
        content
            .overlay(alignment: .topTrailing) {
                if showTooltip {
                    TooltipView(message: message) {
                        discovery.markTooltipShown(for: feature)
                        withAnimation {
                            showTooltip = false
                        }
                    }
                    .offset(x: 0, y: -40)
                    .transition(.scale.combined(with: .opacity))
                }
            }
            .onAppear {
                if discovery.shouldShowTooltip(for: feature) {
                    // Delay to avoid showing immediately
                    DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                        withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                            showTooltip = true
                        }
                    }
                }
            }
    }
}

struct TooltipView: View {
    let message: String
    let onDismiss: () -> Void
    @State private var isVisible = true

    var body: some View {
        HStack(spacing: 8) {
            Text(message)
                .saneReadableSupportText()
                .fixedSize(horizontal: true, vertical: false) // Prevent truncation in small parents
                .multilineTextAlignment(.leading)

            Button(action: {
                withAnimation {
                    isVisible = false
                }
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                    onDismiss()
                }
            }, label: {
                Image(systemName: "xmark.circle.fill")
                    .foregroundStyle(Theme.Colors.textSecondary)
            })
            .buttonStyle(.plain)
            .accessibilityIdentifier("tooltip.action.dismiss")
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .sanePanel(radius: 10, emphasized: true, accent: Theme.Colors.accentSoft)
        .opacity(isVisible ? 1 : 0)
    }
}

extension View {
    /// Show a tooltip on first use of a feature
    func featureTooltip(_ feature: String, message: String) -> some View {
        modifier(FeatureTooltip(feature: feature, message: message))
    }
}
