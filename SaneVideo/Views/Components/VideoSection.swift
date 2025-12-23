//
//  VideoSection.swift
//  SaneVideo
//
//  Extracted from StylesInspectorView.swift
//  Contains video-related inspector controls (Transform, Speed, Smart Crop)
//

import AVFoundation
import SwiftUI

// MARK: - VIDEO Section (Transform + Speed + Smart Crop)

struct VideoSection: View {
    @Environment(AppState.self) var appState
    let clip: VideoClip

    @State private var speed: Double
    @State private var isAnalyzingCrop = false
    @State private var cropResult: String?
    @State private var selectedAspectRatio: AspectRatioOption = .vertical

    init(clip: VideoClip) {
        self.clip = clip
        _speed = State(initialValue: clip.speed)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Transform
            SubsectionHeader(title: String(localized: "video.section.transform", defaultValue: "Transform"))
            TransformControlsView(clip: clip)

            Divider().padding(.vertical, 4)

            // Speed
            SubsectionHeader(title: String(localized: "video.section.speed", defaultValue: "Speed"))
            HStack {
                Slider(value: $speed, in: 0.25 ... 4.0, step: 0.25)
                    .accessibilityIdentifier("video.speed_slider")
                    .onChange(of: speed) { _, newValue in
                        appState.projectState.updateClipSpeed(clipId: clip.id, speed: newValue)
                    }
                Text(String(format: "%.1fx", speed))
                    .font(.system(size: 11, design: .monospaced))
                    .frame(width: 40)
            }
            HStack(spacing: 6) {
                ForEach([0.5, 1.0, 1.5, 2.0], id: \.self) { preset in
                    Button(String(format: "%.1fx", preset)) {
                        speed = preset
                        appState.projectState.updateClipSpeed(clipId: clip.id, speed: speed)
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.mini)
                    .tint(speed == preset ? .accentColor : .secondary)
                    .accessibilityIdentifier("video.speed_preset.\(preset)")
                }
            }

            Divider().padding(.vertical, 4)

            // Smart Crop with Aspect Ratio Options
            SubsectionHeader(title: String(localized: "video.section.smart_crop", defaultValue: "Smart Crop"))

            // Aspect Ratio Picker
            HStack(spacing: 6) {
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
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(8)
                .background(Color.purple.opacity(0.15))
                .cornerRadius(6)
                .overlay(
                    RoundedRectangle(cornerRadius: 6)
                        .stroke(Color.purple.opacity(0.3), lineWidth: 1)
                )
            }
            .buttonStyle(.plain)
            .hoverScale(1.02)
            .pressScale()
            .disabled(isAnalyzingCrop)
            .accessibilityIdentifier("video.apply_smart_crop")
            .smoothAppear()

            if let result = cropResult {
                Text(result)
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }
        }
    }

    private func applySmartCrop() async {
        isAnalyzingCrop = true
        cropResult = nil
        defer { isAnalyzingCrop = false }

        await appState.projectState.applySmartCrop(
            to: clip,
            targetAspectRatio: selectedAspectRatio.ratio
        )
        cropResult = "✅ Applied \(selectedAspectRatio.localizedLabel) crop"
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
        case .vertical: return String(localized: "aspect_ratio.9_16", defaultValue: "9:16")
        case .square: return String(localized: "aspect_ratio.1_1", defaultValue: "1:1")
        case .horizontal: return String(localized: "aspect_ratio.16_9", defaultValue: "16:9")
        case .cinema: return String(localized: "aspect_ratio.21_9", defaultValue: "21:9")
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
        case .vertical: return String(localized: "aspect_ratio.platform.vertical", defaultValue: "TikTok/Reels")
        case .square: return String(localized: "aspect_ratio.platform.square", defaultValue: "Instagram")
        case .horizontal: return String(localized: "aspect_ratio.platform.horizontal", defaultValue: "YouTube")
        case .cinema: return String(localized: "aspect_ratio.platform.cinema", defaultValue: "Cinematic")
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
            .background(isSelected ? Color.purple.opacity(0.2) : Color.secondary.opacity(0.1))
            .foregroundColor(isSelected ? .purple : .secondary)
            .cornerRadius(6)
            .overlay(
                RoundedRectangle(cornerRadius: 6)
                    .stroke(isSelected ? Color.purple : Color.clear, lineWidth: 1)
            )
            .shadow(color: isSelected ? Color.purple.opacity(0.3) : .clear, radius: 4, x: 0, y: 2)
        }
        .buttonStyle(.plain)
        .hoverScale(1.05)
        .pressScale()
        .animation(.smoothUI, value: isSelected)
        .help(option.localizedPlatform)
        .smoothAppear()
    }
}

// MARK: - Transform Controls (Rotation Only)

struct TransformControlsView: View {
    @Environment(AppState.self) var appState
    let clip: VideoClip

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Current rotation status
            if clip.rotation != .none {
                HStack {
                    Text("Current:")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Text(clip.rotation.displayName)
                        .font(.caption.bold())
                        .foregroundColor(.accentColor)
                }
            }

            // Quick Rotation Buttons
            HStack(spacing: 8) {
                // Rotate 90° Clockwise
                Button {
                    appState.projectState.rotateClip(clip)
                } label: {
                    VStack(spacing: 4) {
                        Image(systemName: "rotate.right")
                            .font(.system(size: 16))
                        Text(String(localized: "video.transform.rotate_cw", defaultValue: "90° CW"))
                            .font(.caption2)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 8)
                }
                .buttonStyle(.bordered)
                .accessibilityIdentifier("video.rotate_cw")

                // Rotate 90° Counter-Clockwise
                Button {
                    let targetRotation = clip.rotation.counterClockwise
                    appState.projectState.setClipRotation(clip, to: targetRotation)
                } label: {
                    VStack(spacing: 4) {
                        Image(systemName: "rotate.left")
                            .font(.system(size: 16))
                        Text(String(localized: "video.transform.rotate_ccw", defaultValue: "90° CCW"))
                            .font(.caption2)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 8)
                }
                .buttonStyle(.bordered)
                .accessibilityIdentifier("video.rotate_ccw")
            }

            // Reset to Original
            if clip.rotation != .none {
                Button(String(localized: "video.transform.reset", defaultValue: "Reset to Original")) {
                    appState.projectState.setClipRotation(clip, to: .none)
                }
                .font(.caption)
                .buttonStyle(.bordered)
                .controlSize(.small)
                .tint(.orange)
                .accessibilityIdentifier("video.reset_rotation")
            }
        }
    }
}
