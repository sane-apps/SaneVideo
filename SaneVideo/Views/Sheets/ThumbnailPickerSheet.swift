//
//  ThumbnailPickerSheet.swift
//  SaneVideo
//
//  Full thumbnail creation studio using extracted helpers.
//

import AppKit
import AVFoundation
import SwiftUI

/// Sheet for picking and styling thumbnails
struct ThumbnailPickerSheet: View {
    @Environment(\.dismiss) private var dismiss

    let videoURL: URL
    let projectName: String
    let onSelect: (NSImage) -> Void

    // Frame selection
    @State private var candidates: [ThumbnailCandidate] = []
    @State private var selectedIndex: Int = 0
    @State private var isLoading = true
    @State private var customTime: Double = 0
    @State private var duration: Double = 1
    @State private var customImage: NSImage?
    @State private var showCustomScrubber = false

    // Styling
    @State private var selectedStyle: ThumbnailStyle = .original
    @State private var saturation: Double = 1.0
    @State private var brightness: Double = 0.0
    @State private var contrast: Double = 1.0
    @State private var showTextOverlay = false
    @State private var overlayText: String = ""

    @State private var errorMessage: String?
    @State private var styledPreview: NSImage?

    var body: some View {
        VStack(spacing: 0) {
            SheetHeader(
                title: String(localized: "thumbnail.header.title", defaultValue: "Thumbnail Studio"),
                subtitle: String(localized: "thumbnail.header.subtitle", defaultValue: "Create an eye-catching thumbnail"),
                icon: "photo.on.rectangle.angled",
                dismissAction: { dismiss() },
                accessibilityID: "thumbnail.sheet.close"
            )

            Divider()

            if isLoading {
                loadingView
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 20) {
                        FeatureCallout(
                            title: "Pick the frame, then polish it",
                            message: "Use AI Pick for quick wins, switch to Custom Frame when you need a specific moment, and keep the text readable.",
                            icon: "photo.badge.sparkles"
                        )
                        previewSection
                        Divider()
                        candidatesSection
                        Divider()
                        styleSection
                        advancedSection
                        Divider()
                        textOverlaySection
                    }
                    .padding(20)
                }
            }

            Divider()
            footer
        }
        .frame(width: 600, height: 700)
        .sanePanel(radius: 18, emphasized: true, accent: Theme.Colors.accentSoft)
        .task { await loadCandidates() }
        .onChange(of: selectedIndex) { _, _ in updateStyledPreview() }
        .onChange(of: selectedStyle) { _, _ in applyPreset(); updateStyledPreview() }
        .onChange(of: saturation) { _, _ in updateStyledPreview() }
        .onChange(of: brightness) { _, _ in updateStyledPreview() }
        .onChange(of: contrast) { _, _ in updateStyledPreview() }
        .onChange(of: showTextOverlay) { _, _ in updateStyledPreview() }
        .onChange(of: overlayText) { _, _ in updateStyledPreview() }
    }

    // MARK: - Sections

    private var loadingView: some View {
        VStack(spacing: 12) {
            ProgressView()
            Text(String(localized: "thumbnail.loading", defaultValue: "Analyzing video for best frames..."))
                .saneReadableSupportText()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var previewSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label(
                String(localized: "thumbnail.preview.header", defaultValue: "Preview"),
                systemImage: "eye"
            )
            .saneReadableSectionTitle()

            HelperText(
                text: "Check crop, contrast, and text placement here before you save or copy the thumbnail.",
                icon: "eye.fill"
            )

            ZStack {
                if let preview = styledPreview {
                    Image(nsImage: preview)
                        .resizable()
                        .aspectRatio(16 / 9, contentMode: .fit)
                        .cornerRadius(12)
                        .overlay(
                            RoundedRectangle(cornerRadius: 12)
                                .stroke(Color.white.opacity(0.2), lineWidth: 1)
                        )
                        .shadow(radius: 10)
                } else if !candidates.isEmpty {
                    Image(nsImage: candidates[selectedIndex].image)
                        .resizable()
                        .aspectRatio(16 / 9, contentMode: .fit)
                        .cornerRadius(12)
                }
            }
            .frame(height: 180)
            .frame(maxWidth: .infinity)
        }
    }

    private var candidatesSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Label(
                    String(localized: "thumbnail.frames.header", defaultValue: "Select Frame"),
                    systemImage: "film.stack"
                )
                .saneReadableSectionTitle()
                Spacer()
                Button {
                    showCustomScrubber.toggle()
                } label: {
                    Text(
                        showCustomScrubber
                            ? String(localized: "thumbnail.action.use_ai", defaultValue: "Use AI Pick")
                            : String(localized: "thumbnail.action.use_custom", defaultValue: "Custom Frame")
                    )
                    .font(Theme.Typography.meta)
                }
                .buttonStyle(.bordered)
                .accessibilityIdentifier("thumbnail.action.toggle_custom")
            }

            HelperText(
                text: showCustomScrubber
                    ? "Custom Frame lets you scrub to the exact moment you want."
                    : "AI Pick surfaces frames that look promising for a thumbnail.",
                icon: showCustomScrubber ? "slider.horizontal.below.rectangle" : "sparkles"
            )

            if showCustomScrubber {
                HStack {
                    Text(formatTime(customTime))
                        .saneReadableMeta(monospaced: true)
                    Slider(value: $customTime, in: 0...duration)
                        .accessibilityIdentifier("thumbnail.custom.scrubber")
                        .onChange(of: customTime) { _, newValue in
                            Task { await updateCustomFrame(at: newValue) }
                        }
                    Text(formatTime(duration))
                        .saneReadableMeta(monospaced: true)
                }
            } else {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 10) {
                        ForEach(Array(candidates.enumerated()), id: \.offset) { index, candidate in
                            ThumbnailCard(
                                image: candidate.image,
                                label: candidate.label,
                                score: candidate.score,
                                isSelected: selectedIndex == index,
                                id: "thumbnail.card.\(index)",
                                onSelect: { selectedIndex = index }
                            )
                        }
                    }
                }
            }
        }
    }

    private var styleSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label(
                String(localized: "thumbnail.styles.header", defaultValue: "Style Presets"),
                systemImage: "paintpalette"
            )
            .saneReadableSectionTitle()

            HelperText(
                text: selectedStyle.description,
                icon: selectedStyle.icon
            )

            LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 6), spacing: 8) {
                ForEach(ThumbnailStyle.allCases) { style in
                    Button { selectedStyle = style } label: {
                        VStack(spacing: 4) {
                            Image(systemName: style.icon)
                                .font(.title3)
                            Text(style.displayName)
                                .font(Theme.Typography.meta)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 8)
                        .background(
                            RoundedRectangle(cornerRadius: 8)
                                .fill(selectedStyle == style ? Color.accentColor.opacity(0.2) : Color.white.opacity(0.05))
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 8)
                                .stroke(selectedStyle == style ? Color.accentColor : Color.clear, lineWidth: 1)
                        )
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("thumbnail.style.\(style.rawValue)")
                }
            }
        }
    }

    private var advancedSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label(
                String(localized: "thumbnail.adjust.header", defaultValue: "Fine Tune"),
                systemImage: "slider.horizontal.3"
            )
            .saneReadableSectionTitle()

            HelperText(
                text: "Use these sliders for small corrections after you pick a style preset.",
                icon: "dial.high.fill"
            )

            VStack(spacing: 8) {
                sliderRow(
                    String(localized: "thumbnail.adjust.saturation", defaultValue: "Saturation"),
                    value: $saturation,
                    range: 0...2,
                    format: "%.1f",
                    id: "thumbnail.adjust.saturation"
                )
                sliderRow(
                    String(localized: "thumbnail.adjust.brightness", defaultValue: "Brightness"),
                    value: $brightness,
                    range: -0.5...0.5,
                    format: "%.2f",
                    id: "thumbnail.adjust.brightness"
                )
                sliderRow(
                    String(localized: "thumbnail.adjust.contrast", defaultValue: "Contrast"),
                    value: $contrast,
                    range: 0.5...2,
                    format: "%.1f",
                    id: "thumbnail.adjust.contrast"
                )
            }

            Button(String(localized: "thumbnail.action.reset", defaultValue: "Reset")) {
                saturation = 1.0
                brightness = 0.0
                contrast = 1.0
                selectedStyle = .original
            }
            .font(Theme.Typography.meta)
            .accessibilityIdentifier("thumbnail.action.reset")
        }
    }

    private func sliderRow(
        _ title: String,
        value: Binding<Double>,
        range: ClosedRange<Double>,
        format: String,
        id: String
    ) -> some View {
        HStack {
            Text(title)
                .saneReadableLabel()
                .frame(width: 80, alignment: .leading)
            Slider(value: value, in: range)
                .accessibilityIdentifier(id)
            Text(String(format: format, value.wrappedValue))
                .saneReadableMeta(monospaced: true)
                .frame(width: 44)
        }
    }

    private var textOverlaySection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Label(
                    String(localized: "thumbnail.overlay.header", defaultValue: "Text Overlay"),
                    systemImage: "textformat"
                )
                .saneReadableSectionTitle()
                Spacer()
                Toggle("", isOn: $showTextOverlay)
                    .toggleStyle(.switch)
                    .labelsHidden()
                    .accessibilityIdentifier("thumbnail.overlay.toggle")
            }

            HelperText(
                text: "Turn this on only when the frame still needs a short, readable headline.",
                icon: "textformat.size"
            )

            if showTextOverlay {
                TextField(
                    String(localized: "thumbnail.overlay.placeholder", defaultValue: "Enter title text..."),
                    text: $overlayText
                )
                .textFieldStyle(.roundedBorder)
                .accessibilityIdentifier("thumbnail.overlay.text")
                Text(String(localized: "thumbnail.overlay.footer", defaultValue: "Text will appear at bottom of thumbnail"))
                    .saneReadableSupportText()
            }
        }
    }

    private var footer: some View {
        HStack {
            Menu {
                Button(String(localized: "thumbnail.action.copy", defaultValue: "Copy to Clipboard")) {
                    copyToClipboard()
                }
                Button(String(localized: "thumbnail.action.save_png", defaultValue: "Save as PNG...")) {
                    saveAsFile(.png)
                }
                Button(String(localized: "thumbnail.action.save_jpeg", defaultValue: "Save as JPEG...")) {
                    saveAsFile(.jpeg)
                }
            } label: {
                Label(String(localized: "thumbnail.footer.options", defaultValue: "Options"), systemImage: "ellipsis.circle")
            }
            .accessibilityIdentifier("thumbnail.action.options")

            Spacer()

            Button(String(localized: "thumbnail.action.cancel", defaultValue: "Cancel")) {
                dismiss()
            }
            .keyboardShortcut(.cancelAction)
            .accessibilityIdentifier("thumbnail.action.cancel")

            Button { useSelected() } label: {
                Label(
                    String(localized: "thumbnail.action.use", defaultValue: "Use Thumbnail"),
                    systemImage: "checkmark.circle.fill"
                )
            }
            .buttonStyle(.borderedProminent)
            .keyboardShortcut(.defaultAction)
            .accessibilityIdentifier("thumbnail.action.use")
        }
        .padding(16)
    }

    // MARK: - Logic

    private func applyPreset() {
        let preset = ThumbnailStylingService.presetValues(for: selectedStyle)
        saturation = preset.saturation
        brightness = preset.brightness
        contrast = preset.contrast
    }

    private func updateStyledPreview() {
        let sourceImage: NSImage
        if showCustomScrubber, let custom = customImage {
            sourceImage = custom
        } else if !candidates.isEmpty {
            sourceImage = candidates[selectedIndex].image
        } else {
            return
        }

        guard var result = ThumbnailStylingService.applyStyle(
            to: sourceImage,
            style: selectedStyle,
            saturation: saturation,
            brightness: brightness,
            contrast: contrast
        ) else { return }

        if showTextOverlay && !overlayText.isEmpty {
            result = ThumbnailStylingService.addTextOverlay(to: result, text: overlayText)
        }
        styledPreview = result
    }

    private func loadCandidates() async {
        do {
            let result = try await ThumbnailFrameLoader.loadCandidates(from: videoURL)
            await MainActor.run {
                self.candidates = result.candidates
                self.duration = result.duration
                self.customTime = result.duration * 0.5
                self.overlayText = projectName
                self.isLoading = false
                updateStyledPreview()
            }
        } catch {
            await MainActor.run {
                self.errorMessage = String(
                    localized: "thumbnail.error.load_failed",
                    defaultValue: "Failed to load video"
                )
                self.isLoading = false
            }
        }
    }

    private func updateCustomFrame(at time: Double) async {
        do {
            let image = try await ThumbnailFrameLoader.getFrame(from: videoURL, at: time)
            await MainActor.run {
                self.customImage = image
                updateStyledPreview()
            }
        } catch {}
    }

    // MARK: - Export

    private func getFinalImage() -> NSImage? {
        styledPreview ?? (candidates.isEmpty ? nil : candidates[selectedIndex].image)
    }

    private func useSelected() {
        if let image = getFinalImage() { onSelect(image) }
        dismiss()
    }

    private func copyToClipboard() {
        guard let image = getFinalImage() else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.writeObjects([image])
        ServiceContainer.shared.toastManager.show(
            String(localized: "thumbnail.toast.copied", defaultValue: "Copied to clipboard!")
        )
        dismiss()
    }

    private func saveAsFile(_ format: NSBitmapImageRep.FileType) {
        guard let image = getFinalImage() else { return }
        let savePanel = NSSavePanel()
        savePanel.allowedContentTypes = format == .png ? [.png] : [.jpeg]
        savePanel.nameFieldStringValue = "\(projectName)_thumbnail.\(format == .png ? "png" : "jpg")"

        savePanel.begin { response in
            guard response == .OK, let url = savePanel.url else { return }
            if let tiffData = image.tiffRepresentation,
               let bitmap = NSBitmapImageRep(data: tiffData),
               let data = bitmap.representation(using: format, properties: [:]) {
                try? data.write(to: url)
                ServiceContainer.shared.toastManager.show(
                    String(localized: "thumbnail.toast.saved", defaultValue: "Saved!")
                )
                dismiss()
            }
        }
    }

    private func formatTime(_ seconds: Double) -> String {
        String(format: "%d:%02d", Int(seconds) / 60, Int(seconds) % 60)
    }
}
