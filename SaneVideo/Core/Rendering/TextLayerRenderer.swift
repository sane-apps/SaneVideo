//
//  TextLayerRenderer.swift
//  SaneVideo
//
//  Created by SaneVideo Refactor
//

import AppKit
import CoreImage
import CoreMedia
import Foundation

/// Renders text layers (captions, overlays) into a CIImage
enum TextLayerRenderer {

    // MARK: - Main Renderer

    /// Renders text layers with optional karaoke word highlighting
    /// - Parameters:
    ///   - layers: Text layers to render
    ///   - size: Output size in pixels
    ///   - faceRects: Face rectangles for collision avoidance (normalized 0-1)
    ///   - compositionTime: Current time for karaoke word highlighting
    static func renderTextLayers(
        _ layers: [TextLayerItem],
        size: CGSize,
        faceRects: [CGRect] = [],
        compositionTime: CMTime = .zero
    ) -> CIImage? {
        // macOS Text Rendering using CoreGraphics/AppKit
        let colorSpace = CGColorSpace(name: CGColorSpace.sRGB)!
        let bitmapInfo = CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue)

        guard let context = CGContext(
            data: nil,
            width: Int(size.width),
            height: Int(size.height),
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: colorSpace,
            bitmapInfo: bitmapInfo.rawValue
        ) else { return nil }

        NSGraphicsContext.saveGraphicsState()
        let nsContext = NSGraphicsContext(cgContext: context, flipped: false)
        NSGraphicsContext.current = nsContext

        for layer in layers {
            var rect = CGRect(
                x: layer.frame.origin.x * size.width,
                y: layer.frame.origin.y * size.height,
                width: layer.frame.width * size.width,
                height: layer.frame.height * size.height
            )

            // Face-Aware Positioning (Safe Zones)
            if layer.isCaption && !faceRects.isEmpty {
                // Check if any face overlaps with the caption area
                for faceRect in faceRects {
                    // Vision rects are 0-1, convert to pixel space
                    let pixelFaceRect = CGRect(
                        x: faceRect.origin.x * size.width,
                        y: faceRect.origin.y * size.height,
                        width: faceRect.size.width * size.width,
                        height: faceRect.size.height * size.height
                    )
                    
                    if rect.intersects(pixelFaceRect) {
                        // Collision! Move caption up or down
                        if rect.midY < pixelFaceRect.midY {
                            // Caption is below face, push further down
                            rect.origin.y = min(size.height - rect.height - 20, pixelFaceRect.maxY + 20)
                        } else {
                            // Caption is above/on face, push up
                            rect.origin.y = max(20, pixelFaceRect.minY - rect.height - 20)
                        }
                    }
                }
            }

            let text = layer.text

            // Style - use provided CaptionStyle or fallback to defaults
            let paragraphStyle = NSMutableParagraphStyle()
            paragraphStyle.alignment = .center

            let style = layer.style

            // Font
            let baseFontSize = layer.isCaption ? size.height * 0.05 : size.height * 0.1
            let fontSize = style?.fontSize ?? baseFontSize
            let fontName = style?.fontName ?? "SF Pro Rounded"
            let isBold = style?.isBold ?? true
            let isItalic = style?.isItalic ?? false

            var fontTraits: NSFontTraitMask = []
            if isBold { fontTraits.insert(.boldFontMask) }
            if isItalic { fontTraits.insert(.italicFontMask) }

            let font: NSFont = {
                if let customFont = NSFont(name: fontName, size: fontSize) {
                    return NSFontManager.shared.convert(customFont, toHaveTrait: fontTraits)
                }
                return NSFont.systemFont(ofSize: fontSize, weight: isBold ? .bold : .regular)
            }()

            // Colors
            let textColor = style.flatMap { NSColor(hex: $0.textColor) } ?? NSColor.white
            let strokeColor = style?.strokeColor.flatMap { NSColor(hex: $0) } ?? NSColor.black
            let strokeWidth = style?.strokeWidth ?? 3.0

            // Shadow
            let shadow: NSShadow = {
                let s = NSShadow()
                if let style = style, style.shadowRadius > 0 {
                    s.shadowColor = style.shadowColor.flatMap { NSColor(hex: $0) } ?? NSColor.black.withAlphaComponent(0.8)
                    s.shadowOffset = CGSize(width: 2, height: -2)
                    s.shadowBlurRadius = style.shadowRadius
                } else {
                    s.shadowColor = NSColor.black.withAlphaComponent(0.8)
                    s.shadowOffset = CGSize(width: 2, height: -2)
                    s.shadowBlurRadius = 2
                }
                return s
            }()

            let baseAttributes: [NSAttributedString.Key: Any] = [
                .font: font,
                .foregroundColor: textColor,
                .paragraphStyle: paragraphStyle,
                .strokeColor: strokeColor,
                .strokeWidth: -strokeWidth, // Negative for stroke + fill
                .shadow: shadow
            ]

            // Create attributed string with karaoke highlighting if words are available
            let attributedString: NSAttributedString
            if let words = layer.words,
               !words.isEmpty,
               let style = layer.style,
               style.highlightStyle != .none {
                attributedString = createKaraokeAttributedString(
                    text: text,
                    words: words,
                    compositionTime: compositionTime,
                    baseAttributes: baseAttributes,
                    style: style,
                    font: font
                )
            } else {
                attributedString = NSAttributedString(string: text, attributes: baseAttributes)
            }

            // Apply Transform using CGContext
            context.saveGState()

            // 1. Calculate center of rect
            let midX = rect.midX
            let midY = rect.midY

            // 2. Translate to center
            context.translateBy(x: midX, y: midY)

            // 3. Rotate and Scale
            context.rotate(by: CGFloat(layer.rotation))
            context.scaleBy(x: layer.scale, y: layer.scale)

            // 4. Translate back
            context.translateBy(x: -midX, y: -midY)

            // 5. Draw
            attributedString.draw(in: rect)

            context.restoreGState()
        }

        NSGraphicsContext.restoreGraphicsState()

        guard let cgImage = context.makeImage() else { return nil }
        return CIImage(cgImage: cgImage)
    }

    // MARK: - Karaoke Highlighting

    /// Creates an attributed string with the active word highlighted for karaoke effect
    private static func createKaraokeAttributedString(
        text: String,
        words: [CaptionWord],
        compositionTime: CMTime,
        baseAttributes: [NSAttributedString.Key: Any],
        style: CaptionStyle,
        font: NSFont
    ) -> NSAttributedString {
        let mutableString = NSMutableAttributedString(string: text, attributes: baseAttributes)

        // Find the active word based on composition time
        let currentSeconds = compositionTime.seconds
        guard let activeWord = words.first(where: { currentSeconds >= $0.start && currentSeconds < $0.end }) else {
            return mutableString
        }

        // Find the range of the active word in the text
        guard let wordRange = text.range(of: activeWord.text, options: .caseInsensitive) else {
            return mutableString
        }

        let nsRange = NSRange(wordRange, in: text)

        // Get the active color
        let activeColor = style.activeTextColor.flatMap { NSColor(hex: $0) } ?? NSColor.yellow

        // Apply highlight based on style
        switch style.highlightStyle {
        case .none:
            break

        case .pop:
            // Larger font for active word
            let popFont = NSFont(descriptor: font.fontDescriptor, size: font.pointSize * 1.2) ?? font
            mutableString.addAttribute(.font, value: popFont, range: nsRange)
            mutableString.addAttribute(.foregroundColor, value: activeColor, range: nsRange)

        case .glow:
            // Glow effect via shadow
            let glowShadow = NSShadow()
            glowShadow.shadowColor = activeColor.withAlphaComponent(0.8)
            glowShadow.shadowBlurRadius = 10
            glowShadow.shadowOffset = .zero
            mutableString.addAttribute(.shadow, value: glowShadow, range: nsRange)
            mutableString.addAttribute(.foregroundColor, value: activeColor, range: nsRange)

        case .underline:
            // Underline the active word
            mutableString.addAttribute(.underlineStyle, value: NSUnderlineStyle.thick.rawValue, range: nsRange)
            mutableString.addAttribute(.underlineColor, value: activeColor, range: nsRange)
            mutableString.addAttribute(.foregroundColor, value: activeColor, range: nsRange)

        case .background:
            // Background highlight (like a marker)
            mutableString.addAttribute(.backgroundColor, value: activeColor.withAlphaComponent(0.4), range: nsRange)
        }

        return mutableString
    }
}
