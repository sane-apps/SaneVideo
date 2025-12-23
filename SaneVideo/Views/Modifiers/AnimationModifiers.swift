//
//  AnimationModifiers.swift
//  SaneVideo
//
//  Consistent animation patterns for smooth, polished UI
//

import SwiftUI

// MARK: - Standard Animation Presets

extension Animation {
    /// Smooth, subtle animation for UI interactions
    static let smoothUI = Animation.smooth(duration: 0.25, extraBounce: 0)
    
    /// Quick, snappy animation for button presses
    static let quickSnap = Animation.smooth(duration: 0.15, extraBounce: 0)
    
    /// Gentle spring for panel transitions
    static let gentleSpring = Animation.spring(response: 0.4, dampingFraction: 0.8)
    
    /// Bouncy spring for playful interactions
    static let bouncySpring = Animation.spring(response: 0.5, dampingFraction: 0.6)
    
    /// Smooth fade for content changes
    static let smoothFade = Animation.smooth(duration: 0.2)
}

// MARK: - Transition Presets

extension AnyTransition {
    /// Smooth fade and scale transition
    @MainActor static var smoothScale: AnyTransition {
        .scale(scale: 0.95).combined(with: .opacity)
    }
    
    /// Slide from edge with fade
    @MainActor static func slideFromEdge(_ edge: Edge) -> AnyTransition {
        .move(edge: edge).combined(with: .opacity)
    }
    
    /// Gentle scale with fade
    @MainActor static var gentleScale: AnyTransition {
        .scale(scale: 0.98).combined(with: .opacity)
    }
}

// MARK: - ViewModifiers for Common Animations

/// Smooth appearance animation
struct SmoothAppearModifier: ViewModifier {
    @State private var isVisible = false
    
    func body(content: Content) -> some View {
        content
            .opacity(isVisible ? 1 : 0)
            .scaleEffect(isVisible ? 1 : 0.95)
            .onAppear {
                withAnimation(.smoothUI) {
                    isVisible = true
                }
            }
    }
}

/// Hover scale effect
struct HoverScaleModifier: ViewModifier {
    @State private var isHovered = false
    let scale: CGFloat
    
    init(scale: CGFloat = 1.05) {
        self.scale = scale
    }
    
    func body(content: Content) -> some View {
        content
            .scaleEffect(isHovered ? scale : 1.0)
            .animation(.smoothUI, value: isHovered)
            .onHover { hovering in
                isHovered = hovering
            }
    }
}

/// Press scale effect
struct PressScaleModifier: ViewModifier {
    @State private var isPressed = false
    
    func body(content: Content) -> some View {
        content
            .scaleEffect(isPressed ? 0.96 : 1.0)
            .animation(.quickSnap, value: isPressed)
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { _ in
                        isPressed = true
                    }
                    .onEnded { _ in
                        isPressed = false
                    }
            )
    }
}

/// Smooth value change animation
struct AnimatedValueModifier<T: Equatable>: ViewModifier {
    let value: T
    @State private var animatedValue: T
    
    init(value: T) {
        self.value = value
        _animatedValue = State(initialValue: value)
    }
    
    func body(content: Content) -> some View {
        content
            .onChange(of: value) { _, newValue in
                withAnimation(.smoothUI) {
                    animatedValue = newValue
                }
            }
    }
}

extension View {
    /// Smooth appear animation
    func smoothAppear() -> some View {
        modifier(SmoothAppearModifier())
    }
    
    /// Hover scale effect
    func hoverScale(_ scale: CGFloat = 1.05) -> some View {
        modifier(HoverScaleModifier(scale: scale))
    }
    
    /// Press scale effect
    func pressScale() -> some View {
        modifier(PressScaleModifier())
    }
}

// MARK: - Liquid Glass Enhancements

extension View {
    /// Enhanced liquid glass with subtle animations
    func enhancedLiquidGlass(radius: CGFloat = 12, opacity: Double = 0.5) -> some View {
        self
            .liquidGlass(radius: radius, opacity: opacity)
            .overlay(
                RoundedRectangle(cornerRadius: radius)
                    .stroke(
                        LinearGradient(
                            colors: [
                                .white.opacity(0.2),
                                .white.opacity(0.05),
                                .clear
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        lineWidth: 1
                    )
            )
            .shadow(color: .black.opacity(0.15), radius: 12, x: 0, y: 6)
    }
}

