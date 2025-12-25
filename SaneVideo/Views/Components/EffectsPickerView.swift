//
//  EffectsPickerView.swift
//  SaneVideo
//
//  Created by SaneVideo Refactor
//  Redesigned: Direct effect tiles using Apple's CIFilter effects
//

import SwiftUI

struct EffectsPickerView: View {
    @Environment(AppState.self) var appState
    let clip: VideoClip
    @Binding var isOperationInProgress: Bool

    @State private var effects: [VideoEffect]
    @State private var selectedCategory: EffectCategory = .looks

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
            // Smart Actions
            Button(action: {
                Task {
                    await appState.projectState.applySmartColorGrade(to: clip)
                }
            }, label: {
                HStack(spacing: 4) {
                    Image(systemName: "wand.and.stars")
                        .foregroundColor(.purple)
                    Text(String(localized: "effects.action.auto_grade", defaultValue: "Auto-Grade (AI)"))
                        .foregroundColor(.primary)
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
                .padding(8)
                .background(Color.purple.opacity(0.1))
                .cornerRadius(6)
                .overlay(
                    RoundedRectangle(cornerRadius: 6)
                        .stroke(Color.purple.opacity(0.3), lineWidth: 1)
                )
            })
            .buttonStyle(.plain)
            .hoverScale(1.02)
            .pressScale()
            .disabled(clip.isMissing || isOperationInProgress) // CRITICAL FIX: Disable if clip is missing or operation in progress
            .help(clip.isMissing ? "Clip file is missing. Use 'Locate File' in Clip Info to relink the file." : (isOperationInProgress ? "Another operation is in progress" : "Automatically applies color grading to the video"))
            .padding(.bottom, 4)
            .accessibilityIdentifier("effects.action.auto_grade")
            .accessibilityLabel("Auto-Grade")
            .accessibilityHint(clip.isMissing ? "Clip file is missing. Use 'Locate File' in Clip Info to relink the file." : (isOperationInProgress ? "Another operation is in progress" : "Automatically applies color grading to the video"))
            .focusable() // P0 FIX: Keyboard navigation
            .smoothAppear()

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

            // P1 FIX: Larger effect tiles grid (64x64px minimum)
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 64), spacing: 8)], spacing: 8) {
                ForEach(effectsForCategory) { effectType in
                    EffectTile(
                        effectType: effectType,
                        isActive: effects.contains { $0.type == effectType },
                        id: "effects.tile.\(effectType.rawValue)",
                        onTap: { toggleEffect(effectType) }
                    )
                }
            }
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
}

// MARK: - Effect Tile (Tappable)

struct EffectTile: View {
    let effectType: VideoEffectType
    let isActive: Bool
    let id: String
    let onTap: () -> Void
    
    // P1 FIX: State for hover preview
    @State private var isHovering = false

    var body: some View {
        Button(action: onTap, label: {
            VStack(spacing: 4) {
                ZStack {
                    // P1 FIX: Larger tile (64x64px)
                    RoundedRectangle(cornerRadius: 8)
                        .fill(isActive ? Color.accentColor : Color.secondary.opacity(0.15))
                        .frame(width: 64, height: 64)
                        .overlay(
                            RoundedRectangle(cornerRadius: 8)
                                .stroke(isActive ? Color.accentColor : Color.clear, lineWidth: 2)
                        )

                    Image(systemName: effectType.icon)
                        .font(.system(size: 20)) // P1 FIX: Larger icon
                        .foregroundColor(isActive ? .white : .primary)

                    // Checkmark badge when active
                    if isActive {
                        VStack {
                            HStack {
                                Spacer()
                                Image(systemName: "checkmark.circle.fill")
                                    .font(.system(size: 14)) // P1 FIX: Larger checkmark
                                    .foregroundColor(.white)
                                    .background(Circle().fill(Color.accentColor))
                            }
                            Spacer()
                        }
                        .frame(width: 64, height: 64)
                        .offset(x: 4, y: -4)
                    }
                }

                Text(effectType.displayName)
                    .font(.system(size: 10)) // P1 FIX: Slightly larger text
                    .fontWeight(isActive ? .bold : .regular)
                    .foregroundColor(isActive ? .accentColor : .secondary)
                    .lineLimit(1)
            }
        })
        .buttonStyle(.plain)
        .hoverScale(1.1)
        .pressScale()
        .shadow(color: isActive ? Color.accentColor.opacity(0.3) : .clear, radius: 6, x: 0, y: 3)
        .animation(.smoothUI, value: isActive)
        .help(isActive ? 
            String(localized: "effects.tile.remove", defaultValue: "Remove") + " \(effectType.displayName)" : 
            String(localized: "effects.tile.apply", defaultValue: "Apply") + " \(effectType.displayName)")
        // P0 FIX: Enhanced accessibility
        .accessibilityIdentifier(id)
        .accessibilityLabel(effectType.displayName)
        .accessibilityHint(isActive ? "Remove \(effectType.displayName) effect" : "Apply \(effectType.displayName) effect")
        .accessibilityValue(isActive ? "Active" : "Inactive")
        // P0 FIX: Keyboard navigation
        .focusable()
        .smoothAppear()
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
                    .controlSize(.mini)
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
