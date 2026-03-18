//
//  PDFGeneratorService.swift
//  SaneVideo
//
//  Created by SaneVideo Refactor
//

import Combine
import CoreMedia
import Foundation
import PDFKit

protocol PDFGeneratorServiceProtocol: Actor {
    func generateStudyGuide(for project: VideoProject, outputURL: URL) async throws
    func generateStudyGuideData(for project: VideoProject) throws -> Data
}

enum PDFError: Error, LocalizedError {
    case generationFailed
    case fileSaveFailed

    var errorDescription: String? {
        switch self {
        case .generationFailed: return "Failed to generate PDF context."
        case .fileSaveFailed: return "Failed to save PDF file."
        }
    }
}

actor PDFGeneratorService: PDFGeneratorServiceProtocol {

    init() {}

    func generateStudyGuide(for project: VideoProject, outputURL: URL) async throws {
        let pdfData = try generateStudyGuideData(for: project)
        try pdfData.write(to: outputURL)
        await MainActor.run {
            AppLogger.export.info(" PDF Generated at: \(outputURL.path)")
        }
    }

    func generateStudyGuideData(for project: VideoProject) throws -> Data {
        let pdfData = NSMutableData()
        var pageBounds = CGRect(x: 0, y: 0, width: 595.2, height: 841.8)

        guard let consumer = CGDataConsumer(data: pdfData as CFMutableData),
              let context = CGContext(consumer: consumer, mediaBox: &pageBounds, nil)
        else {
            throw PDFError.generationFailed
        }

        drawContent(in: context, project: project, pageBounds: pageBounds)

        context.closePDF()
        return pdfData as Data
    }

    private func drawContent(in context: CGContext, project: VideoProject, pageBounds: CGRect) {
        // Helper to start new page
        func startPage() {
            context.beginPDFPage(nil as CFDictionary?)
            // Flip context for Core Text if needed, but let's try standard coordinates first.
            // In PDF (0,0) is bottom-left.
        }

        startPage()

        let margin: CGFloat = 50
        var cursorY: CGFloat = pageBounds.height - margin // Start from top

        func drawText(_ text: String, font: NSFont, x: CGFloat, y: CGFloat) -> CGFloat {
            let attributes: [NSAttributedString.Key: Any] = [
                .font: font,
                .foregroundColor: NSColor.black
            ]
            let attributedString = NSAttributedString(string: text, attributes: attributes)
            let size = attributedString.size()

            // Calculate bottom-left Y for the text line
            let textY = y - size.height

            // Draw
            // NSAttributedString.draw(at:) draws in the current context.
            // We need to ensure the context is set up for NSGraphicsContext
            NSGraphicsContext.current = NSGraphicsContext(cgContext: context, flipped: false)
            attributedString.draw(at: CGPoint(x: x, y: textY))

            return size.height + 10 // Line spacing
        }

        // Draw Title
        cursorY -= drawText(project.name, font: .boldSystemFont(ofSize: 24), x: margin, y: cursorY)
        cursorY -= 20

        // Draw Date
        let dateFormatter = DateFormatter()
        dateFormatter.dateStyle = .medium
        let dateString = "Generated on: \(dateFormatter.string(from: Date()))"
        cursorY -= drawText(dateString, font: .systemFont(ofSize: 12), x: margin, y: cursorY)
        cursorY -= 30

        // Draw Section Header
        cursorY -= drawText("Transcript", font: .boldSystemFont(ofSize: 18), x: margin, y: cursorY)
        cursorY -= 10

        // Draw Captions
        // Collect all clips from all tracks, sorted by timeline position
        let allClips = project.timeline.tracks.flatMap { $0.clips }.sorted { $0.startTime < $1.startTime }

        for clip in allClips {
            for caption in clip.captions {
                // Check for page break
                if cursorY < margin {
                    context.endPDFPage()
                    startPage()
                    cursorY = pageBounds.height - margin
                }

                let timeString = String(format: "[%02d:%02d]", Int(caption.startTime.seconds) / 60, Int(caption.startTime.seconds) % 60)
                let captionLine = "\(timeString) \(caption.text)"
                cursorY -= drawText(captionLine, font: .systemFont(ofSize: 12), x: margin, y: cursorY)
            }
        }

        context.endPDFPage()
    }
}
