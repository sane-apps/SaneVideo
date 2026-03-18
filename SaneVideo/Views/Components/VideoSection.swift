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

    private var hasClickData: Bool { clip.hasRecordedClickData }
    private var hasCursorData: Bool { clip.hasRecordedCursorData }
    private var hasKeystrokeData: Bool { clip.hasRecordedKeystrokeData }
    private var autoZoomSummary: String {
        if hasClickData && hasCursorData {
            return "Creates focus moves from recorded clicks and cursor motion so walkthroughs feel guided instead of static."
        } else if hasClickData {
            return "Creates focus moves from recorded click events so the viewer follows the action without manual keyframing."
        } else {
            return "Auto-Zoom needs recorded click data. Screen recordings with interaction capture turn this on automatically."
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 12) {
                SubsectionHeader(title: String(localized: "video.section.auto_zoom", defaultValue: "Auto-Zoom"))

                HelperText(
                    text: autoZoomSummary,
                    icon: "sparkles.tv.fill",
                    color: hasClickData ? Theme.Colors.accent : Theme.Colors.warning
                )

                HStack(spacing: 8) {
                    FeatureBadge(
                        label: hasClickData ? "Click data ready" : "No click data yet",
                        icon: hasClickData ? "cursorarrow.click" : "exclamationmark.triangle.fill",
                        accent: hasClickData ? Theme.Colors.accent : Theme.Colors.warning
                    )

                    if hasCursorData {
                        FeatureBadge(
                            label: "Cursor path ready",
                            icon: "cursorarrow.motionlines",
                            accent: Theme.Colors.accentSoft
                        )
                    }

                    if hasKeystrokeData {
                        FeatureBadge(
                            label: "Keys ready",
                            icon: "command",
                            accent: Theme.Colors.accentSoft
                        )
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                Button {
                    Task { await appState.projectState.applyAutoZoom(to: clip) }
                } label: {
                    HStack(spacing: 10) {
                        Image(systemName: "magnifyingglass")
                            .font(.system(size: Theme.Typography.iconSizeSM, weight: .semibold))
                        Text(
                            hasClickData
                                ? String(localized: "video.action.apply_auto_zoom", defaultValue: "Apply Auto-Zoom")
                                : "Record Click Data First"
                        )
                        .saneReadableBodyStrong()
                        Spacer()
                        Text(hasCursorData ? "Cursor-guided" : "Click-guided")
                            .saneReadableMeta()
                    }
                    .padding(12)
                    .background(
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .fill(Theme.Colors.accent.opacity(hasClickData ? 0.18 : 0.08))
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .stroke(Theme.Colors.accent.opacity(hasClickData ? 0.34 : 0.16), lineWidth: 1)
                    )
                }
                .buttonStyle(.plain)
                .hoverScale(1.02)
                .pressScale()
                .disabled(appState.projectState.isProcessing || isOperationInProgress || clip.isMissing || !hasClickData)
                .help(
                    clip.isMissing
                        ? "Clip file is missing"
                        : hasClickData
                            ? "Generate automatic focus moves from recorded interaction data"
                            : "Auto-Zoom needs click data from a screen recording"
                )
                .accessibilityIdentifier("video.apply_auto_zoom")
                .smoothAppear()
            }
            .padding(14)
            .sanePanel(radius: 16, emphasized: hasClickData, accent: hasClickData ? Theme.Colors.accent : Theme.Colors.warning)

            VStack(alignment: .leading, spacing: 12) {
                SubsectionHeader(title: String(localized: "video.section.smart_crop", defaultValue: "Smart Crop"))

                HelperText(
                    text: "Reframes the clip for a destination shape. Pick the target below, then run the analysis button once.",
                    icon: "viewfinder.circle.fill",
                    color: Theme.Colors.accent
                )

                VStack(alignment: .leading, spacing: 8) {
                    Text("Target output")
                        .saneReadableLabel()
                    Text("These ratio buttons only choose the destination format. They do not crop the clip until you run the action below.")
                        .saneReadableSupportText()

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
                }

                Button {
                    Task { await applySmartCrop() }
                } label: {
                    HStack(spacing: 10) {
                        Image(systemName: "crop")
                            .font(.system(size: Theme.Typography.iconSizeSM, weight: .semibold))
                        Text(isAnalyzingCrop ? String(localized: "video.action.analyzing", defaultValue: "Analyzing...") : "Analyze + Apply Crop")
                            .saneReadableBodyStrong()
                        Spacer()
                        if isAnalyzingCrop {
                            ProgressView().scaleEffect(0.6)
                        } else {
                            Text("\(selectedAspectRatio.localizedLabel) · \(selectedAspectRatio.localizedPlatform)")
                                .saneReadableMeta()
                        }
                    }
                    .padding(12)
                    .background(
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .fill(Theme.Colors.accent.opacity(0.18))
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .stroke(Theme.Colors.accent.opacity(0.34), lineWidth: 1)
                    )
                }
                .buttonStyle(.plain)
                .hoverScale(1.02)
                .pressScale()
                .disabled(isAnalyzingCrop || isOperationInProgress || clip.isMissing)
                .help(clip.isMissing ? "Clip file is missing" : "Analyze the clip and apply a smart crop for the selected output shape")
                .accessibilityIdentifier("video.apply_smart_crop")
                .smoothAppear()
            }
            .padding(14)
            .sanePanel(radius: 16, accent: Theme.Colors.accentSoft)

            if let error = cropError {
                InformationBox(text: error, color: Theme.Colors.warning, icon: "exclamationmark.triangle.fill")
                    .transition(.smoothScale)
            }

            if let result = cropResult {
                InformationBox(text: result, color: Theme.Colors.accent, icon: "checkmark.circle.fill")
            }

            HelperText(
                text: "Rotate and playback speed still live in the toolbar below the viewer.",
                icon: "slider.horizontal.3",
                color: Theme.Colors.accentSoft
            )
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
            cropResult = "Applied \(selectedAspectRatio.localizedLabel) crop for \(selectedAspectRatio.localizedPlatform)."
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
            VStack(spacing: 4) {
                Image(systemName: option.icon)
                    .font(.system(size: 15, weight: .semibold))
                Text(option.localizedLabel)
                    .font(.system(size: 11, weight: .bold))
                Text(option.localizedPlatform)
                    .font(.system(size: 10, weight: .medium))
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 10)
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(
                        isSelected
                            ? LinearGradient(
                                colors: [Theme.Colors.accent.opacity(0.24), Theme.Colors.accentDeep.opacity(0.18)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                            : LinearGradient(
                                colors: [Color.white.opacity(0.05), Theme.Colors.ambientDeep.opacity(0.18)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                    )
            )
            .foregroundStyle(isSelected ? Theme.Colors.textPrimary : Theme.Colors.textSecondary)
            .overlay(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .stroke(isSelected ? Theme.Colors.accent : Color.white.opacity(0.08), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
        .hoverScale(1.03)
        .pressScale()
        .animation(.smoothUI, value: isSelected)
        .help(option.localizedPlatform)
        .smoothAppear()
    }
}
