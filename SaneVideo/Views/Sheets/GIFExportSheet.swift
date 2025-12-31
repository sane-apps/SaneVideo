//
//  GIFExportSheet.swift
//  SaneVideo
//
//  Settings sheet for GIF export with quality/size options
//

import AppKit
import AVFoundation
import SwiftUI

/// Sheet for configuring GIF export settings
struct GIFExportSheet: View {
    @Environment(\.dismiss) private var dismiss

    let videoURL: URL
    let projectName: String
    let clipDuration: Double

    // Settings
    @State private var fps: Int = 10
    @State private var width: Int = 480
    @State private var startTime: Double = 0
    @State private var endTime: Double = 0
    @State private var useFullVideo = true

    // State
    @State private var isExporting = false
    @State private var exportProgress: Double = 0
    @State private var estimatedSize: String = "~1-3 MB"
    @State private var errorMessage: String?
    // SWIFT 6 FIX: Track export task to prevent concurrent exports
    @State private var exportTask: Task<Void, Never>?

    private let fpsOptions = [5, 10, 15, 20, 25]
    private let widthOptions = [320, 480, 640, 720, 1080]

    var body: some View {
        VStack(spacing: 0) {
            SheetHeader(
                title: String(localized: "gif.header.title", defaultValue: "Export as GIF"),
                subtitle: String(localized: "gif.header.subtitle", defaultValue: "Create animated GIF from video"),
                dismissAction: { dismiss() },
                accessibilityID: "gif.sheet.close"
            )

            Divider()

            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    presetsSection
                    Divider()
                    fpsSection
                    widthSection
                    Divider()
                    durationSection
                    EstimateBox(
                        label: String(localized: "gif.size.estimate", defaultValue: "Estimated Size"),
                        value: estimatedSize
                    )

                    if let error = errorMessage {
                        Text(error)
                            .foregroundStyle(.red)
                            .font(.caption)
                    }
                }
                .padding(20)
            }

            Divider()

            SheetFooter(
                actionTitle: String(localized: "gif.action.export", defaultValue: "Export GIF"),
                isLoading: isExporting,
                loadingTitle: String(localized: "gif.action.exporting", defaultValue: "Exporting..."),
                cancelID: "gif.action.cancel",
                actionID: "gif.action.export",
                onCancel: { dismiss() },
                onAction: { exportGIF() }
            )
        }
        .frame(width: 420, height: 520)
        .subtleGlass(radius: 12)
        .onAppear {
            endTime = clipDuration
            updateSizeEstimate()
        }
        .onChange(of: fps) { _, _ in updateSizeEstimate() }
        .onChange(of: width) { _, _ in updateSizeEstimate() }
        .onChange(of: startTime) { _, _ in updateSizeEstimate() }
        .onChange(of: endTime) { _, _ in updateSizeEstimate() }
    }

    // MARK: - Sections

    private var presetsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label(
                String(localized: "gif.presets.header", defaultValue: "Quality Presets"),
                systemImage: "slider.horizontal.below.square.filled.and.square"
            )
            .font(.subheadline.weight(.semibold))

            HStack(spacing: 10) {
                PresetButton(
                    title: String(localized: "gif.preset.social.title", defaultValue: "Social"),
                    subtitle: String(localized: "gif.preset.social.subtitle", defaultValue: "Small, fast"),
                    isSelected: fps == 10 && width == 320,
                    id: "gif.preset.social",
                    action: { fps = 10; width = 320 }
                )
                PresetButton(
                    title: String(localized: "gif.preset.standard.title", defaultValue: "Standard"),
                    subtitle: String(localized: "gif.preset.standard.subtitle", defaultValue: "Balanced"),
                    isSelected: fps == 10 && width == 480,
                    id: "gif.preset.standard",
                    action: { fps = 10; width = 480 }
                )
                PresetButton(
                    title: String(localized: "gif.preset.high.title", defaultValue: "High"),
                    subtitle: String(localized: "gif.preset.high.subtitle", defaultValue: "Smooth"),
                    isSelected: fps == 15 && width == 640,
                    id: "gif.preset.high",
                    action: { fps = 15; width = 640 }
                )
            }
        }
    }

    private var fpsSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(String(localized: "gif.fps.header", defaultValue: "Frame Rate"))
                .font(.caption)

            Picker("", selection: $fps) {
                ForEach(fpsOptions, id: \.self) { option in
                    Text("\(option) FPS").tag(option)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()

            Text(String(localized: "gif.fps.footer.low", defaultValue: "Lower = smaller file"))
                .font(.caption2)
                .foregroundStyle(.tertiary)
        }
    }

    private var widthSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(String(localized: "gif.width.header", defaultValue: "Width"))
                .font(.caption)

            Picker("", selection: $width) {
                ForEach(widthOptions, id: \.self) { option in
                    Text("\(option)px").tag(option)
                }
            }
            .pickerStyle(.menu)
            .labelsHidden()
        }
    }

    private var durationSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Label(String(localized: "gif.duration.header", defaultValue: "Duration"), systemImage: "clock")
                    .font(.subheadline.weight(.semibold))

                Spacer()

                Toggle(String(localized: "gif.duration.full_video", defaultValue: "Full video"), isOn: $useFullVideo)
                    .toggleStyle(.switch)
                    .labelsHidden()
                    .accessibilityIdentifier("gif.duration.full_video")
            }

            if !useFullVideo {
                VStack(spacing: 8) {
                    HStack {
                        Text("Start: \(formatTime(startTime))")
                            .font(.caption.monospacedDigit())
                        Slider(value: $startTime, in: 0...max(0.1, endTime - 0.5))
                            .accessibilityIdentifier("gif.duration.start")
                    }

                    HStack {
                        Text("End: \(formatTime(endTime))")
                            .font(.caption.monospacedDigit())
                        Slider(value: $endTime, in: startTime + 0.5...clipDuration)
                            .accessibilityIdentifier("gif.duration.end")
                    }
                }
            }

            Text("Duration: \(formatTime(useFullVideo ? clipDuration : endTime - startTime))")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    // MARK: - Helpers

    private func formatTime(_ seconds: Double) -> String {
        let mins = Int(seconds) / 60
        let secs = Int(seconds) % 60
        return String(format: "%d:%02d", mins, secs)
    }

    private func updateSizeEstimate() {
        let duration = useFullVideo ? clipDuration : max(0.1, endTime - startTime)
        let height = Double(width) * 9.0 / 16.0
        let rawBytes = Double(width) * height * Double(fps) * duration * 0.1
        let mb = rawBytes / 1_000_000

        if mb < 1 {
            estimatedSize = String(format: "~%.0f KB", mb * 1000)
        } else if mb < 10 {
            estimatedSize = String(format: "~%.1f MB", mb)
        } else {
            estimatedSize = String(format: "~%.0f MB", mb)
        }
    }

    private func exportGIF() {
        // SWIFT 6 FIX: Prevent concurrent exports
        guard !isExporting else { return }
        isExporting = true
        errorMessage = nil

        // Cancel any previous export task
        exportTask?.cancel()
        exportTask = Task {
            do {
                let savePanel = NSSavePanel()
                savePanel.allowedContentTypes = [.gif]
                savePanel.nameFieldStringValue = "\(projectName).gif"

                guard let window = NSApp.keyWindow else { return }
                let response = await savePanel.beginSheetModal(for: window)

                guard response == .OK, let url = savePanel.url else {
                    await MainActor.run { isExporting = false }
                    return
                }

                let ffmpeg = ServiceContainer.shared.ffmpegService
                guard await ffmpeg.isAvailable else {
                    await MainActor.run {
                        errorMessage = String(
                            localized: "gif.error.ffmpeg_missing",
                            defaultValue: "FFmpeg not installed. Run: brew install ffmpeg"
                        )
                        isExporting = false
                    }
                    return
                }

                let start = useFullVideo ? nil : startTime
                let duration = useFullVideo ? nil : (endTime - startTime)

                try await ffmpeg.exportAsGIF(
                    inputURL: videoURL,
                    outputURL: url,
                    fps: fps,
                    width: width,
                    startTime: start,
                    duration: duration
                )

                await MainActor.run {
                    isExporting = false
                    ServiceContainer.shared.toastManager.show(
                        String(localized: "gif.toast.exported", defaultValue: "GIF exported!")
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
}

// MARK: - Preset Button

private struct PresetButton: View {
    let title: String
    let subtitle: String
    let isSelected: Bool
    let id: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 2) {
                Text(title)
                    .fontWeight(.semibold)
                Text(subtitle)
                    .foregroundStyle(.secondary)
            }
            .font(.caption2)
        }
        .buttonStyle(.bordered)
        .tint(isSelected ? .blue : .secondary)
        .accessibilityIdentifier(id)
    }
}
