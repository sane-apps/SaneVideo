//
//  MLEffectsExportSection.swift
//  SaneVideo
//
//  ML Effects toggle section for export configuration
//  These effects use VideoToolbox VTFrameProcessor for high-quality processing
//

import SwiftUI

/// ML effect configurations for export
struct MLExportEffects: Equatable {
    var superResolutionEnabled = false
    var superResolutionScale: CGFloat = 2.0

    var denoiseEnabled = false
    var denoiseStrength: Float = 1.0

    var frameInterpolationEnabled = false
    var targetFrameRate: Double = 60

    var hasAnyEnabled: Bool {
        superResolutionEnabled || denoiseEnabled || frameInterpolationEnabled
    }
}

/// Section view for ML effects in export configuration
struct MLEffectsExportSection: View {
    @Binding var mlEffects: MLExportEffects
    @State private var modelStatus: String = "Checking..."
    @State private var isDownloadingModel = false
    @State private var isModelReady = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Header
            HStack {
                Label(
                    String(localized: "export.ml.header", defaultValue: "AI Enhancement"),
                    systemImage: "cpu"
                )
                .font(.subheadline.weight(.semibold))

                Spacer()

                if mlEffects.hasAnyEnabled {
                    Text(String(localized: "export.ml.warning", defaultValue: "Export will take longer"))
                        .font(.caption2)
                        .foregroundStyle(.orange)
                }
            }

            // Super Resolution
            VStack(alignment: .leading, spacing: 6) {
                Toggle(isOn: $mlEffects.superResolutionEnabled) {
                    HStack {
                        Image(systemName: "arrow.up.left.and.arrow.down.right")
                            .foregroundStyle(Color.accentColor)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(String(localized: "export.ml.superres", defaultValue: "Super Resolution"))
                                .font(.caption.weight(.medium))
                            Text(String(localized: "export.ml.superres.desc", defaultValue: "ML upscaling for sharper video"))
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                .toggleStyle(.switch)
                .accessibilityIdentifier("export.ml.superres")

                if mlEffects.superResolutionEnabled {
                    HStack {
                        Text(String(localized: "export.ml.scale", defaultValue: "Scale:"))
                            .font(.caption)
                        Picker("", selection: $mlEffects.superResolutionScale) {
                            Text("1.5x").tag(CGFloat(1.5))
                            Text("2x").tag(CGFloat(2.0))
                        }
                        .pickerStyle(.segmented)
                        .frame(width: 120)
                    }
                    .padding(.leading, 24)
                }
            }

            Divider()

            // Denoise
            VStack(alignment: .leading, spacing: 6) {
                Toggle(isOn: $mlEffects.denoiseEnabled) {
                    HStack {
                        Image(systemName: "sparkles")
                            .foregroundStyle(Color.accentColor)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(String(localized: "export.ml.denoise", defaultValue: "Noise Reduction"))
                                .font(.caption.weight(.medium))
                            Text(String(localized: "export.ml.denoise.desc", defaultValue: "Temporal noise filter for cleaner video"))
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                .toggleStyle(.switch)
                .disabled(!MLEffectsService.isDenoiseSupported)
                .accessibilityIdentifier("export.ml.denoise")

                if mlEffects.denoiseEnabled {
                    HStack {
                        Text(String(localized: "export.ml.strength", defaultValue: "Strength:"))
                            .font(.caption)
                        Slider(value: $mlEffects.denoiseStrength, in: 0.5...1.5)
                            .frame(width: 100)
                        Text(String(format: "%.1fx", mlEffects.denoiseStrength))
                            .font(.caption.monospacedDigit())
                            .frame(width: 32)
                    }
                    .padding(.leading, 24)
                }
            }

            Divider()

            // Frame Interpolation
            VStack(alignment: .leading, spacing: 6) {
                Toggle(isOn: $mlEffects.frameInterpolationEnabled) {
                    HStack {
                        Image(systemName: "film.stack")
                            .foregroundStyle(Color.accentColor)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(String(localized: "export.ml.interpolation", defaultValue: "Frame Interpolation"))
                                .font(.caption.weight(.medium))
                            Text(String(localized: "export.ml.interpolation.desc", defaultValue: "Smooth motion with ML-generated frames"))
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                .toggleStyle(.switch)
                .accessibilityIdentifier("export.ml.interpolation")

                if mlEffects.frameInterpolationEnabled {
                    HStack {
                        Text(String(localized: "export.ml.target_fps", defaultValue: "Target FPS:"))
                            .font(.caption)
                        Picker("", selection: $mlEffects.targetFrameRate) {
                            Text("48 fps").tag(48.0)
                            Text("60 fps").tag(60.0)
                            Text("120 fps").tag(120.0)
                        }
                        .pickerStyle(.segmented)
                        .frame(width: 180)
                    }
                    .padding(.leading, 24)
                }
            }

            // Model status / download prompt for super resolution
            if mlEffects.superResolutionEnabled && !isModelReady {
                HStack {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(.yellow)
                    Text(String(localized: "export.ml.model_required", defaultValue: "ML model download required"))
                        .font(.caption)
                    Spacer()
                    if isDownloadingModel {
                        ProgressView()
                            .controlSize(.small)
                    } else {
                        Button(String(localized: "export.ml.download", defaultValue: "Download")) {
                            downloadModel()
                        }
                        .font(.caption)
                        .buttonStyle(.bordered)
                    }
                }
                .padding(8)
                .background(Color.accentColor.opacity(0.1))
                .cornerRadius(6)
            }
        }
        .padding(12)
        .background(Color.secondary.opacity(0.05))
        .cornerRadius(8)
        .task {
            updateModelStatus()
        }
    }

    private func updateModelStatus() {
        if #available(macOS 26.0, *) {
            let status = MLEffectsService.superResolutionModelStatus
            switch status {
            case .ready:
                modelStatus = "Ready"
                isModelReady = true
            case .downloading:
                modelStatus = "Downloading..."
                isDownloadingModel = true
                isModelReady = false
            case .downloadRequired:
                modelStatus = "Download Required"
                isModelReady = false
            @unknown default:
                modelStatus = "Unknown"
                isModelReady = false
            }
        } else {
            // Super resolution not available on older macOS
            modelStatus = "Requires macOS 26"
            isModelReady = false
        }
    }

    private func downloadModel() {
        guard #available(macOS 26.0, *) else {
            ServiceContainer.shared.toastManager.show(
                "Super resolution requires macOS 26 or later",
                type: .error
            )
            return
        }

        isDownloadingModel = true
        Task {
            do {
                let service = MLEffectsService()
                try await service.downloadSuperResolutionModel()
                await MainActor.run {
                    isDownloadingModel = false
                    updateModelStatus()
                }
            } catch {
                await MainActor.run {
                    isDownloadingModel = false
                    ServiceContainer.shared.toastManager.show(
                        "Failed to download ML model: \(error.localizedDescription)",
                        type: .error
                    )
                }
            }
        }
    }
}

#Preview {
    @Previewable @State var effects = MLExportEffects()

    MLEffectsExportSection(mlEffects: $effects)
        .frame(width: 350)
        .padding()
}
