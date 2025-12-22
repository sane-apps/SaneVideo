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
    let estimateFileSize: () -> String

    var body: some View {
        GroupBox {
            VStack(spacing: 12) {
                // PRESETS ROW with descriptions
                VStack(alignment: .leading, spacing: 8) {
                    Text(String(localized: "export.preset.label", defaultValue: "Preset"))
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    HStack(spacing: 8) {
                        ExportPresetButton(preset: .youtube4K, icon: "4k.tv", title: "YouTube 4K", selected: selectedPreset == .youtube4K, id: "export.preset.youtube4k") { applyPreset(.youtube4K) }
                        ExportPresetButton(preset: .youtube1080, icon: "play.tv", title: "YouTube 1080p", selected: selectedPreset == .youtube1080, id: "export.preset.youtube1080") { applyPreset(.youtube1080) }
                        ExportPresetButton(preset: .social1080, icon: "iphone", title: "Social", selected: selectedPreset == .social1080, id: "export.preset.social") { applyPreset(.social1080) }
                        ExportPresetButton(preset: .compressed, icon: "arrow.down.circle", title: "Small File", selected: selectedPreset == .compressed, id: "export.preset.small") { applyPreset(.compressed) }
                    }

                    if let description = selectedPreset?.description {
                        Text(description)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(.leading, 4)

                Divider()

                // MANUAL SETTINGS ROW
                HStack(spacing: 20) {
                    VStack(alignment: .leading, spacing: 4) {
                        Label(String(localized: "export.quality.label", defaultValue: "Quality"), systemImage: "dial.high")
                            .font(.caption)
                            .foregroundStyle(.secondary)

                        Picker("", selection: $exportSettings.resolution) {
                            Text(String(localized: "export.res.uhd", defaultValue: "4K (2160p)")).tag(SaneExportSettings.ExportResolution.uhd4K)
                            Text(String(localized: "export.res.hd", defaultValue: "1080p")).tag(SaneExportSettings.ExportResolution.hd1080)
                            Text(String(localized: "export.res.sd", defaultValue: "720p")).tag(SaneExportSettings.ExportResolution.hd720)
                        }
                        .pickerStyle(.menu)
                        .frame(maxWidth: 120)
                        .accessibilityIdentifier("export.resolution_picker")
                        .onChange(of: exportSettings.resolution) { _, _ in selectedPreset = .custom }
                    }

                    VStack(alignment: .leading, spacing: 4) {
                        Label(String(localized: "export.format.label", defaultValue: "Format"), systemImage: "film")
                            .font(.caption)
                            .foregroundStyle(.secondary)

                        Picker("", selection: $exportSettings.codec) {
                            Text(String(localized: "export.codec.h264", defaultValue: "H.264 (Compat)")).tag(AVVideoCodecType.h264)
                            Text(String(localized: "export.codec.hevc", defaultValue: "HEVC (Small)")).tag(AVVideoCodecType.hevc)
                            Text(String(localized: "export.codec.prores", defaultValue: "ProRes (Edit)")).tag(AVVideoCodecType.proRes422)
                        }
                        .pickerStyle(.menu)
                        .frame(maxWidth: 120)
                        .accessibilityIdentifier("export.format_picker")
                        .onChange(of: exportSettings.codec) { _, _ in selectedPreset = .custom }
                    }

                    VStack(alignment: .leading, spacing: 4) {
                        Label(String(localized: "export.size.label", defaultValue: "Est. Size"), systemImage: "externaldrive")
                            .font(.caption)
                            .foregroundStyle(.secondary)

                        Text("\(Int(exportSettings.bitrate / 1_000_000)) Mbps")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                        Text(estimateFileSize())
                            .font(.caption.monospaced())
                    }
                }
                .padding(4)
            }
        }
    }

    private func applyPreset(_ preset: ExportPreset) {
        selectedPreset = preset
        switch preset {
        case .youtube4K:
            exportSettings.resolution = .uhd4K
            exportSettings.codec = .hevc
            exportSettings.bitrate = 20_000_000
            exportSettings.frameRate = 60.0
        case .youtube1080:
            exportSettings.resolution = .hd1080
            exportSettings.codec = .h264
            exportSettings.bitrate = 12_000_000
            exportSettings.frameRate = 30.0
        case .social1080, .tiktok, .instagram, .twitter, .facebook:
            exportSettings.resolution = .hd1080
            exportSettings.codec = .h264
            exportSettings.bitrate = 8_000_000
            exportSettings.frameRate = 30.0
        case .compressed:
            exportSettings.resolution = .hd1080
            exportSettings.codec = .hevc
            exportSettings.bitrate = 5_000_000
            exportSettings.frameRate = 30.0
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
                    .font(.caption2)
                    .fontWeight(selected ? .semibold : .regular)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 8)
            .background(selected ? Color.accentColor.opacity(0.1) : Color.clear)
            .cornerRadius(6)
            .overlay(
                RoundedRectangle(cornerRadius: 6)
                    .stroke(selected ? Color.accentColor : Color.secondary.opacity(0.2), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier(id)
    }
}
