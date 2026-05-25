#!/usr/bin/env swift

import AppKit
import Foundation

struct ScreenshotSpec {
    let fileName: String
    let title: String
    let subtitle: String
    let callouts: [String]
}

let specs: [ScreenshotSpec] = [
    ScreenshotSpec(
        fileName: "appstore-01-recording-dark-mac.png",
        title: "Record screen, camera, and mic",
        subtitle: "Capture a clean local take with native Mac controls.",
        callouts: ["Screen", "Camera", "Mic", "Record"]
    ),
    ScreenshotSpec(
        fileName: "appstore-02-editing-dark-mac.png",
        title: "Edit locally on a timeline",
        subtitle: "Trim clips, arrange scenes, and polish without uploading footage.",
        callouts: ["Media", "Timeline", "Inspector", "Preview"]
    ),
    ScreenshotSpec(
        fileName: "appstore-03-export-dark-mac.png",
        title: "Export local files with presets",
        subtitle: "Choose 4K, 1080p, vertical, or small-file presets.",
        callouts: ["4K", "1080p", "Vertical", "Small File"]
    ),
    ScreenshotSpec(
        fileName: "appstore-04-captions-demo-pack-dark-mac.png",
        title: "Captions and demo packs",
        subtitle: "Package finished videos with captions and creator-ready assets.",
        callouts: ["Captions", "Demo Pack", "Local", "Ready"]
    )
]

let outputDirectory = URL(fileURLWithPath: CommandLine.arguments.dropFirst().first ?? "Screenshots", isDirectory: true)
try FileManager.default.createDirectory(at: outputDirectory, withIntermediateDirectories: true)

let canvasSize = NSSize(width: 2880, height: 1800)
let background = NSColor(calibratedRed: 0.035, green: 0.039, blue: 0.047, alpha: 1)
let panel = NSColor(calibratedRed: 0.10, green: 0.115, blue: 0.135, alpha: 1)
let accent = NSColor(calibratedRed: 0.20, green: 0.63, blue: 0.94, alpha: 1)
let green = NSColor(calibratedRed: 0.26, green: 0.82, blue: 0.49, alpha: 1)
let text = NSColor.white
let muted = NSColor(calibratedWhite: 0.86, alpha: 1)

func attributes(size: CGFloat, weight: NSFont.Weight, color: NSColor) -> [NSAttributedString.Key: Any] {
    [
        .font: NSFont.systemFont(ofSize: size, weight: weight),
        .foregroundColor: color
    ]
}

func fillRounded(_ rect: NSRect, radius: CGFloat, color: NSColor) {
    color.setFill()
    NSBezierPath(roundedRect: rect, xRadius: radius, yRadius: radius).fill()
}

func strokeRounded(_ rect: NSRect, radius: CGFloat, color: NSColor, width: CGFloat = 4) {
    color.setStroke()
    let path = NSBezierPath(roundedRect: rect, xRadius: radius, yRadius: radius)
    path.lineWidth = width
    path.stroke()
}

func drawString(_ value: String, in rect: NSRect, size: CGFloat, weight: NSFont.Weight = .regular, color: NSColor = text, alignment: NSTextAlignment = .left) {
    let paragraph = NSMutableParagraphStyle()
    paragraph.alignment = alignment
    paragraph.lineBreakMode = .byWordWrapping
    var attrs = attributes(size: size, weight: weight, color: color)
    attrs[.paragraphStyle] = paragraph
    value.draw(in: rect, withAttributes: attrs)
}

func drawChrome(in rect: NSRect) {
    fillRounded(rect, radius: 34, color: panel)
    strokeRounded(rect, radius: 34, color: NSColor(calibratedWhite: 1, alpha: 0.10), width: 3)
    let trafficY = rect.maxY - 64
    [NSColor.systemRed, NSColor.systemYellow, NSColor.systemGreen].enumerated().forEach { index, color in
        color.setFill()
        NSBezierPath(ovalIn: NSRect(x: rect.minX + 54 + CGFloat(index * 34), y: trafficY, width: 18, height: 18)).fill()
    }
}

func drawTimeline(in rect: NSRect) {
    fillRounded(rect, radius: 18, color: NSColor(calibratedRed: 0.06, green: 0.07, blue: 0.09, alpha: 1))
    for row in 0..<4 {
        let y = rect.minY + 38 + CGFloat(row) * 86
        let track = NSRect(x: rect.minX + 42, y: y, width: rect.width - 84, height: 42)
        fillRounded(track, radius: 10, color: NSColor(calibratedWhite: 1, alpha: 0.06))
        let clipWidth = (track.width - 64) / 3
        for clip in 0..<3 {
            let clipRect = NSRect(x: track.minX + CGFloat(clip) * (clipWidth + 24), y: track.minY + 7, width: clipWidth, height: 28)
            fillRounded(clipRect, radius: 8, color: clip == row % 3 ? accent : NSColor(calibratedWhite: 1, alpha: 0.18))
        }
    }
}

func drawScreenshot(_ spec: ScreenshotSpec) throws {
    guard let bitmap = NSBitmapImageRep(
        bitmapDataPlanes: nil,
        pixelsWide: Int(canvasSize.width),
        pixelsHigh: Int(canvasSize.height),
        bitsPerSample: 8,
        samplesPerPixel: 4,
        hasAlpha: true,
        isPlanar: false,
        colorSpaceName: .deviceRGB,
        bytesPerRow: 0,
        bitsPerPixel: 0
    ),
    let context = NSGraphicsContext(bitmapImageRep: bitmap)
    else {
        throw NSError(domain: "SaneVideoScreenshots", code: 1, userInfo: [NSLocalizedDescriptionKey: "Could not create bitmap context for \(spec.fileName)"])
    }

    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = context
    context.cgContext.setShouldAntialias(true)
    context.cgContext.setAllowsAntialiasing(true)
    defer { NSGraphicsContext.restoreGraphicsState() }

    background.setFill()
    NSRect(origin: .zero, size: canvasSize).fill()

    drawString("SaneVideo", in: NSRect(x: 160, y: 1585, width: 420, height: 80), size: 54, weight: .bold)
    drawString(spec.title, in: NSRect(x: 160, y: 1380, width: 980, height: 150), size: 78, weight: .bold)
    drawString(spec.subtitle, in: NSRect(x: 166, y: 1280, width: 890, height: 90), size: 34, color: muted)

    let appRect = NSRect(x: 1110, y: 245, width: 1580, height: 1270)
    drawChrome(in: appRect)
    fillRounded(NSRect(x: appRect.minX + 52, y: appRect.minY + 585, width: 920, height: 560), radius: 24, color: NSColor(calibratedRed: 0.02, green: 0.025, blue: 0.032, alpha: 1))
    strokeRounded(NSRect(x: appRect.minX + 52, y: appRect.minY + 585, width: 920, height: 560), radius: 24, color: accent, width: 3)
    drawString("Preview", in: NSRect(x: appRect.minX + 94, y: appRect.minY + 1065, width: 220, height: 54), size: 30, weight: .semibold)

    fillRounded(NSRect(x: appRect.minX + 1030, y: appRect.minY + 585, width: 480, height: 560), radius: 24, color: NSColor(calibratedWhite: 1, alpha: 0.06))
    drawString("Controls", in: NSRect(x: appRect.minX + 1070, y: appRect.minY + 1065, width: 240, height: 54), size: 30, weight: .semibold)
    for (index, item) in spec.callouts.enumerated() {
        let row = NSRect(x: appRect.minX + 1070, y: appRect.minY + 965 - CGFloat(index) * 92, width: 400, height: 58)
        fillRounded(row, radius: 14, color: index == 0 ? accent : NSColor(calibratedWhite: 1, alpha: 0.10))
        drawString(item, in: row.insetBy(dx: 24, dy: 12), size: 24, weight: .semibold)
    }

    drawTimeline(in: NSRect(x: appRect.minX + 52, y: appRect.minY + 92, width: 1458, height: 390))

    fillRounded(NSRect(x: 160, y: 360, width: 780, height: 120), radius: 24, color: accent)
    drawString("Private by default", in: NSRect(x: 210, y: 394, width: 680, height: 54), size: 34, weight: .bold)
    drawString("Local files stay local. No personal customer data collection.", in: NSRect(x: 166, y: 265, width: 820, height: 70), size: 30, color: muted)

    let url = outputDirectory.appendingPathComponent(spec.fileName)
    guard let data = bitmap.representation(using: .png, properties: [:]) else {
        throw NSError(domain: "SaneVideoScreenshots", code: 1, userInfo: [NSLocalizedDescriptionKey: "Could not render \(spec.fileName)"])
    }
    try data.write(to: url)
    print("Wrote \(url.path)")
}

for spec in specs {
    try drawScreenshot(spec)
}
