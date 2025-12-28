//
//  LiquidGlassNSView.swift
//  SaneVideo
//
//  NSView wrapper for Liquid Glass effect in AppKit windows (PiP, Floating Controls).
//  Matches the SwiftUI LiquidGlassModifier for visual consistency across the app.
//

import AppKit

/// An NSView that applies the macOS Tahoe "Liquid Glass" aesthetic for AppKit windows.
/// Use this in NSPanel/NSWindow contentView for consistent styling with SwiftUI views.
final class LiquidGlassNSView: NSView {

    // MARK: - Configuration

    enum Intensity {
        case subtle      // For backgrounds
        case standard    // Default
        case premium     // For important floating windows
    }

    private let intensity: Intensity
    private let cornerRadius: CGFloat

    private let visualEffectView: NSVisualEffectView
    private let edgeLayer: CAGradientLayer
    private let innerGlowLayer: CAGradientLayer?

    // MARK: - Initialization

    init(intensity: Intensity = .standard, cornerRadius: CGFloat = 12) {
        self.intensity = intensity
        self.cornerRadius = cornerRadius

        // Create visual effect view
        visualEffectView = NSVisualEffectView()
        visualEffectView.material = .hudWindow
        visualEffectView.state = .active
        visualEffectView.blendingMode = .withinWindow

        // Create edge lighting layer
        edgeLayer = CAGradientLayer()

        // Inner glow only for premium
        innerGlowLayer = intensity == .premium ? CAGradientLayer() : nil

        super.init(frame: .zero)

        setupLayers()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    // MARK: - Setup

    private func setupLayers() {
        wantsLayer = true
        layer?.cornerRadius = cornerRadius
        layer?.masksToBounds = true

        // Add visual effect view as base
        visualEffectView.translatesAutoresizingMaskIntoConstraints = false
        addSubview(visualEffectView)

        NSLayoutConstraint.activate([
            visualEffectView.leadingAnchor.constraint(equalTo: leadingAnchor),
            visualEffectView.trailingAnchor.constraint(equalTo: trailingAnchor),
            visualEffectView.topAnchor.constraint(equalTo: topAnchor),
            visualEffectView.bottomAnchor.constraint(equalTo: bottomAnchor)
        ])

        visualEffectView.wantsLayer = true
        visualEffectView.layer?.cornerRadius = cornerRadius
        visualEffectView.layer?.masksToBounds = true

        // Configure edge layer
        configureEdgeLayer()

        // Configure inner glow for premium
        if let innerGlow = innerGlowLayer {
            configureInnerGlowLayer(innerGlow)
        }

        // Add shadow
        configureShadow()
    }

    private func configureEdgeLayer() {
        edgeLayer.type = .axial
        edgeLayer.startPoint = CGPoint(x: 0, y: 0)
        edgeLayer.endPoint = CGPoint(x: 1, y: 1)
        edgeLayer.colors = edgeColors
        edgeLayer.cornerRadius = cornerRadius
        edgeLayer.masksToBounds = true

        // Create border mask
        let borderWidth = edgeWidth
        let maskLayer = CAShapeLayer()
        maskLayer.fillColor = nil
        maskLayer.strokeColor = NSColor.white.cgColor
        maskLayer.lineWidth = borderWidth
        edgeLayer.mask = maskLayer

        layer?.addSublayer(edgeLayer)
    }

    private func configureInnerGlowLayer(_ glowLayer: CAGradientLayer) {
        glowLayer.type = .axial
        glowLayer.startPoint = CGPoint(x: 0.5, y: 0)
        glowLayer.endPoint = CGPoint(x: 0.5, y: 0.5)
        glowLayer.colors = [
            NSColor.white.withAlphaComponent(0.1).cgColor,
            NSColor.clear.cgColor
        ]
        glowLayer.cornerRadius = cornerRadius
        glowLayer.masksToBounds = true

        // Inner border mask
        let maskLayer = CAShapeLayer()
        maskLayer.fillColor = nil
        maskLayer.strokeColor = NSColor.white.cgColor
        maskLayer.lineWidth = 0.5
        glowLayer.mask = maskLayer

        layer?.addSublayer(glowLayer)
    }

    private func configureShadow() {
        layer?.shadowColor = NSColor.black.cgColor
        layer?.shadowOpacity = Float(shadowOpacity)
        layer?.shadowRadius = shadowRadius
        layer?.shadowOffset = CGSize(width: 0, height: -shadowY)
        layer?.masksToBounds = false
    }

    // MARK: - Layout

    override func layout() {
        super.layout()

        CATransaction.begin()
        CATransaction.setDisableActions(true)

        edgeLayer.frame = bounds
        innerGlowLayer?.frame = bounds

        // Update border mask paths
        updateBorderMask(for: edgeLayer, inset: 0)
        if let innerGlow = innerGlowLayer {
            updateBorderMask(for: innerGlow, inset: 1)
        }

        // Update shadow path for performance
        layer?.shadowPath = NSBezierPath(roundedRect: bounds, xRadius: cornerRadius, yRadius: cornerRadius).cgPath

        CATransaction.commit()
    }

    private func updateBorderMask(for gradientLayer: CAGradientLayer, inset: CGFloat) {
        guard let maskLayer = gradientLayer.mask as? CAShapeLayer else { return }

        let insetRect = bounds.insetBy(dx: inset, dy: inset)
        let path = NSBezierPath(roundedRect: insetRect, xRadius: cornerRadius - inset, yRadius: cornerRadius - inset)
        maskLayer.path = path.cgPath
        maskLayer.frame = bounds
    }

    // MARK: - Intensity-Based Properties

    private var edgeColors: [CGColor] {
        switch intensity {
        case .subtle:
            return [
                NSColor.white.withAlphaComponent(0.08).cgColor,
                NSColor.clear.cgColor,
                NSColor.white.withAlphaComponent(0.03).cgColor
            ]
        case .standard:
            return [
                NSColor.white.withAlphaComponent(0.15).cgColor,
                NSColor.clear.cgColor,
                NSColor.white.withAlphaComponent(0.05).cgColor
            ]
        case .premium:
            return [
                NSColor.white.withAlphaComponent(0.25).cgColor,
                NSColor.white.withAlphaComponent(0.1).cgColor,
                NSColor.clear.cgColor,
                NSColor.white.withAlphaComponent(0.05).cgColor
            ]
        }
    }

    private var edgeWidth: CGFloat {
        switch intensity {
        case .subtle, .standard: return 0.5
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

// MARK: - NSBezierPath CGPath Extension

private extension NSBezierPath {
    var cgPath: CGPath {
        let path = CGMutablePath()
        var points = [CGPoint](repeating: .zero, count: 3)

        for i in 0..<elementCount {
            let type = element(at: i, associatedPoints: &points)
            switch type {
            case .moveTo:
                path.move(to: points[0])
            case .lineTo:
                path.addLine(to: points[0])
            case .curveTo:
                path.addCurve(to: points[2], control1: points[0], control2: points[1])
            case .closePath:
                path.closeSubpath()
            case .cubicCurveTo:
                path.addCurve(to: points[2], control1: points[0], control2: points[1])
            case .quadraticCurveTo:
                path.addQuadCurve(to: points[1], control: points[0])
            @unknown default:
                break
            }
        }

        return path
    }
}
