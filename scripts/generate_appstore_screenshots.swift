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
        websiteName: "sanevideo-meeting-workflow.jpg",
        title: "Edit meeting footage locally",
        realAppSource: "outputs/appstore-real-captures/01-editor-meeting.png"
    ),
    RealShotSpec(
        fileName: "appstore-02-captions-dark-mac.png",
        websiteName: "sanevideo-captions-transcribing.jpg",
        title: "Transcribe captions locally",
        realAppSource: "outputs/appstore-real-captures/04-inspector-magic-fix-varied.png"
    ),
    RealShotSpec(
        fileName: "appstore-03-review-phone-dark-mac.png",
        websiteName: "sanevideo-review-phone.jpg",
        title: "Review phone footage before sharing",
        realAppSource: "outputs/appstore-real-captures/03-editor-phone.png"
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
    case cannotEncodeImage(String)
    case duplicateRealAppSources([String])

    var description: String {
        switch self {
        case .missingRealAppSource(let path):
            return "Missing real SaneVideo app capture: \(path). Do not generate synthetic UI; capture the actual app with sample media loaded."
        case .cannotLoadRealAppSource(let path):
            return "Could not load real SaneVideo app capture: \(path)."
        case .cannotEncodePNG(let path):
            return "Could not encode PNG: \(path)."
        case .cannotEncodeImage(let path):
            return "Could not encode website image: \(path)."
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

let validatedSources: [(spec: RealShotSpec, image: NSImage)] = try specs.map { spec in
    let sourceURL = root.appendingPathComponent(spec.realAppSource)
    guard FileManager.default.fileExists(atPath: sourceURL.path) else {
        throw ScreenshotGenerationError.missingRealAppSource(spec.realAppSource)
    }
    guard let sourceImage = NSImage(contentsOf: sourceURL) else {
        throw ScreenshotGenerationError.cannotLoadRealAppSource(spec.realAppSource)
    }
    return (spec, sourceImage)
}

let staleWebsiteImageNames = [
    "sanevideo-actual-edit-workflow.jpg",
    "sanevideo-actual-edit-workflow.png",
    "sanevideo-recording.jpg",
    "sanevideo-recording.png",
    "sanevideo-recording-complete.png",
    "sanevideo-captions-demo-pack.jpg",
    "sanevideo-captions-demo-pack.png",
    "sanevideo-export.jpg",
    "sanevideo-export.png",
    "sanevideo-inspector-tools.jpg",
    "sanevideo-inspector-tools.png",
    "sanevideo-magic-fix.jpg",
    "sanevideo-magic-fix.png",
    "sanevideo-captions-transcribing.png",
    "sanevideo-captions-transcribing.jpg",
    "sanevideo-review-phone.png",
    "sanevideo-review-phone.jpg",
    "sanevideo-meeting-workflow.jpg"
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

func writeJPEG(_ image: NSImage, to url: URL) throws {
    guard
        let tiff = image.tiffRepresentation,
        let bitmap = NSBitmapImageRep(data: tiff),
        let jpeg = bitmap.representation(using: .jpeg, properties: [.compressionFactor: 0.88])
    else {
        throw ScreenshotGenerationError.cannotEncodeImage(url.path)
    }
    try jpeg.write(to: url)
}

try removeGeneratedOutputs()

for (spec, sourceImage) in validatedSources {
    let appStoreImage = drawRealAppShot(sourceImage, targetSize: appStoreSize)
    try writePNG(appStoreImage, to: screenshotsDirectory.appendingPathComponent(spec.fileName))

    let websiteImage = drawRealAppShot(sourceImage, targetSize: websiteSize)
    try writeJPEG(websiteImage, to: websiteImagesDirectory.appendingPathComponent(spec.websiteName))

    print("Generated \(spec.fileName) from real app capture: \(spec.realAppSource) — \(spec.title)")
}
