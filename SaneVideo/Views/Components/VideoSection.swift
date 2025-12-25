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
    @Binding var isOperationInProgress: Bool

    // CRITICAL FIX: Sync state with clip properties
    @State private var speed: Double
    @State private var isAnalyzingCrop = false
    @State private var cropResult: String?
    @State private var selectedAspectRatio: AspectRatioOption = .vertical
    @State private var cropError: String?
    
    // CRITICAL FIX: Debounce slider updates
    @State private var pendingSpeedUpdate: Task<Void, Never>?

    init(clip: VideoClip, isOperationInProgress: Binding<Bool>) {
        self.clip = clip
        self._isOperationInProgress = isOperationInProgress
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
                        // CRITICAL FIX: Debounce slider updates to prevent excessive saves
                        pendingSpeedUpdate?.cancel()
                        pendingSpeedUpdate = Task {
                            // Wait 300ms after user stops dragging
                            try? await Task.sleep(nanoseconds: 300_000_000)
                            guard !Task.isCancelled else { return }
                            await MainActor.run {
                                appState.projectState.updateClipSpeed(clipId: clip.id, speed: newValue)
                            }
                        }
                    }
                Text(String(format: "%.1fx", speed))
                    .font(.system(size: 11, design: .monospaced))
                    .frame(width: 40)
            }
            // CRITICAL FIX: Sync speed when clip changes externally
            .onChange(of: clip.speed) { _, newSpeed in
                if abs(speed - newSpeed) > 0.01 { // Only update if significantly different
                    speed = newSpeed
                }
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

            // Auto-Zoom (Screen Studio style)
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
                            .foregroundStyle(.secondary)
                    }
                    .padding(8)
                    .background(Color.blue.opacity(0.15))
                    .cornerRadius(6)
                    .overlay(
                        RoundedRectangle(cornerRadius: 6)
                            .stroke(Color.blue.opacity(0.3), lineWidth: 1)
                    )
                }
                .buttonStyle(.plain)
                .hoverScale(1.02)
                .pressScale()
                .disabled(appState.projectState.isProcessing || clip.isMissing) // CRITICAL FIX: Disable if clip is missing
                .accessibilityIdentifier("video.apply_auto_zoom")
                .smoothAppear()
                
                Divider().padding(.vertical, 4)
            }

            // Smart Crop with Aspect Ratio Options
            SubsectionHeader(title: String(localized: "video.section.smart_crop", defaultValue: "Smart Crop"))

            // P1 FIX: Larger aspect ratio buttons
            HStack(spacing: 8) {
                ForEach(AspectRatioOption.allCases) { option in
                    AspectRatioButton(
                        option: option,
                        isSelected: selectedAspectRatio == option
                    ) {
                        selectedAspectRatio = option
                    }
                    .accessibilityIdentifier("video.aspect_ratio.\(option.id)")
                    .accessibilityLabel("\(option.localizedLabel) aspect ratio")
                    .accessibilityHint(option.localizedPlatform)
                    .focusable()
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
            .disabled(isAnalyzingCrop || clip.isMissing) // CRITICAL FIX: Disable if clip is missing
            .accessibilityIdentifier("video.apply_smart_crop")
            .smoothAppear()

            // CRITICAL FIX: Show error if operation failed
            if let error = cropError {
                HStack {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundColor(.orange)
                    Text(error)
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
                .padding(6)
                .background(Color.orange.opacity(0.1))
                .cornerRadius(4)
                .transition(.smoothScale)
            }
            
            if let result = cropResult {
                Text(result)
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }
        }
    }

    private func applySmartCrop() async {
        // CRITICAL FIX: Validate clip before operation
        guard !clip.isMissing else {
            await MainActor.run {
                cropError = "Cannot apply crop: Clip file is missing. Use 'Locate File' in Clip Info to relink the file."
                cropResult = nil
                ServiceContainer.shared.toastManager.show(
                    "Clip file is missing. Check Clip Info section to relink the file.",
                    type: .error
                )
            }
            return
        }
        
        // CRITICAL FIX: Check if clip has video track
        let asset = AVURLAsset(url: clip.url)
        let tracks = try? await asset.loadTracks(withMediaType: .video)
        guard let videoTrack = tracks?.first else {
            await MainActor.run {
                cropError = "Cannot apply crop: No video track found in this clip"
                cropResult = nil
                ServiceContainer.shared.toastManager.show(
                    "This clip doesn't contain video. Smart crop requires a video track.",
                    type: .error
                )
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

        do {
            await appState.projectState.applySmartCrop(
                to: clip,
                targetAspectRatio: selectedAspectRatio.ratio
            )
            await MainActor.run {
                cropResult = "✅ Applied \(selectedAspectRatio.localizedLabel) crop"
                cropError = nil
            }
        } catch {
            await MainActor.run {
                let errorMessage = error.localizedDescription
                cropError = "Crop failed: \(errorMessage)"
                cropResult = nil
                AppLogger.project.error("Smart crop failed: \(errorMessage)")
                ServiceContainer.shared.toastManager.show(
                    "Smart crop failed: \(errorMessage)",
                    type: .error
                )
            }
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

            // P1 FIX: Larger rotation buttons with better visual feedback
            HStack(spacing: 8) {
                // Rotate 90° Clockwise
                Button {
                    appState.projectState.rotateClip(clip)
                } label: {
                    VStack(spacing: 6) {
                        Image(systemName: "rotate.right")
                            .font(.system(size: 18, weight: .medium))
                        Text(String(localized: "video.transform.rotate_cw", defaultValue: "90° CW"))
                            .font(.caption)
                            .fontWeight(.medium)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 10)
                }
                .buttonStyle(.bordered)
                .controlSize(.regular) // P1 FIX: Larger control size
                .disabled(clip.isMissing)
                .accessibilityIdentifier("video.rotate_cw")
                .help("Rotate 90° clockwise")

                // Rotate 90° Counter-Clockwise
                Button {
                    // CRITICAL FIX: Validate clip before operation
                    guard !clip.isMissing else {
                        ServiceContainer.shared.toastManager.show(
                            "Cannot rotate: Clip file is missing",
                            type: .error
                        )
                        return
                    }
                    
                    let targetRotation = clip.rotation.counterClockwise
                    appState.projectState.setClipRotation(clip, to: targetRotation)
                } label: {
                    VStack(spacing: 6) {
                        Image(systemName: "rotate.left")
                            .font(.system(size: 18, weight: .medium))
                        Text(String(localized: "video.transform.rotate_ccw", defaultValue: "90° CCW"))
                            .font(.caption)
                            .fontWeight(.medium)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 10)
                }
                .buttonStyle(.bordered)
                .controlSize(.regular) // P1 FIX: Larger control size
                .disabled(clip.isMissing)
                .accessibilityIdentifier("video.rotate_ccw")
                .help("Rotate 90° counter-clockwise")
            }

            // Reset to Original
            if clip.rotation != .none {
                Button(String(localized: "video.transform.reset", defaultValue: "Reset to Original")) {
                    // CRITICAL FIX: Validate clip before operation
                    guard !clip.isMissing else {
                        ServiceContainer.shared.toastManager.show(
                            "Cannot reset rotation: Clip file is missing",
                            type: .error
                        )
                        return
                    }
                    
                    appState.projectState.setClipRotation(clip, to: .none)
                }
                .font(.caption)
                .buttonStyle(.bordered)
                .controlSize(.small)
                .tint(.orange)
                .disabled(clip.isMissing) // CRITICAL FIX: Disable if clip is missing
                .accessibilityIdentifier("video.reset_rotation")
            }
        }
    }
}
