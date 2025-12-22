//
//  LiquidGlassStyle.swift
//  SaneVideo
//
//  Created by SaneVideo Refactor
//

import SwiftUI

/// A view modifier that applies the macOS Tahoe "Liquid Glass" aesthetic.
struct LiquidGlassModifier: ViewModifier {
    var radius: CGFloat = 12
    var opacity: Double = 0.5
    
    func body(content: Content) -> some View {
        content
            .background(
                ZStack {
                    // HUD Material for the "glass" base
                    VisualEffectView(material: .hudWindow, blendingMode: .withinWindow)
                        .opacity(0.8)
                    
                    // Subtle edge light gradient
                    RoundedRectangle(cornerRadius: radius)
                        .stroke(
                            LinearGradient(
                                colors: [.white.opacity(0.15), .clear, .white.opacity(0.05)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            ),
                            lineWidth: 0.5
                        )
                }
            )
            .clipShape(RoundedRectangle(cornerRadius: radius))
            .shadow(color: .black.opacity(0.1), radius: 10, x: 0, y: 5)
    }
}

extension View {
    /// Applies the SaneVideo Tahoe-style Liquid Glass effect.
    func liquidGlass(radius: CGFloat = 12, opacity: Double = 0.5) -> some View {
        self.modifier(LiquidGlassModifier(radius: radius, opacity: opacity))
    }
}

/// A wrapper for NSVisualEffectView to enable advanced material controls in SwiftUI.
struct VisualEffectView: NSViewRepresentable {
    var material: NSVisualEffectView.Material
    var blendingMode: NSVisualEffectView.BlendingMode
    var state: NSVisualEffectView.State = .followsWindowActiveState

    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = material
        view.blendingMode = blendingMode
        view.state = state
        return view
    }

    func updateNSView(_ nsView: NSVisualEffectView, context: Context) {
        nsView.material = material
        nsView.blendingMode = blendingMode
        nsView.state = state
    }
}
