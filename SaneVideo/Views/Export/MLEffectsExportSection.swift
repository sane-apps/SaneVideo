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
                .saneReadableSectionTitle()

                Spacer()

                if mlEffects.hasAnyEnabled {
                    Text(String(localized: "export.ml.warning", defaultValue: "Export will take longer"))
                        .font(Theme.Typography.support)
                        .foregroundStyle(.orange)
                }
            }

            HelperText(
                text: "These enhancement effects run on-device. They can improve polish, but they make export slower.",
                icon: "cpu"
            )

            // Super Resolution
            VStack(alignment: .leading, spacing: 6) {
                Toggle(isOn: $mlEffects.superResolutionEnabled) {
                    HStack {
                        Image(systemName: "arrow.up.left.and.arrow.down.right")
                            .foregroundStyle(Color.accentColor)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(String(localized: "export.ml.superres", defaultValue: "Super Resolution"))
                                .saneReadableBodyStrong()
                            Text(String(localized: "export.ml.superres.desc", defaultValue: "ML upscaling for sharper video"))
                                .saneReadableSupportText()
                        }
                    }
                }
                .toggleStyle(.switch)
                .accessibilityIdentifier("export.ml.superres")

                if mlEffects.superResolutionEnabled {
                    HStack {
                        Text(String(localized: "export.ml.scale", defaultValue: "Scale:"))
                            .saneReadableLabel()
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
                                .saneReadableBodyStrong()
                            Text(String(localized: "export.ml.denoise.desc", defaultValue: "Temporal noise filter for cleaner video"))
                                .saneReadableSupportText()
                        }
                    }
                }
                .toggleStyle(.switch)
                .disabled(!MLEffectsService.isDenoiseSupported)
                .accessibilityIdentifier("export.ml.denoise")

                if mlEffects.denoiseEnabled {
                    HStack {
                        Text(String(localized: "export.ml.strength", defaultValue: "Strength:"))
                            .saneReadableLabel()
                        Slider(value: $mlEffects.denoiseStrength, in: 0.5...1.5)
                            .frame(width: 100)
                        Text(String(format: "%.1fx", mlEffects.denoiseStrength))
                            .saneReadableMeta(monospaced: true)
                            .frame(width: 40)
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
                                .saneReadableBodyStrong()
                            Text(String(localized: "export.ml.interpolation.desc", defaultValue: "Smooth motion with ML-generated frames"))
                                .saneReadableSupportText()
                        }
                    }
                }
                .toggleStyle(.switch)
                .accessibilityIdentifier("export.ml.interpolation")

                if mlEffects.frameInterpolationEnabled {
                    HStack {
                        Text(String(localized: "export.ml.target_fps", defaultValue: "Target FPS:"))
                            .saneReadableLabel()
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
                        .saneReadableSupportText()
                    Spacer()
                    if isDownloadingModel {
                        ProgressView()
                            .controlSize(.small)
                    } else {
                        Button(String(localized: "export.ml.download", defaultValue: "Download")) {
                            downloadModel()
                        }
                        .font(Theme.Typography.meta)
                        .buttonStyle(.bordered)
                    }
                }
                .padding(8)
                .sanePanel(radius: 10, accent: .yellow)
            }
        }
        .padding(12)
        .sanePanel(radius: 12, accent: Theme.Colors.accentSoft)
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
