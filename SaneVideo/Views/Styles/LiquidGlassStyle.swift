//
//  LiquidGlassStyle.swift
//  SaneVideo
//
//  Created by SaneVideo Refactor
//

import SwiftUI

/// A view modifier that applies the macOS Tahoe "Liquid Glass" aesthetic.
/// Enhanced with premium edge lighting and depth shadows.
struct LiquidGlassModifier: ViewModifier {
    var radius: CGFloat = 12
    var opacity: Double = 0.5
    var intensity: GlassIntensity = .standard
    
    enum GlassIntensity {
        case subtle      // For backgrounds
        case standard    // Default
        case premium     // For important cards/overlays
    }
    
    func body(content: Content) -> some View {
        content
            .background(
                ZStack {
                    // HUD Material for the "glass" base
                    VisualEffectView(material: .hudWindow, blendingMode: .withinWindow)
                        .opacity(intensity == .premium ? 0.95 : 0.8)
                    
                    // Enhanced edge light gradient with multiple stops
                    RoundedRectangle(cornerRadius: radius)
                        .stroke(
                            LinearGradient(
                                colors: edgeColors,
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            ),
                            lineWidth: edgeWidth
                        )
                    
                    // Additional subtle inner glow for premium
                    if intensity == .premium {
                        RoundedRectangle(cornerRadius: radius)
                            .stroke(
                                LinearGradient(
                                    colors: [
                                        .white.opacity(0.1),
                                        .clear
                                    ],
                                    startPoint: .top,
                                    endPoint: .center
                                ),
                                lineWidth: 0.5
                            )
                            .padding(1)
                    }
                }
            )
            .clipShape(RoundedRectangle(cornerRadius: radius))
            .shadow(color: .black.opacity(shadowOpacity), radius: shadowRadius, x: 0, y: shadowY)
            .shadow(color: .white.opacity(0.05), radius: 5, x: 0, y: -2) // Subtle top highlight
    }
    
    private var edgeColors: [Color] {
        switch intensity {
        case .subtle:
            return [.white.opacity(0.08), .clear, .white.opacity(0.03)]
        case .standard:
            return [.white.opacity(0.15), .clear, .white.opacity(0.05)]
        case .premium:
            return [
                .white.opacity(0.25),
                .white.opacity(0.1),
                .clear,
                .white.opacity(0.05)
            ]
        }
    }
    
    private var edgeWidth: CGFloat {
        switch intensity {
        case .subtle: return 0.5
        case .standard: return 0.5
        case .premium: return 1.0
        }
    }
    
    private var shadowOpacity: Double {
        switch intensity {
        case .subtle: return 0.1
        case .standard: return 0.15
        case .premium: return 0.3
        }
    }
    
    private var shadowRadius: CGFloat {
        switch intensity {
        case .subtle: return 8
        case .standard: return 12
        case .premium: return 20
        }
    }
    
    private var shadowY: CGFloat {
        switch intensity {
        case .subtle: return 3
        case .standard: return 5
        case .premium: return 10
        }
    }
}

extension View {
    /// Applies the SaneVideo Tahoe-style Liquid Glass effect.
    /// - Parameters:
    ///   - radius: Corner radius (default: 12)
    ///   - opacity: Material opacity (default: 0.5)
    ///   - intensity: Visual intensity level (default: .standard)
    func liquidGlass(
        radius: CGFloat = 12,
        opacity: Double = 0.5,
        intensity: LiquidGlassModifier.GlassIntensity = .standard
    ) -> some View {
        self.modifier(LiquidGlassModifier(radius: radius, opacity: opacity, intensity: intensity))
    }
    
    /// Premium liquid glass for important cards and overlays
    func premiumGlass(radius: CGFloat = 12) -> some View {
        self.liquidGlass(radius: radius, intensity: .premium)
    }
    
    /// Subtle liquid glass for backgrounds
    func subtleGlass(radius: CGFloat = 12) -> some View {
        self.liquidGlass(radius: radius, intensity: .subtle)
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
    
    // CRITICAL FIX: Proper cleanup to prevent use-after-free during autorelease
    static func dismantleNSView(_ nsView: NSVisualEffectView, coordinator: ()) {
        nsView.state = .inactive
        nsView.removeFromSuperview()
    }
}
