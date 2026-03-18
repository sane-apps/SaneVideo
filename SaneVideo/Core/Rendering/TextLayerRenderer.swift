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
            paragraphStyle.lineBreakMode = .byWordWrapping

            let style = layer.style

            // Font
            let fontName = style?.fontName ?? "SF Pro Rounded"
            let isBold = style?.isBold ?? true
            let isItalic = style?.isItalic ?? false

            var fontTraits: NSFontTraitMask = []
            if isBold { fontTraits.insert(.boldFontMask) }
            if isItalic { fontTraits.insert(.italicFontMask) }

            let baseFontSize = layer.isCaption ? size.height * 0.05 : size.height * 0.042
            let preferredFontSize = style?.fontSize ?? baseFontSize
            let baseFont: NSFont = {
                if let customFont = NSFont(name: fontName, size: preferredFontSize) {
                    return NSFontManager.shared.convert(customFont, toHaveTrait: fontTraits)
                }
                return NSFont.systemFont(ofSize: preferredFontSize, weight: isBold ? .bold : .regular)
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

            let font = fittedFont(
                startingFrom: baseFont,
                for: text,
                in: rect,
                paragraphStyle: paragraphStyle,
                minimumScale: layer.isCaption ? 1.0 : 0.62
            )

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
                let karaokeInput = KaraokeInput(
                    text: text,
                    words: words,
                    compositionTime: compositionTime,
                    baseAttributes: baseAttributes,
                    style: style,
                    font: font
                )
                attributedString = createKaraokeAttributedString(using: karaokeInput)
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

    private static func fittedFont(
        startingFrom font: NSFont,
        for text: String,
        in rect: CGRect,
        paragraphStyle: NSParagraphStyle,
        minimumScale: CGFloat
    ) -> NSFont {
        guard !text.isEmpty, minimumScale < 1.0 else { return font }

        let insetRect = rect.insetBy(dx: 16, dy: 12)
        guard insetRect.width > 0, insetRect.height > 0 else { return font }

        let minimumSize = max(18, font.pointSize * minimumScale)
        var candidate = font

        while candidate.pointSize > minimumSize {
            if textFits(text, in: insetRect.size, font: candidate, paragraphStyle: paragraphStyle) {
                return candidate
            }

            let nextSize = max(minimumSize, candidate.pointSize * 0.92)
            guard nextSize < candidate.pointSize else { break }
            candidate = NSFont(descriptor: font.fontDescriptor, size: nextSize) ?? candidate
        }

        return candidate
    }

    private static func textFits(
        _ text: String,
        in size: CGSize,
        font: NSFont,
        paragraphStyle: NSParagraphStyle
    ) -> Bool {
        let attributes: [NSAttributedString.Key: Any] = [
            .font: font,
            .paragraphStyle: paragraphStyle
        ]

        let measured = NSAttributedString(string: text, attributes: attributes)
            .boundingRect(
                with: size,
                options: [.usesLineFragmentOrigin, .usesFontLeading],
                context: nil
            )

        return measured.width <= size.width && measured.height <= size.height
    }

    // MARK: - Karaoke Highlighting

    private struct KaraokeInput {
        let text: String
        let words: [CaptionWord]
        let compositionTime: CMTime
        let baseAttributes: [NSAttributedString.Key: Any]
        let style: CaptionStyle
        let font: NSFont
    }

    /// Creates an attributed string with the active word highlighted for karaoke effect
    private static func createKaraokeAttributedString(using input: KaraokeInput) -> NSAttributedString {
        let mutableString = NSMutableAttributedString(string: input.text, attributes: input.baseAttributes)

        // Find the active word based on composition time
        let currentSeconds = input.compositionTime.seconds
        guard let activeWord = input.words.first(where: { currentSeconds >= $0.start && currentSeconds < $0.end }) else {
            return mutableString
        }

        // Find the range of the active word in the text
        guard let wordRange = input.text.range(of: activeWord.text, options: .caseInsensitive) else {
            return mutableString
        }

        let nsRange = NSRange(wordRange, in: input.text)

        // Get the active color
        let activeColor = input.style.activeTextColor.flatMap { NSColor(hex: $0) } ?? NSColor.yellow

        // Apply highlight based on style
        switch input.style.highlightStyle {
        case .none:
            break

        case .pop:
            // Larger font for active word
            let popFont = NSFont(descriptor: input.font.fontDescriptor, size: input.font.pointSize * 1.2) ?? input.font
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

enum InteractionOverlayRenderer {
  static func renderInteractionLayers(
    _ layers: [InteractionLayerItem],
    size: CGSize,
    compositionTime: CMTime
  ) -> CIImage? {
    let activeLayers = layers.filter { $0.timeRange.containsTime(compositionTime) }
    guard !activeLayers.isEmpty else { return nil }

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
    ) else {
      return nil
    }

    NSGraphicsContext.saveGraphicsState()
    let nsContext = NSGraphicsContext(cgContext: context, flipped: false)
    NSGraphicsContext.current = nsContext

    for layer in activeLayers {
      if layer.style.spotlightCursor, let cursor = layer.cursorPosition(at: compositionTime) {
        drawCursorSpotlight(
          in: context,
          position: cursor,
          size: size,
          opacity: layer.style.spotlightOpacity
        )
      }

      if layer.style.highlightClicks {
        drawClickHighlights(
          in: context,
          clicks: layer.clicks,
          size: size,
          compositionTime: compositionTime,
          scale: layer.style.clickRingScale
        )
      }

      if layer.style.showKeystrokes {
        drawKeystrokes(
          in: context,
          keystrokes: layer.keystrokes,
          size: size,
          compositionTime: compositionTime
        )
      }
    }

    NSGraphicsContext.restoreGraphicsState()

    guard let cgImage = context.makeImage() else { return nil }
    return CIImage(cgImage: cgImage)
  }

  private static func drawCursorSpotlight(
    in context: CGContext,
    position: (x: Double, y: Double),
    size: CGSize,
    opacity: Double
  ) {
    let center = pixelPoint(fromNormalizedTopLeft: CGPoint(x: position.x, y: position.y), size: size)
    let radius = max(120, min(size.width, size.height) * 0.14)
    let colors = [
      NSColor(calibratedRed: 0.21, green: 0.49, blue: 1.0, alpha: min(0.45, opacity + 0.08)).cgColor,
      NSColor(calibratedRed: 0.21, green: 0.49, blue: 1.0, alpha: CGFloat(opacity)).cgColor,
      NSColor.clear.cgColor
    ] as CFArray
    let locations: [CGFloat] = [0.0, 0.35, 1.0]

    guard let gradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: colors, locations: locations) else {
      return
    }

    context.saveGState()
    context.setBlendMode(.screen)
    context.drawRadialGradient(
      gradient,
      startCenter: center,
      startRadius: 12,
      endCenter: center,
      endRadius: radius,
      options: [.drawsAfterEndLocation]
    )
    context.restoreGState()
  }

  private static func drawClickHighlights(
    in context: CGContext,
    clicks: [InteractionClickItem],
    size: CGSize,
    compositionTime: CMTime,
    scale: Double
  ) {
    let currentTime = compositionTime.seconds
    let visibleClicks = clicks.filter {
      let delta = currentTime - $0.time.seconds
      return delta >= 0 && delta <= 0.7
    }

    for click in visibleClicks {
      let delta = currentTime - click.time.seconds
      let progress = max(0, min(1, delta / 0.7))
      let center = pixelPoint(fromNormalizedTopLeft: CGPoint(x: click.x, y: click.y), size: size)
      let baseRadius = 20.0 * scale
      let radius = CGFloat(baseRadius + (44.0 * progress * scale))
      let alpha = CGFloat(1.0 - progress)
      let ringRect = CGRect(
        x: center.x - radius,
        y: center.y - radius,
        width: radius * 2,
        height: radius * 2
      )

      context.saveGState()
      context.setLineWidth(max(2, 4 - (progress * 1.5)))
      context.setStrokeColor(NSColor(calibratedRed: 0.24, green: 0.62, blue: 1.0, alpha: alpha).cgColor)
      context.strokeEllipse(in: ringRect)

      let fillRadius = max(8.0, 14.0 * (1.0 - progress * 0.4))
      let fillRect = CGRect(
        x: center.x - CGFloat(fillRadius / 2),
        y: center.y - CGFloat(fillRadius / 2),
        width: CGFloat(fillRadius),
        height: CGFloat(fillRadius)
      )
      context.setFillColor(NSColor.white.withAlphaComponent(alpha * 0.8).cgColor)
      context.fillEllipse(in: fillRect)
      context.restoreGState()
    }
  }

  private static func drawKeystrokes(
    in context: CGContext,
    keystrokes: [InteractionKeystrokeItem],
    size: CGSize,
    compositionTime: CMTime
  ) {
    let currentTime = compositionTime.seconds
    let visibleKeystrokes = keystrokes
      .filter {
        let delta = currentTime - $0.time.seconds
        return delta >= 0 && delta <= 2.4
      }
      .suffix(3)

    guard !visibleKeystrokes.isEmpty else { return }

    let paragraphStyle = NSMutableParagraphStyle()
    paragraphStyle.alignment = .center

    let font = NSFont.systemFont(ofSize: max(18, size.height * 0.022), weight: .semibold)
    let textAttributes: [NSAttributedString.Key: Any] = [
      .font: font,
      .foregroundColor: NSColor.white,
      .paragraphStyle: paragraphStyle
    ]

    let pillSpacing = max(10.0, size.height * 0.01)
    let horizontalPadding = max(18.0, size.width * 0.012)
    let verticalPadding = max(10.0, size.height * 0.008)
    var currentY = max(28.0, size.height * 0.045)

    for item in visibleKeystrokes.reversed() {
      let delta = currentTime - item.time.seconds
      let alpha = CGFloat(max(0.25, 1.0 - (delta / 2.4)))
      let attributedString = NSAttributedString(string: item.text, attributes: textAttributes)
      var textRect = attributedString.boundingRect(with: CGSize(width: size.width * 0.5, height: size.height), options: [.usesLineFragmentOrigin, .usesFontLeading])
      textRect.size.width = ceil(textRect.width)
      textRect.size.height = ceil(textRect.height)

      let pillRect = CGRect(
        x: size.width - textRect.width - horizontalPadding * 2 - max(28.0, size.width * 0.03),
        y: currentY,
        width: textRect.width + horizontalPadding * 2,
        height: textRect.height + verticalPadding * 2
      )

      let pillPath = NSBezierPath(roundedRect: pillRect, xRadius: pillRect.height / 2, yRadius: pillRect.height / 2)
      NSColor(calibratedRed: 0.03, green: 0.09, blue: 0.24, alpha: alpha * 0.9).setFill()
      pillPath.fill()
      NSColor(calibratedRed: 0.24, green: 0.62, blue: 1.0, alpha: alpha * 0.9).setStroke()
      pillPath.lineWidth = 1.5
      pillPath.stroke()

      let drawRect = CGRect(
        x: pillRect.minX + horizontalPadding,
        y: pillRect.minY + verticalPadding,
        width: textRect.width,
        height: textRect.height
      )
      attributedString.draw(in: drawRect)
      currentY += pillRect.height + pillSpacing
    }
  }

  private static func pixelPoint(fromNormalizedTopLeft point: CGPoint, size: CGSize) -> CGPoint {
    CGPoint(x: point.x * size.width, y: (1.0 - point.y) * size.height)
  }
}
