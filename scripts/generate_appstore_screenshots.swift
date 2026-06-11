#!/usr/bin/env swift

import AppKit
import Foundation

struct RealShotSpec {
    let fileName: String
    let websiteName: String
    let title: String
    let realAppSource: String
}

let specs: [RealShotSpec] = [
    RealShotSpec(
        fileName: "appstore-01-editing-dark-mac.png",
        websiteName: "sanevideo-actual-edit-workflow.png",
        title: "Edit locally with Magic Fix tools",
        realAppSource: "outputs/visual-audit-20260603/01-editor-real-fixture.png"
    ),
    RealShotSpec(
        fileName: "appstore-02-magic-fix-dark-mac.png",
        websiteName: "sanevideo-magic-fix.png",
        title: "Polish clips with Magic Fix",
        realAppSource: "outputs/appstore-real-captures/04-inspector-magic-fix.png"
    ),
    RealShotSpec(
        fileName: "appstore-03-recording-complete-dark-mac.png",
        websiteName: "sanevideo-recording-complete.png",
        title: "Save, edit, or share a recording",
        realAppSource: "outputs/appstore-real-captures/05-recording-complete.png"
    )
]

let root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath, isDirectory: true)
let screenshotsDirectory = root.appendingPathComponent("Screenshots", isDirectory: true)
let websiteImagesDirectory = root.appendingPathComponent("docs/images", isDirectory: true)
try FileManager.default.createDirectory(at: screenshotsDirectory, withIntermediateDirectories: true)
try FileManager.default.createDirectory(at: websiteImagesDirectory, withIntermediateDirectories: true)

let appStoreSize = NSSize(width: 5_760, height: 3_600)
let websiteSize = NSSize(width: 1_512, height: 1_012)
let matteColor = NSColor(calibratedRed: 0.043, green: 0.059, blue: 0.078, alpha: 1)

enum ScreenshotGenerationError: Error, CustomStringConvertible {
    case missingRealAppSource(String)
    case cannotLoadRealAppSource(String)
    case cannotEncodePNG(String)
    case duplicateRealAppSources([String])

    var description: String {
        switch self {
        case .missingRealAppSource(let path):
            return "Missing real SaneVideo app capture: \(path). Do not generate synthetic UI; capture the actual app with sample media loaded."
        case .cannotLoadRealAppSource(let path):
            return "Could not load real SaneVideo app capture: \(path)."
        case .cannotEncodePNG(let path):
            return "Could not encode PNG: \(path)."
        case .duplicateRealAppSources(let paths):
            return "App Store screenshots must use feature-specific real app captures. Duplicate source(s): \(paths.joined(separator: ", "))."
        }
    }
}

let duplicateSources = Dictionary(grouping: specs, by: \.realAppSource)
    .filter { $0.value.count > 1 }
    .map(\.key)
    .sorted()
if !duplicateSources.isEmpty {
    throw ScreenshotGenerationError.duplicateRealAppSources(duplicateSources)
}

let staleWebsiteImageNames = [
    "sanevideo-actual-edit-workflow.jpg",
    "sanevideo-recording.jpg",
    "sanevideo-recording.png",
    "sanevideo-captions-demo-pack.jpg",
    "sanevideo-captions-demo-pack.png",
    "sanevideo-export.jpg",
    "sanevideo-export.png",
    "sanevideo-inspector-tools.jpg",
    "sanevideo-inspector-tools.png",
    "sanevideo-magic-fix.jpg",
    "sanevideo-magic-fix.png"
]

func removeGeneratedOutputs() throws {
    let generatedAppStoreNames = try FileManager.default
        .contentsOfDirectory(atPath: screenshotsDirectory.path)
        .filter { $0.hasPrefix("appstore-") && $0.hasSuffix("-dark-mac.png") }
    for name in generatedAppStoreNames {
        try FileManager.default.removeItem(at: screenshotsDirectory.appendingPathComponent(name))
    }

    for name in staleWebsiteImageNames {
        let url = websiteImagesDirectory.appendingPathComponent(name)
        if FileManager.default.fileExists(atPath: url.path) {
            try FileManager.default.removeItem(at: url)
        }
    }
}

func cleanSourceRect(for image: NSImage) -> NSRect {
    let size = image.size
    let croppedHeight = min(size.height, 900)
    let yOffset = max(0, size.height - croppedHeight)
    return NSRect(x: 0, y: yOffset, width: size.width, height: croppedHeight)
}

func drawRealAppShot(_ sourceImage: NSImage, targetSize: NSSize) -> NSImage {
    let output = NSImage(size: targetSize)
    output.lockFocus()
    matteColor.setFill()
    NSRect(origin: .zero, size: targetSize).fill()

    let sourceRect = cleanSourceRect(for: sourceImage)
    let scale = min(targetSize.width / sourceRect.width, targetSize.height / sourceRect.height)
    let drawSize = NSSize(width: sourceRect.width * scale, height: sourceRect.height * scale)
    let drawRect = NSRect(
        x: (targetSize.width - drawSize.width) / 2,
        y: (targetSize.height - drawSize.height) / 2,
        width: drawSize.width,
        height: drawSize.height
    )
    sourceImage.draw(in: drawRect, from: sourceRect, operation: .sourceOver, fraction: 1)
    output.unlockFocus()
    return output
}

func writePNG(_ image: NSImage, to url: URL) throws {
    guard
        let tiff = image.tiffRepresentation,
        let bitmap = NSBitmapImageRep(data: tiff),
        let png = bitmap.representation(using: .png, properties: [:])
    else {
        throw ScreenshotGenerationError.cannotEncodePNG(url.path)
    }
    try png.write(to: url)
}

try removeGeneratedOutputs()

for spec in specs {
    let sourceURL = root.appendingPathComponent(spec.realAppSource)
    guard FileManager.default.fileExists(atPath: sourceURL.path) else {
        throw ScreenshotGenerationError.missingRealAppSource(spec.realAppSource)
    }
    guard let sourceImage = NSImage(contentsOf: sourceURL) else {
        throw ScreenshotGenerationError.cannotLoadRealAppSource(spec.realAppSource)
    }

    let appStoreImage = drawRealAppShot(sourceImage, targetSize: appStoreSize)
    try writePNG(appStoreImage, to: screenshotsDirectory.appendingPathComponent(spec.fileName))

    let websiteImage = drawRealAppShot(sourceImage, targetSize: websiteSize)
    try writePNG(websiteImage, to: websiteImagesDirectory.appendingPathComponent(spec.websiteName))

    print("Generated \(spec.fileName) from real app capture: \(spec.realAppSource) — \(spec.title)")
}
