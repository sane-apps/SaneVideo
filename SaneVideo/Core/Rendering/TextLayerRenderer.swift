//
//  TextLayerRenderer.swift
//  SaneVideo
//
//  Created by SaneVideo Refactor
//

import CoreImage
import Foundation
import AppKit

/// Renders text layers (captions, overlays) into a CIImage
enum TextLayerRenderer {
    
    // Simple CoreGraphics text renderer
    static func renderTextLayers(_ layers: [TextLayerItem], size: CGSize, faceRects: [CGRect] = []) -> CIImage? {
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

            // Style
            let paragraphStyle = NSMutableParagraphStyle()
            paragraphStyle.alignment = .center

            let fontSize = layer.isCaption ? size.height * 0.05 : size.height * 0.1
            let font = NSFont.systemFont(ofSize: fontSize, weight: .bold)

            let attributes: [NSAttributedString.Key: Any] = [
                .font: font,
                .foregroundColor: NSColor.white,
                .paragraphStyle: paragraphStyle,
                .strokeColor: NSColor.black,
                .strokeWidth: -3.0, // Negative for stroke + fill
                .shadow: {
                    let shadow = NSShadow()
                    shadow.shadowColor = NSColor.black.withAlphaComponent(0.8)
                    shadow.shadowOffset = CGSize(width: 2, height: -2)
                    shadow.shadowBlurRadius = 2
                    return shadow
                }()
            ]

            // Draw
            let string = NSAttributedString(string: text, attributes: attributes)

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
            string.draw(in: rect)

            context.restoreGState()
        }

        NSGraphicsContext.restoreGraphicsState()

        guard let cgImage = context.makeImage() else { return nil }
        return CIImage(cgImage: cgImage)
    }
}
