#!/usr/bin/env swift
// Builds docs/images/og-image.png (1200x630) for sanevideo.com.
// Pattern follows saneapps.com/generate_og_image.swift. White text, one cyan accent (SaneUI accentSoft #5CDBF2).
// Usage: swift scripts/generate_og_image.swift <editor-capture.png> [output.png]
import Cocoa
import CoreText

let width = 1200
let height = 630
let args = CommandLine.arguments
let scriptDir = URL(fileURLWithPath: args[0]).deletingLastPathComponent().path
let docsImages = "\(scriptDir)/../docs/images"
guard args.count >= 2 else {
    print("Usage: swift generate_og_image.swift <editor-capture.png> [output.png]")
    exit(2)
}

let capturePath = args[1]
let outputPath = args.count >= 3 ? args[2] : "\(docsImages)/og-image.png"

let colorSpace = CGColorSpaceCreateDeviceRGB()
guard let ctx = CGContext(
    data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width * 4,
    space: colorSpace, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
) else {
    print("Failed to create context")
    exit(1)
}

// Top-left origin.
ctx.translateBy(x: 0, y: CGFloat(height))
ctx.scaleBy(x: 1, y: -1)

let white = CGColor(red: 1, green: 1, blue: 1, alpha: 1)
let accent = CGColor(red: 0x5C / 255.0, green: 0xDB / 255.0, blue: 0xF2 / 255.0, alpha: 1)

// Background: site --bg #070b12 with a faint cyan glow behind the capture.
ctx.setFillColor(CGColor(red: 0x07 / 255.0, green: 0x0B / 255.0, blue: 0x12 / 255.0, alpha: 1))
ctx.fill(CGRect(x: 0, y: 0, width: width, height: height))
let glow = [
    CGColor(red: 0x5C / 255.0, green: 0xDB / 255.0, blue: 0xF2 / 255.0, alpha: 0.16),
    CGColor(red: 0x5C / 255.0, green: 0xDB / 255.0, blue: 0xF2 / 255.0, alpha: 0)
] as CFArray
if let gradient = CGGradient(colorsSpace: colorSpace, colors: glow, locations: [0, 1]) {
    ctx.drawRadialGradient(gradient, startCenter: CGPoint(x: 930, y: 300), startRadius: 0,
                           endCenter: CGPoint(x: 930, y: 300), endRadius: 520, options: [])
}

func drawImage(_ path: String, in rect: CGRect, radius: CGFloat, crop: CGRect? = nil) {
    guard let nsImage = NSImage(contentsOfFile: path),
          var cg = nsImage.cgImage(forProposedRect: nil, context: nil, hints: nil)
    else {
        print("Missing image: \(path)")
        exit(1)
    }
    if let crop, let cropped = cg.cropping(to: crop) {
        cg = cropped
    }
    ctx.saveGState()
    ctx.addPath(CGPath(roundedRect: rect, cornerWidth: radius, cornerHeight: radius, transform: nil))
    ctx.clip()
    ctx.translateBy(x: rect.minX, y: rect.maxY)
    ctx.scaleBy(x: 1, y: -1)
    ctx.interpolationQuality = .high
    ctx.draw(cg, in: CGRect(origin: .zero, size: rect.size))
    ctx.restoreGState()
}

func drawText(_ text: String, x: CGFloat, y: CGFloat, size: CGFloat, weight: NSFont.Weight, color: CGColor) {
    let attrs: [NSAttributedString.Key: Any] = [
        .font: NSFont.systemFont(ofSize: size, weight: weight),
        .foregroundColor: NSColor(cgColor: color) ?? NSColor.white
    ]
    let line = CTLineCreateWithAttributedString(NSAttributedString(string: text, attributes: attrs))
    ctx.saveGState()
    ctx.translateBy(x: 0, y: CGFloat(height))
    ctx.scaleBy(x: 1, y: -1)
    // y is the top of the line box.
    ctx.textPosition = CGPoint(x: x, y: CGFloat(height) - y - size)
    CTLineDraw(line, ctx)
    ctx.restoreGState()
}

// Capture on the right, running off the right edge. The editor capture is cropped to the
// preview, timeline and Clean Up panel so the card shows the app at a readable size.
guard let captureImage = NSImage(contentsOfFile: capturePath),
      let captureCG = captureImage.cgImage(forProposedRect: nil, context: nil, hints: nil)
else {
    print("Missing capture: \(capturePath)")
    exit(1)
}

let cw = CGFloat(captureCG.width)
let ch = CGFloat(captureCG.height)
// Skip the left sidebar (about 21% of the window) so the preview, timeline and Clean Up panel fill the card.
let cropRect = CGRect(x: cw * 0.207, y: 0, width: cw * 0.793, height: ch)
let shotHeight: CGFloat = 470
let shotWidth = shotHeight * cropRect.width / cropRect.height
let shotRect = CGRect(x: 640, y: (CGFloat(height) - shotHeight) / 2, width: shotWidth, height: shotHeight)
drawImage(capturePath, in: shotRect, radius: 14, crop: cropRect)
ctx.setStrokeColor(CGColor(red: 1, green: 1, blue: 1, alpha: 0.16))
ctx.setLineWidth(1.5)
ctx.addPath(CGPath(roundedRect: shotRect, cornerWidth: 14, cornerHeight: 14, transform: nil))
ctx.strokePath()

// Text column.
drawImage("\(docsImages)/icon.png", in: CGRect(x: 64, y: 62, width: 60, height: 60), radius: 13)
drawText("SaneVideo", x: 138, y: 72, size: 34, weight: .bold, color: white)
drawText("Record. Clean Up.", x: 64, y: 176, size: 58, weight: .heavy, color: white)
drawText("Post.", x: 64, y: 244, size: 58, weight: .heavy, color: white)
drawText("Screen and camera videos", x: 64, y: 340, size: 28, weight: .semibold, color: white)
drawText("for YouTube and Shorts.", x: 64, y: 376, size: 28, weight: .semibold, color: white)
drawText("One click cuts silences and ums.", x: 64, y: 432, size: 23, weight: .regular, color: white)
drawText("Runs on your Mac.", x: 64, y: 464, size: 23, weight: .regular, color: white)
/// Footer words in white with cyan separators, laid out by measured width.
var footerX: CGFloat = 64
for (index, word) in ["Free", "Mac", "sanevideo.com"].enumerated() {
    if index > 0 {
        drawText("·", x: footerX + 10, y: 540, size: 22, weight: .heavy, color: accent)
        footerX += 34
    }
    drawText(word, x: footerX, y: 540, size: 22, weight: .semibold, color: white)
    let font = NSFont.systemFont(ofSize: 22, weight: .semibold)
    footerX += (word as NSString).size(withAttributes: [.font: font]).width
}

// Accent rule along the bottom edge.
ctx.setFillColor(accent)
ctx.fill(CGRect(x: 0, y: CGFloat(height) - 4, width: CGFloat(width), height: 4))

guard let image = ctx.makeImage(),
      let dest = CGImageDestinationCreateWithURL(URL(fileURLWithPath: outputPath) as CFURL, "public.png" as CFString, 1, nil)
else {
    print("Failed to write image")
    exit(1)
}

CGImageDestinationAddImage(dest, image, nil)
CGImageDestinationFinalize(dest)
print("OG image saved to \(outputPath)")
