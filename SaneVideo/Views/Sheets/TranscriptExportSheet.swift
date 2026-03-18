//
//  TranscriptExportSheet.swift
//  SaneVideo
//
//  Export captions as PDF transcript, SRT, VTT, or plain text
//

import AppKit
import CoreMedia
import SwiftUI
import UniformTypeIdentifiers

/// Format options for transcript export
enum TranscriptFormat: String, CaseIterable, Identifiable {
    case pdf = "transcript.format.pdf"
    case srt = "transcript.format.srt"
    case vtt = "transcript.format.vtt"
    case txt = "transcript.format.txt"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .pdf: return String(localized: "transcript.format.pdf", defaultValue: "PDF Study Guide")
        case .srt: return String(localized: "transcript.format.srt", defaultValue: "SRT Subtitles")
        case .vtt: return String(localized: "transcript.format.vtt", defaultValue: "WebVTT")
        case .txt: return String(localized: "transcript.format.txt", defaultValue: "Plain Text")
        }
    }

    var icon: String {
        switch self {
        case .pdf: return "doc.richtext"
        case .srt: return "captions.bubble"
        case .vtt: return "globe"
        case .txt: return "doc.plaintext"
        }
    }

    var fileExtension: String {
        switch self {
        case .pdf: return "pdf"
        case .srt: return "srt"
        case .vtt: return "vtt"
        case .txt: return "txt"
        }
    }

    var contentType: UTType {
        switch self {
        case .pdf: return .pdf
        case .srt, .vtt, .txt: return .plainText
        }
    }
}

/// Sheet for configuring transcript export
struct TranscriptExportSheet: View {
    @Environment(\.dismiss) private var dismiss

    let captions: [Caption]
    let projectName: String

    @State private var selectedFormat: TranscriptFormat = .pdf
    @State private var includeTimestamps = true
    @State private var isExporting = false
    @State private var errorMessage: String?

    var body: some View {
        VStack(spacing: 0) {
            SheetHeader(
                title: String(localized: "transcript.header.title", defaultValue: "Export Transcript"),
                subtitle: "\(captions.count) captions",
                dismissAction: { dismiss() },
                accessibilityID: "transcript.sheet.close"
            )

            Divider()

            VStack(alignment: .leading, spacing: 20) {
                HelperText(
                    text: "Choose a transcript format based on where it is going next. PDF is best for notes, SRT and VTT are for subtitles, and TXT is plain copy.",
                    icon: "doc.text.fill"
                )

                formatSection
                Divider()
                optionsSection
                previewSection

                if let error = errorMessage {
                    Text(error)
                        .foregroundStyle(.red)
                        .font(.caption)
                }
            }
            .padding(20)

            Divider()

            SheetFooter(
                actionTitle: String(localized: "transcript.action.export", defaultValue: "Export") +
                    " \(selectedFormat.fileExtension.uppercased())",
                isLoading: isExporting,
                loadingTitle: String(localized: "transcript.action.exporting", defaultValue: "Exporting..."),
                isDisabled: captions.isEmpty,
                cancelID: "transcript.action.cancel",
                actionID: "transcript.action.export",
                onCancel: { dismiss() },
                onAction: { exportTranscript() }
            )
        }
        .frame(width: 450, height: 480)
        .subtleGlass(radius: 12)
    }

    // MARK: - Sections

    private var formatSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label(
                String(localized: "transcript.format.header", defaultValue: "Format"),
                systemImage: "doc.badge.gearshape"
            )
            .font(.subheadline.weight(.semibold))

            HelperText(
                text: "Pick PDF when a human will read it, or subtitle formats when another editor or player needs the timing data.",
                icon: "square.and.arrow.down"
            )

            Picker("", selection: $selectedFormat) {
                ForEach(TranscriptFormat.allCases) { format in
                    Label(format.displayName, systemImage: format.icon).tag(format)
                }
            }
            .pickerStyle(.menu)
            .labelsHidden()
        }
    }

    private var optionsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label(
                String(localized: "transcript.options.header", defaultValue: "Options"),
                systemImage: "slider.horizontal.3"
            )
            .font(.subheadline.weight(.semibold))

            Toggle(
                String(localized: "transcript.options.timestamps", defaultValue: "Include timestamps"),
                isOn: $includeTimestamps
            )
            .font(.caption)
            .accessibilityIdentifier("transcript.options.timestamps")
            .help("Shows the timing for each line when the selected format supports it.")

            Text(optionsDescription)
                .font(.caption)
                .foregroundStyle(Color.stone)

            HelperText(
                text: "Timestamps make review and editing easier. Turn them off only when you want cleaner reader-facing plain text.",
                icon: "clock.badge.checkmark"
            )
        }
    }

    private var optionsDescription: String {
        switch selectedFormat {
        case .pdf:
            return String(
                localized: "transcript.description.pdf",
                defaultValue: "Creates a formatted study guide with title, date, and timestamped captions."
            )
        case .srt:
            return String(
                localized: "transcript.description.srt",
                defaultValue: "SubRip format, compatible with YouTube, Premiere, Final Cut Pro."
            )
        case .vtt:
            return String(
                localized: "transcript.description.vtt",
                defaultValue: "WebVTT format for web video players and HTML5."
            )
        case .txt:
            return String(
                localized: "transcript.description.txt",
                defaultValue: "Simple plain text, one caption per line."
            )
        }
    }

    private var previewSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label(
                String(localized: "transcript.preview.header", defaultValue: "Preview"),
                systemImage: "eye"
            )
            .font(.subheadline.weight(.semibold))

            ScrollView {
                Text(generatePreview())
                    .font(.system(.caption, design: .monospaced))
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(height: 100)
            .padding(8)
            .background(Color.black.opacity(0.2))
            .cornerRadius(8)

            HelperText(
                text: "This preview shows the first few lines so you can confirm the format before saving the full export.",
                icon: "eye.fill"
            )
        }
    }

    // MARK: - Helpers

    private func generatePreview() -> String {
        let preview = captions.prefix(3)

        switch selectedFormat {
        case .pdf:
            return preview.map { caption in
                let time = formatTime(caption.startTime)
                return includeTimestamps ? "[\(time)] \(caption.text)" : caption.text
            }.joined(separator: "\n")

        case .srt:
            return preview.enumerated().map { index, caption in
                """
                \(index + 1)
                \(formatSRTTime(caption.startTime)) --> \(formatSRTTime(caption.endTime))
                \(caption.text)
                """
            }.joined(separator: "\n\n")

        case .vtt:
            var result = "WEBVTT\n\n"
            result += preview.map { caption in
                "\(formatVTTTime(caption.startTime)) --> \(formatVTTTime(caption.endTime))\n\(caption.text)"
            }.joined(separator: "\n\n")
            return result

        case .txt:
            return preview.map { $0.text }.joined(separator: "\n")
        }
    }

    private func formatTime(_ time: CMTime) -> String {
        let seconds = CMTimeGetSeconds(time)
        let mins = Int(seconds) / 60
        let secs = Int(seconds) % 60
        return String(format: "%02d:%02d", mins, secs)
    }

    private func formatSRTTime(_ time: CMTime) -> String {
        let seconds = CMTimeGetSeconds(time)
        let hrs = Int(seconds) / 3600
        let mins = (Int(seconds) % 3600) / 60
        let secs = Int(seconds) % 60
        let ms = Int((seconds.truncatingRemainder(dividingBy: 1)) * 1000)
        return String(format: "%02d:%02d:%02d,%03d", hrs, mins, secs, ms)
    }

    private func formatVTTTime(_ time: CMTime) -> String {
        let seconds = CMTimeGetSeconds(time)
        let hrs = Int(seconds) / 3600
        let mins = (Int(seconds) % 3600) / 60
        let secs = Int(seconds) % 60
        let ms = Int((seconds.truncatingRemainder(dividingBy: 1)) * 1000)
        return String(format: "%02d:%02d:%02d.%03d", hrs, mins, secs, ms)
    }

    private func exportTranscript() {
        isExporting = true
        errorMessage = nil

        Task {
            do {
                let savePanel = NSSavePanel()
                savePanel.allowedContentTypes = [selectedFormat.contentType]
                savePanel.nameFieldStringValue = "\(projectName).\(selectedFormat.fileExtension)"

                guard let window = NSApp.keyWindow else { return }
                let response = await savePanel.beginSheetModal(for: window)

                guard response == .OK, let url = savePanel.url else {
                    await MainActor.run { isExporting = false }
                    return
                }

                if selectedFormat == .pdf {
                    let pdfData = try generatePDFData()
                    try pdfData.write(to: url)
                } else {
                    let content = generateFullContent()
                    try content.write(to: url, atomically: true, encoding: .utf8)
                }

                await MainActor.run {
                    isExporting = false
                    ServiceContainer.shared.toastManager.show(
                        String(localized: "transcript.toast.exported", defaultValue: "Transcript exported!")
                    )
                    NSWorkspace.shared.activateFileViewerSelecting([url])
                    dismiss()
                }
            } catch {
                await MainActor.run {
                    isExporting = false
                    errorMessage = error.localizedDescription
                }
            }
        }
    }

    private func generateFullContent() -> String {
        switch selectedFormat {
        case .pdf, .txt:
            return captions.map { caption in
                if includeTimestamps {
                    let time = formatTime(caption.startTime)
                    return "[\(time)] \(caption.text)"
                } else {
                    return caption.text
                }
            }.joined(separator: "\n")

        case .srt:
            return captions.enumerated().map { index, caption in
                """
                \(index + 1)
                \(formatSRTTime(caption.startTime)) --> \(formatSRTTime(caption.endTime))
                \(caption.text)
                """
            }.joined(separator: "\n\n")

        case .vtt:
            var result = "WEBVTT\n\n"
            result += captions.map { caption in
                "\(formatVTTTime(caption.startTime)) --> \(formatVTTTime(caption.endTime))\n\(caption.text)"
            }.joined(separator: "\n\n")
            return result
        }
    }

    private func generatePDFData() throws -> Data {
        let pdfData = NSMutableData()
        var pageBounds = CGRect(x: 0, y: 0, width: 595.2, height: 841.8)

        guard let consumer = CGDataConsumer(data: pdfData as CFMutableData),
              let context = CGContext(consumer: consumer, mediaBox: &pageBounds, nil)
        else {
            throw PDFError.generationFailed
        }

        func beginPage() {
            context.beginPDFPage(nil as CFDictionary?)
        }

        @discardableResult
        func drawText(_ text: String, font: NSFont, x: CGFloat, y: CGFloat) -> CGFloat {
            let attributes: [NSAttributedString.Key: Any] = [
                .font: font,
                .foregroundColor: NSColor.black
            ]
            let attributedString = NSAttributedString(string: text, attributes: attributes)
            let size = attributedString.size()
            let textY = y - size.height

            NSGraphicsContext.current = NSGraphicsContext(cgContext: context, flipped: false)
            attributedString.draw(at: CGPoint(x: x, y: textY))
            return size.height + 8
        }

        let margin: CGFloat = 50
        var cursorY: CGFloat = pageBounds.height - margin

        beginPage()
        cursorY -= drawText(projectName, font: .boldSystemFont(ofSize: 22), x: margin, y: cursorY)
        cursorY -= drawText("Transcript Export", font: .boldSystemFont(ofSize: 16), x: margin, y: cursorY)
        cursorY -= drawText(
            "Generated on \(DateFormatter.localizedString(from: .now, dateStyle: .medium, timeStyle: .short))",
            font: .systemFont(ofSize: 11),
            x: margin,
            y: cursorY
        )
        cursorY -= 20

        for caption in captions {
            if cursorY < margin + 24 {
                context.endPDFPage()
                beginPage()
                cursorY = pageBounds.height - margin
            }

            let line: String
            if includeTimestamps {
                line = "[\(formatTime(caption.startTime))] \(caption.text)"
            } else {
                line = caption.text
            }

            cursorY -= drawText(line, font: .systemFont(ofSize: 12), x: margin, y: cursorY)
        }

        context.endPDFPage()
        context.closePDF()
        return pdfData as Data
    }
}

// MARK: - Format Button

private struct FormatButton: View {
    let format: TranscriptFormat
    let isSelected: Bool
    let onSelect: () -> Void

    var body: some View {
        Button(action: onSelect) {
            HStack {
                Image(systemName: format.icon)
                    .font(.title3)
                    .frame(width: 24)

                VStack(alignment: .leading, spacing: 2) {
                    Text(format.displayName)
                        .font(.caption.weight(.medium))
                    Text(".\(format.fileExtension)")
                        .font(.caption2)
                        .foregroundStyle(Color.stone)
                }

                Spacer()

                if isSelected {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(Color.accentColor)
                }
            }
            .padding(10)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(isSelected ? Color.accentColor.opacity(0.15) : Color.white.opacity(0.05))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(isSelected ? Color.accentColor : Color.white.opacity(0.1), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("transcript.format.\(format.rawValue).button")
    }
}
