//
//  ExportConfigurationView.swift
//  SaneVideo
//
//  Extracted from ExportView.swift
//  Contains export preset buttons and manual settings (Resolution, Frame Rate, etc.)
//

import AVFoundation
import SwiftUI

struct ExportConfigurationView: View {
    @Binding var exportSettings: SaneExportSettings
    @Binding var selectedPreset: ExportPreset?
    @Binding var mlEffects: MLExportEffects
    let estimateFileSize: () -> String

    var body: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 14) {
                HelperText(
                    text: "Start with a preset, then override quality or format only when the destination needs something specific.",
                    icon: "slider.horizontal.3"
                )

                // PRESETS ROW with descriptions
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text(String(localized: "export.preset.label", defaultValue: "Preset"))
                            .saneReadableLabel()
                        Spacer()
                        ExportPresetPicker(
                            exportSettings: $exportSettings,
                            selectedPreset: $selectedPreset
                        )
                    }

                    // Enhanced presets: Primary row + Social media row
                    VStack(spacing: 8) {
                        // Primary presets row
                        HStack(spacing: 8) {
                            ExportPresetButton(preset: .youtube4K, icon: ExportPreset.youtube4K.icon, title: "YouTube 4K", selected: selectedPreset == .youtube4K, id: "export.preset.youtube4k") { applyPreset(.youtube4K) }
                            ExportPresetButton(preset: .youtube1080, icon: ExportPreset.youtube1080.icon, title: "YouTube 1080p", selected: selectedPreset == .youtube1080, id: "export.preset.youtube1080") { applyPreset(.youtube1080) }
                            ExportPresetButton(preset: .compressed, icon: ExportPreset.compressed.icon, title: "Small File", selected: selectedPreset == .compressed, id: "export.preset.small") { applyPreset(.compressed) }
                        }

                        // Social media presets row (Creator-friendly)
                        HStack(spacing: 8) {
                            ExportPresetButton(preset: .tiktok, icon: ExportPreset.tiktok.icon, title: "TikTok", selected: selectedPreset == .tiktok, id: "export.preset.tiktok") { applyPreset(.tiktok) }
                            ExportPresetButton(preset: .instagram, icon: ExportPreset.instagram.icon, title: "Instagram", selected: selectedPreset == .instagram, id: "export.preset.instagram") { applyPreset(.instagram) }
                            ExportPresetButton(preset: .twitter, icon: ExportPreset.twitter.icon, title: "Twitter/X", selected: selectedPreset == .twitter, id: "export.preset.twitter") { applyPreset(.twitter) }
                        }
                    }

                    if let description = selectedPreset?.description {
                        HelperText(text: description, icon: "sparkles")
                    }
                }
                .padding(.leading, 4)

                Divider()

                // MANUAL SETTINGS ROW
                HStack(spacing: 20) {
                    VStack(alignment: .leading, spacing: 4) {
                        Label(String(localized: "export.quality.label", defaultValue: "Quality"), systemImage: "dial.high")
                            .saneReadableLabel()

                        Picker("", selection: $exportSettings.resolution) {
                            Text(String(localized: "export.res.uhd", defaultValue: "4K (2160p)")).tag(SaneExportSettings.ExportResolution.uhd4K)
                            Text(String(localized: "export.res.hd", defaultValue: "1080p")).tag(SaneExportSettings.ExportResolution.hd1080)
                            Text(String(localized: "export.res.sd", defaultValue: "720p")).tag(SaneExportSettings.ExportResolution.hd720)
                        }
                        .pickerStyle(.menu)
                        .frame(maxWidth: 120)
                        .accessibilityIdentifier("export.resolution_picker")
                        .accessibilityLabel("Export resolution")
                        .onChange(of: exportSettings.resolution) { _, _ in selectedPreset = .custom }
                        
                        Text("4K keeps product UI crisp. 1080p is the normal default for lighter exports.")
                            .saneReadableSupportText()
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    VStack(alignment: .leading, spacing: 4) {
                        Label(String(localized: "export.format.label", defaultValue: "Format"), systemImage: "film")
                            .saneReadableLabel()

                        Picker("", selection: $exportSettings.codec) {
                            Text(String(localized: "export.codec.h264", defaultValue: "H.264 (Most Compatible)")).tag(AVVideoCodecType.h264)
                            Text(String(localized: "export.codec.hevc", defaultValue: "HEVC (Smaller File)")).tag(AVVideoCodecType.hevc)
                            Text(String(localized: "export.codec.hevc_alpha", defaultValue: "HEVC + Transparency")).tag(AVVideoCodecType.hevcWithAlpha)
                            Text(String(localized: "export.codec.prores", defaultValue: "ProRes (Best for Editing)")).tag(AVVideoCodecType.proRes422)
                        }
                        .pickerStyle(.menu)
                        .frame(maxWidth: 120)
                        .accessibilityIdentifier("export.format_picker")
                        .accessibilityLabel("Export format")
                        .onChange(of: exportSettings.codec) { _, _ in selectedPreset = .custom }

                        Text("H.264 is safest, HEVC is smaller, and ProRes is best when you plan to re-edit the export later.")
                            .saneReadableSupportText()
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    VStack(alignment: .leading, spacing: 4) {
                        Label(String(localized: "export.size.label", defaultValue: "Est. Size"), systemImage: "externaldrive")
                            .saneReadableLabel()

                        Text("\(Int(exportSettings.bitrate / 1_000_000)) Mbps")
                            .saneReadableMeta()
                        Text(estimateFileSize())
                            .saneReadableMeta(monospaced: true)

                        Text("Bitrate is the main size lever. Bigger numbers usually look better, but take more space and time.")
                            .saneReadableSupportText()
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .padding(4)

                Divider()

                // ML Effects Section
                MLEffectsExportSection(mlEffects: $mlEffects)
            }
        }
        .sanePanel(radius: 16, accent: Theme.Colors.accentSoft)
    }

    private func applyPreset(_ preset: ExportPreset) {
        selectedPreset = preset
        switch preset {
        case .youtube4K:
            exportSettings.resolution = .uhd4K
            exportSettings.codec = .hevc
            exportSettings.bitrate = 20_000_000
            exportSettings.frameRate = 60.0
            exportSettings.aspectRatio = nil // Use source aspect (horizontal)
        case .youtube1080:
            exportSettings.resolution = .hd1080
            exportSettings.codec = .h264
            exportSettings.bitrate = 12_000_000
            exportSettings.frameRate = 30.0
            exportSettings.aspectRatio = nil // Use source aspect (horizontal)
        case .tiktok, .instagram:
            // Vertical 9:16 for short-form social platforms
            exportSettings.resolution = .hd1080
            exportSettings.codec = .h264
            exportSettings.bitrate = 8_000_000
            exportSettings.frameRate = 30.0
            exportSettings.aspectRatio = .vertical9x16
        case .twitter:
            // Twitter/X supports vertical but square also common
            exportSettings.resolution = .hd1080
            exportSettings.codec = .h264
            exportSettings.bitrate = 8_000_000
            exportSettings.frameRate = 30.0
            exportSettings.aspectRatio = .vertical9x16
        case .social1080, .facebook:
            // General social - keep horizontal
            exportSettings.resolution = .hd1080
            exportSettings.codec = .h264
            exportSettings.bitrate = 8_000_000
            exportSettings.frameRate = 30.0
            exportSettings.aspectRatio = nil // Use source aspect
        case .compressed:
            exportSettings.resolution = .hd1080
            exportSettings.codec = .hevc
            exportSettings.bitrate = 5_000_000
            exportSettings.frameRate = 30.0
            exportSettings.aspectRatio = nil // Use source aspect
        case .custom:
            break
        }
    }
}

// MARK: - Helper Components

struct ExportPresetButton: View {
    let preset: ExportPreset
    let icon: String
    let title: String
    let selected: Bool
    let id: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 4) {
                Image(systemName: icon)
                    .font(.system(size: 20))
                Text(title)
                    .font(.system(size: Theme.Typography.fontSizeSM, weight: selected ? .semibold : .regular))
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 10)
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(
                        selected
                            ? AnyShapeStyle(
                                LinearGradient(
                                    colors: [Theme.Colors.accentSoft.opacity(0.22), Theme.Colors.accentDeep.opacity(0.16)],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                            )
                            : AnyShapeStyle(
                                LinearGradient(
                                    colors: [Color.white.opacity(0.04), Color.white.opacity(0.02)],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                            )
                    )
            )
            .cornerRadius(6)
            .overlay(
                RoundedRectangle(cornerRadius: 6)
                    .stroke(selected ? Theme.Colors.accentSoft : Color.stone.opacity(0.2), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier(id)
        .accessibilityLabel("\(title) preset\(selected ? ", selected" : "")")
        .help(preset.description)
    }
}
