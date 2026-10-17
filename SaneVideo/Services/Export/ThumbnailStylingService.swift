import AppKit
import CoreImage
import Foundation

/// Handles thumbnail image styling (filters, presets, text overlay)
enum ThumbnailStylingService {
    private static var context: CIContext { RenderingService.shared.ciContext }

    struct StylePreset {
        let saturation: Double
        let brightness: Double
        let contrast: Double
    }
    
    static func applyStyle(
        to image: NSImage,
        style: ThumbnailStyle,
        saturation: Double,
        brightness: Double,
        contrast: Double
    ) -> NSImage? {
        guard let tiffData = image.tiffRepresentation,
              let ciImage = CIImage(data: tiffData) else { return nil }
        
        var filtered = ciImage
        
        if let colorFilter = CIFilter(name: "CIColorControls") {
            colorFilter.setValue(filtered, forKey: kCIInputImageKey)
            colorFilter.setValue(saturation, forKey: kCIInputSaturationKey)
            colorFilter.setValue(brightness, forKey: kCIInputBrightnessKey)
            colorFilter.setValue(contrast, forKey: kCIInputContrastKey)
            if let output = colorFilter.outputImage {
                filtered = output
            }
        }
        
        if style == .warm {
            filtered = applyWarmTint(to: filtered)
        } else if style == .cool {
            filtered = applyCoolTint(to: filtered)
        }
        
        guard let cgImage = context.createCGImage(filtered, from: filtered.extent) else { return nil }
        return NSImage(cgImage: cgImage, size: image.size)
    }
    
    private static func applyWarmTint(to image: CIImage) -> CIImage {
        guard let tempFilter = CIFilter(name: "CITemperatureAndTint") else { return image }
        tempFilter.setValue(image, forKey: kCIInputImageKey)
        tempFilter.setValue(CIVector(x: 6500, y: 0), forKey: "inputNeutral")
        tempFilter.setValue(CIVector(x: 7500, y: 0), forKey: "inputTargetNeutral")
        return tempFilter.outputImage ?? image
    }
    
    private static func applyCoolTint(to image: CIImage) -> CIImage {
        guard let tempFilter = CIFilter(name: "CITemperatureAndTint") else { return image }
        tempFilter.setValue(image, forKey: kCIInputImageKey)
        tempFilter.setValue(CIVector(x: 6500, y: 0), forKey: "inputNeutral")
        tempFilter.setValue(CIVector(x: 5500, y: 0), forKey: "inputTargetNeutral")
        return tempFilter.outputImage ?? image
    }
    
    /// Add text overlay at bottom of image
    static func addTextOverlay(to image: NSImage, text: String) -> NSImage {
        let newImage = NSImage(size: image.size)
        newImage.lockFocus()
        
        image.draw(in: NSRect(origin: .zero, size: image.size))
        
        let gradientHeight: CGFloat = image.size.height * 0.25
        let gradientRect = NSRect(x: 0, y: 0, width: image.size.width, height: gradientHeight)
        
        if let gradient = NSGradient(starting: NSColor.black.withAlphaComponent(0.8),
                                      ending: NSColor.clear) {
            gradient.draw(in: gradientRect, angle: 90)
        }
        
        let fontSize = min(image.size.width / 15, 60)
        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: fontSize, weight: .bold),
            .foregroundColor: NSColor.white,
            .strokeColor: NSColor.black,
            .strokeWidth: -2
        ]
        
        let textSize = text.size(withAttributes: attributes)
        let textX = (image.size.width - textSize.width) / 2
        let textY = gradientHeight / 2 - textSize.height / 2 + 10
        
        text.draw(at: NSPoint(x: textX, y: textY), withAttributes: attributes)
        
        newImage.unlockFocus()
        return newImage
    }
    
    static func presetValues(for style: ThumbnailStyle) -> StylePreset {
        switch style {
        case .original:
            return StylePreset(saturation: 1.0, brightness: 0.0, contrast: 1.0)
        case .vibrant:
            return StylePreset(saturation: 1.5, brightness: 0.05, contrast: 1.1)
        case .dramatic:
            return StylePreset(saturation: 0.8, brightness: -0.05, contrast: 1.4)
        case .warm:
            return StylePreset(saturation: 1.2, brightness: 0.05, contrast: 1.1)
        case .cool:
            return StylePreset(saturation: 1.1, brightness: 0.0, contrast: 1.1)
        case .bw:
            return StylePreset(saturation: 0.0, brightness: 0.0, contrast: 1.2)
        }
    }
}
