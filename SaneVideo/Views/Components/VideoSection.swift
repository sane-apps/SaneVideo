//
//  VideoSection.swift
//  SaneVideo
//
//  2025-12-31: Simplified - Transform/Speed moved to toolbar. Kept: Auto-Zoom, Smart Crop
//

import AVFoundation
import SwiftUI

// MARK: - VIDEO Section (Auto-Zoom + Smart Crop)

struct VideoSection: View {
    @Environment(AppState.self) var appState
    let clip: VideoClip
    @Binding var isOperationInProgress: Bool

    @State private var isAnalyzingCrop = false
    @State private var cropResult: String?
    @State private var selectedAspectRatio: AspectRatioOption = .vertical
    @State private var cropError: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Auto-Zoom (Screen Studio style) - only if click data exists
            if clip.clickDataURL != nil {
                SubsectionHeader(title: String(localized: "video.section.auto_zoom", defaultValue: "Auto-Zoom"))
                Button {
                    Task { await appState.projectState.applyAutoZoom(to: clip) }
                } label: {
                    HStack {
                        Image(systemName: "magnifyingglass")
                        Text(String(localized: "video.action.apply_auto_zoom", defaultValue: "Apply Auto-Zoom"))
                            .font(.caption)
                        Spacer()
                        Image(systemName: "sparkles")
                            .font(.caption2)
                            .foregroundStyle(Color.stone)
                    }
                    .padding(8)
                    .background(Color.accentColor.opacity(0.15))
                    .cornerRadius(6)
                    .overlay(
                        RoundedRectangle(cornerRadius: 6)
                            .stroke(Color.accentColor.opacity(0.3), lineWidth: 1)
                    )
                }
                .buttonStyle(.plain)
                .hoverScale(1.02)
                .pressScale()
                .disabled(appState.projectState.isProcessing || clip.isMissing)
                .help(clip.isMissing ? "Clip file is missing" : "Apply auto-zoom to highlight click events")
                .accessibilityIdentifier("video.apply_auto_zoom")
                .smoothAppear()

                Divider().padding(.vertical, 4)
            }

            // Smart Crop with Aspect Ratio Options
            SubsectionHeader(title: String(localized: "video.section.smart_crop", defaultValue: "Smart Crop"))

            HStack(spacing: 8) {
                ForEach(AspectRatioOption.allCases) { option in
                    AspectRatioButton(
                        option: option,
                        isSelected: selectedAspectRatio == option
                    ) {
                        selectedAspectRatio = option
                    }
                    .accessibilityIdentifier("video.aspect_ratio.\(option.id)")
                }
            }

            // Apply Button
            Button {
                Task { await applySmartCrop() }
            } label: {
                HStack {
                    Image(systemName: "crop")
                    Text(isAnalyzingCrop ? String(localized: "video.action.analyzing", defaultValue: "Analyzing...") : String(localized: "video.action.apply_smart_crop", defaultValue: "Apply Smart Crop"))
                        .font(.caption)
                    Spacer()
                    if isAnalyzingCrop {
                        ProgressView().scaleEffect(0.6)
                    } else {
                        Text(selectedAspectRatio.localizedLabel)
                            .font(.caption2)
                            .foregroundStyle(Color.stone)
                    }
                }
                .padding(8)
                .background(Theme.Colors.accent.opacity(0.15))
                .cornerRadius(6)
                .overlay(
                    RoundedRectangle(cornerRadius: 6)
                        .stroke(Theme.Colors.accent.opacity(0.3), lineWidth: 1)
                )
            }
            .buttonStyle(.plain)
            .hoverScale(1.02)
            .pressScale()
            .disabled(isAnalyzingCrop || clip.isMissing)
            .help(clip.isMissing ? "Clip file is missing" : "Apply smart crop to reframe video")
            .accessibilityIdentifier("video.apply_smart_crop")
            .smoothAppear()

            if let error = cropError {
                HStack {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundColor(.orange)
                    Text(error)
                        .font(.caption2)
                        .foregroundColor(Color.stone)
                }
                .padding(6)
                .background(Color.orange.opacity(0.1))
                .cornerRadius(4)
                .transition(.smoothScale)
            }

            if let result = cropResult {
                Text(result)
                    .font(.caption2)
                    .foregroundColor(Color.stone)
            }

            // Hint: Basic controls in toolbar
            HStack(spacing: 4) {
                Image(systemName: "info.circle")
                    .font(.caption2)
                Text("Rotate & Speed in toolbar below video")
                    .font(.caption2)
            }
            .foregroundColor(Color.stone)
            .padding(.top, 4)
        }
    }

    private func applySmartCrop() async {
        guard !clip.isMissing else {
            await MainActor.run {
                cropError = "Clip file is missing"
                ServiceContainer.shared.toastManager.show("Clip file is missing", type: .error)
            }
            return
        }

        let asset = AVURLAsset(url: clip.url)
        let tracks = try? await asset.loadTracks(withMediaType: .video)
        guard tracks?.first != nil else {
            await MainActor.run {
                cropError = "No video track found"
                ServiceContainer.shared.toastManager.show("No video track in clip", type: .error)
            }
            return
        }

        isAnalyzingCrop = true
        cropResult = nil
        cropError = nil
        defer {
            Task { @MainActor in
                isAnalyzingCrop = false
            }
        }

        await appState.projectState.applySmartCrop(
            to: clip,
            targetAspectRatio: selectedAspectRatio.ratio
        )
        await MainActor.run {
            cropResult = "✅ Applied \(selectedAspectRatio.localizedLabel) crop"
            cropError = nil
        }
    }
}

// MARK: - Aspect Ratio Options

enum AspectRatioOption: String, CaseIterable, Identifiable {
    case vertical = "9:16"
    case square = "1:1"
    case horizontal = "16:9"
    case cinema = "21:9"

    var id: String { rawValue }

    var localizedLabel: String {
        switch self {
        case .vertical: return "9:16"
        case .square: return "1:1"
        case .horizontal: return "16:9"
        case .cinema: return "21:9"
        }
    }

    var ratio: CGFloat {
        switch self {
        case .vertical: return 9.0 / 16.0
        case .square: return 1.0
        case .horizontal: return 16.0 / 9.0
        case .cinema: return 21.0 / 9.0
        }
    }

    var icon: String {
        switch self {
        case .vertical: return "rectangle.portrait"
        case .square: return "square"
        case .horizontal: return "rectangle"
        case .cinema: return "rectangle.ratio.16.to.9"
        }
    }

    var localizedPlatform: String {
        switch self {
        case .vertical: return "TikTok/Reels"
        case .square: return "Instagram"
        case .horizontal: return "YouTube"
        case .cinema: return "Cinematic"
        }
    }
}

// MARK: - Aspect Ratio Button

struct AspectRatioButton: View {
    let option: AspectRatioOption
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 2) {
                Image(systemName: option.icon)
                    .font(.system(size: 14))
                Text(option.localizedLabel)
                    .font(.system(size: 8, weight: .medium))
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 6)
            .background(isSelected ? Color.accentColor.opacity(0.2) : Color.stone.opacity(0.1))
            .foregroundColor(isSelected ? .accentColor : Color.stone)
            .cornerRadius(6)
            .overlay(
                RoundedRectangle(cornerRadius: 6)
                    .stroke(isSelected ? Color.accentColor : Color.clear, lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
        .hoverScale(1.05)
        .pressScale()
        .animation(.smoothUI, value: isSelected)
        .help(option.localizedPlatform)
        .smoothAppear()
    }
}
