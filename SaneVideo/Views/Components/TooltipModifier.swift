//
//  TooltipModifier.swift
//  SaneVideo
//
//  Created by SaneVideo Refactor
//

import SwiftUI

struct TooltipData {
    let text: String
    let anchor: Anchor<CGRect>
}

struct TooltipPreferenceKey: PreferenceKey {
    static let defaultValue: TooltipData? = nil

    static func reduce(value: inout TooltipData?, nextValue: () -> TooltipData?) {
        value = nextValue() ?? value
    }
}

struct InstantTooltipModifier: ViewModifier {
    let text: String
    @State private var isHovering = false

    func body(content: Content) -> some View {
        content
            .onHover { hovering in
                isHovering = hovering
            }
            .anchorPreference(key: TooltipPreferenceKey.self, value: .bounds) { anchor in
                if isHovering {
                    return TooltipData(text: text, anchor: anchor)
                }
                return nil
            }
    }
}

extension View {
    func instantTooltip(_ text: String) -> some View {
        modifier(InstantTooltipModifier(text: text))
    }

    /// Apply this to the root view to render tooltips
    func tooltipOverlay() -> some View {
        overlayPreferenceValue(TooltipPreferenceKey.self) { value in
            if let tooltip = value {
                GeometryReader { geometry in
                    let rect = geometry[tooltip.anchor]

                    Text(tooltip.text)
                        .font(.caption)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(.ultraThinMaterial)
                        .background(Color.black.opacity(0.8))
                        .foregroundColor(.white)
                        .cornerRadius(4)
                        .fixedSize()
                        .shadow(radius: 2)
                        .allowsHitTesting(false)
                        // Position above the anchor
                        // We center horizontally (rect.midX) and place above (rect.minY - 10)
                        .position(x: rect.midX, y: rect.minY - 20)
                        .zIndex(1000)
                }
            }
        }
    }
}
