//
//  EffectsPickerView.swift
//  SaneVideo
//
//  Created by SaneVideo Refactor
//  Redesigned: Direct effect tiles using Apple's CIFilter effects
//

import CoreMedia
import SwiftUI

struct EffectsPickerView: View {
    @Environment(AppState.self) var appState
    let clip: VideoClip
    @Binding var isOperationInProgress: Bool

    @State private var effects: [VideoEffect]
    @State private var selectedCategory: EffectCategory = .looks
    @State private var previewThumbnail: NSImage?  // Cached preview frame for effect tiles

    init(clip: VideoClip, isOperationInProgress: Binding<Bool>) {
        self.clip = clip
        self._isOperationInProgress = isOperationInProgress
        _effects = State(initialValue: clip.effects)
    }

    private var effectsForCategory: [VideoEffectType] {
        VideoEffectType.allCases.filter { $0.category == selectedCategory }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            // UX FIX: Removed duplicate Auto-Grade button
            // This feature is already accessible in Smart Tools as "Auto Color"
            // Having it in two places was confusing users

            // Active effects (if any) - shown at top with sliders
            if !effects.isEmpty {
                VStack(spacing: 4) {
                    ForEach(effects) { effect in
                        ActiveEffectRow(
                            effect: effect,
                            onIntensityChange: { updateEffectIntensity(effect.id, intensity: $0) },
                            onRemove: { removeEffect(effect.id) }
                        )
                    }
                }

                Divider()
            }

            // Category tabs
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    ForEach(EffectCategory.allCases, id: \.self) { category in
                        Button(category.displayName) {
                            withAnimation(.smoothUI) {
                                selectedCategory = category
                            }
                        }
                        .font(.caption2)
                        .fontWeight(selectedCategory == category ? .bold : .regular)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                        .background(selectedCategory == category ? Color.accentColor : Color.secondary.opacity(0.2))
                        .foregroundColor(selectedCategory == category ? .white : .primary)
                        .cornerRadius(12)
                        .overlay(
                            RoundedRectangle(cornerRadius: 12)
                                .stroke(selectedCategory == category ? Color.accentColor.opacity(0.5) : Color.clear, lineWidth: 1)
                        )
                        .shadow(color: selectedCategory == category ? Color.accentColor.opacity(0.3) : .clear, radius: 4, x: 0, y: 2)
                        .buttonStyle(.plain)
                        .hoverScale(1.05)
                        .animation(.smoothUI, value: selectedCategory)
                        .accessibilityIdentifier("effects.category.\(category.rawValue)")
                    }
                }
            }

            // UX FIX: Effect tiles with live previews showing what each filter does
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 64), spacing: 8)], spacing: 8) {
                ForEach(effectsForCategory) { effectType in
                    EffectTile(
                        effectType: effectType,
                        isActive: effects.contains { $0.type == effectType },
                        id: "effects.tile.\(effectType.rawValue)",
                        onTap: { toggleEffect(effectType) },
                        previewImage: previewThumbnail  // Show effect preview on actual clip frame
                    )
                }
            }
        }
        .task(id: clip.id) {
            // Load a preview thumbnail for effect previews
            await loadPreviewThumbnail()
        }
        // CRITICAL FIX: Sync effects when clip changes externally
        .onChange(of: clip.effects) { _, newEffects in
            // Only update if significantly different to avoid unnecessary re-renders
            if effects.count != newEffects.count || 
               !effects.elementsEqual(newEffects, by: { $0.id == $1.id && $0.intensity == $1.intensity }) {
                self.effects = newEffects
            }
        }
        // CRITICAL FIX: Validate clip exists before operations
        .onChange(of: clip.id) { _, _ in
            // Clip changed, sync effects
            self.effects = clip.effects
        }
    }

    // MARK: - Actions

    private func toggleEffect(_ type: VideoEffectType) {
        // CRITICAL FIX: Validate clip before toggling effect
        guard !clip.isMissing else {
            ServiceContainer.shared.toastManager.show(
                "Cannot apply effect: Clip file is missing. Use 'Locate File' in Clip Info to relink the file.",
                type: .error
            )
            return
        }
        
        if let index = effects.firstIndex(where: { $0.type == type }) {
            // Remove if already active
            effects.remove(at: index)
        } else {
            // Add with default intensity
            let effect = VideoEffect(type: type)
            effects.append(effect)
        }
        saveEffects()
    }

    private func removeEffect(_ id: UUID) {
        effects.removeAll { $0.id == id }
        saveEffects()
    }

    private func updateEffectIntensity(_ id: UUID, intensity: Float) {
        if let index = effects.firstIndex(where: { $0.id == id }) {
            effects[index].intensity = intensity
            // INSTANT PREVIEW: Save immediately for real-time slider feedback
            // No debouncing - user wants to see effect changes as they drag
            saveEffects()
        }
    }

    private func saveEffects() {
        // CRITICAL FIX: Validate clip before saving effects
        guard !clip.isMissing else {
            ServiceContainer.shared.toastManager.show(
                "Cannot save effects: Clip file is missing. Use 'Locate File' in Clip Info to relink the file.",
                type: .error
            )
            return
        }
        appState.projectState.updateClipEffects(clipId: clip.id, effects: effects)
    }

    /// Load a preview thumbnail from the clip for effect previews
    private func loadPreviewThumbnail() async {
        guard !clip.isMissing else { return }

        // Use middle of clip for representative frame
        let midTime = CMTime(seconds: clip.duration.seconds * 0.5, preferredTimescale: 600)
        let previewSize = CGSize(width: 128, height: 128)  // Small for performance

        if let thumbnail = await ServiceContainer.shared.thumbnailService.thumbnail(
            for: clip,
            time: midTime,
            size: previewSize
        ) {
            await MainActor.run {
                self.previewThumbnail = thumbnail
            }
        }
    }
}

// MARK: - Effect Tile (Tappable)

struct EffectTile: View {
    let effectType: VideoEffectType
    let isActive: Bool
    let id: String
    let onTap: () -> Void
    var previewImage: NSImage?  // Optional preview frame from clip

    // P1 FIX: State for hover preview
    @State private var isHovering = false
    @State private var filteredPreview: NSImage?

    var body: some View {
        Button(action: onTap, label: {
            VStack(spacing: 4) {
                ZStack {
                    // UX FIX: Show actual effect preview if we have a sample frame
                    if let preview = filteredPreview ?? previewImage {
                        Image(nsImage: preview)
                            .resizable()
                            .aspectRatio(contentMode: .fill)
                            .frame(width: 64, height: 64)
                            .clipShape(RoundedRectangle(cornerRadius: 8))
                            .overlay(
                                RoundedRectangle(cornerRadius: 8)
                                    .stroke(isActive ? Color.blue : Color.secondary.opacity(0.3), lineWidth: isActive ? 2 : 1)
                            )
                            .saturation(isActive ? 1.0 : 0.8)  // Slight desaturation when inactive
                    } else {
                        // Fallback to icon-based tile
                        RoundedRectangle(cornerRadius: 8)
                            .fill(isActive ? Color.blue.opacity(0.2) : Color.secondary.opacity(0.15))
                            .frame(width: 64, height: 64)
                            .overlay(
                                RoundedRectangle(cornerRadius: 8)
                                    .stroke(isActive ? Color.blue : Color.clear, lineWidth: 2)
                            )

                        Image(systemName: effectType.icon)
                            .font(.system(size: 20))
                            .foregroundColor(isActive ? .blue : .primary)
                    }

                    // Checkmark badge when active
                    if isActive {
                        VStack {
                            HStack {
                                Spacer()
                                Image(systemName: "checkmark.circle.fill")
                                    .font(.system(size: 14))
                                    .foregroundColor(.white)
                                    .background(Circle().fill(Color.blue))
                            }
                            Spacer()
                        }
                        .frame(width: 64, height: 64)
                        .offset(x: 4, y: -4)
                    }
                }

                Text(effectType.displayName)
                    .font(.system(size: 10))
                    .fontWeight(isActive ? .bold : .regular)
                    .foregroundColor(isActive ? .blue : .secondary)
                    .lineLimit(1)
            }
        })
        .buttonStyle(.plain)
        .hoverScale(1.1)
        .pressScale()
        .shadow(color: isActive ? Color.blue.opacity(0.3) : .clear, radius: 6, x: 0, y: 3)
        .animation(.smoothUI, value: isActive)
        .help(isActive ?
            String(localized: "effects.tile.remove", defaultValue: "Remove") + " \(effectType.displayName)" :
            String(localized: "effects.tile.apply", defaultValue: "Apply") + " \(effectType.displayName)")
        .accessibilityIdentifier(id)
        .accessibilityLabel(effectType.displayName)
        .accessibilityHint(isActive ? "Remove \(effectType.displayName) effect" : "Apply \(effectType.displayName) effect")
        .accessibilityValue(isActive ? "Active" : "Inactive")
        .focusable()
        .smoothAppear()
        .task(id: previewImage) {
            // Generate filtered preview when we have a source image
            if let sourceImage = previewImage {
                filteredPreview = applyEffectToPreview(sourceImage)
            }
        }
    }

    /// Apply this effect type to a preview image
    private func applyEffectToPreview(_ source: NSImage) -> NSImage? {
        guard let cgImage = source.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
            return source
        }

        let ciImage = CIImage(cgImage: cgImage)
        let effect = VideoEffect(type: effectType)

        guard let filtered = effect.apply(to: ciImage) else {
            return source
        }

        let context = CIContext()
        guard let outputCG = context.createCGImage(filtered, from: filtered.extent) else {
            return source
        }

        return NSImage(cgImage: outputCG, size: source.size)
    }
}

// MARK: - Active Effect Row (with slider)

struct ActiveEffectRow: View {
    let effect: VideoEffect
    let onIntensityChange: (Float) -> Void
    let onRemove: () -> Void

    @State private var intensity: Float

    init(effect: VideoEffect, onIntensityChange: @escaping (Float) -> Void, onRemove: @escaping () -> Void) {
        self.effect = effect
        self.onIntensityChange = onIntensityChange
        self.onRemove = onRemove
        _intensity = State(initialValue: effect.intensity)
    }

    var body: some View {
        HStack(spacing: 6) {
            // Icon
            Image(systemName: effect.type.icon)
                .font(.system(size: 12))
                .foregroundColor(.accentColor)
                .frame(width: 18)

            // Name
            Text(effect.type.displayName)
                .font(.caption2)
                .frame(width: 50, alignment: .leading)

            // Slider (if adjustable)
            if !effect.type.isBinary {
                Slider(value: $intensity, in: effect.type.intensityRange)
                    .controlSize(.small)
                    .accessibilityIdentifier("effects.active.\(effect.type.rawValue).intensity")
                    .onChange(of: intensity) { _, newValue in
                        // Live update while dragging for real-time preview
                        onIntensityChange(newValue)
                    }
            } else {
                Spacer()
                Text(String(localized: "effects.active.status.on", defaultValue: "On"))
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }

            // Remove button
            Button(action: onRemove, label: {
                Image(systemName: "xmark")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundColor(.secondary)
            })
            .buttonStyle(.plain)
            .accessibilityIdentifier("effects.active.\(effect.type.rawValue).remove")
        }
        .padding(.vertical, 4)
        .padding(.horizontal, 6)
        .background(Color.accentColor.opacity(0.1))
        .cornerRadius(6)
        .overlay(
            RoundedRectangle(cornerRadius: 6)
                .stroke(Color.accentColor.opacity(0.2), lineWidth: 1)
        )
        .smoothAppear()
    }
}
