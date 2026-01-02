//
//  SmartToolsSection.swift
//  SaneVideo
//
//  Created by SaneVideo Refactor
//

import AVFoundation
import SwiftUI

// Import new modifiers
// AnimationModifiers, AccessibilityModifiers

struct SmartToolsSection: View {
  @Environment(AppState.self) var appState
  let clip: VideoClip

  @Binding var options: MagicFixOptions
  @Binding var isOperationInProgress: Bool

  // We bind to the options from ProjectState parent, but simpler to just access via environment if we want
  // But adhering to pattern: usually sections take bindings or the clip.
  // Since options are in ProjectState, let's bind to them.

  var body: some View {
    // CRITICAL FIX: Remove nested ScrollView - parent StylesInspectorView already has ScrollView
    // Nested ScrollViews cause scrolling conflicts and performance issues
    VStack(alignment: .leading, spacing: Theme.Dimensions.spacingMD) {
      // MARK: - Header & Presets
      headerView

      // MARK: - Core Cleanup Card (simplified UI - 2025-12-31)
      // Only 5 core features: Remove Silence, Remove Fillers, Generate Captions, Enhance Speech, Smooth Cuts
      // Other features (Smart Crop, Auto-Framing, Find Highlights) are in their canonical locations
      coreCleanupCard

      // Global Action Button
      magicButton

      // CRITICAL FIX: Reset/Regenerate button when Magic Fix has been applied
      if appState.projectState.hasMagicFixResults(for: clip) {
        resetMagicFixButton
      }
    }
    .padding(Theme.Dimensions.paddingMD)
  }

  private var headerView: some View {
    // COMPACT: Single row with title and presets menu
    // NOTE: PrivacyBadge moved to InspectorHeader (always visible)
    HStack(alignment: .center) {
      Text("Magic Fix")
        .font(.system(size: Theme.Typography.fontSizeLG, weight: .bold))
        .foregroundColor(.primary)

      Spacer()

      Menu {
        Button {
          options = .minimal
        } label: {
          Label("Quick Fix", systemImage: "hare")
        }
        .accessibilityIdentifier(AccessibilityIdentifiers.presetMinimal)
        .help("Remove silence only - fastest option")

        Button {
          options = .proClean
        } label: {
          Label("Full Cleanup", systemImage: "sparkles")
        }
        .accessibilityIdentifier(AccessibilityIdentifiers.presetProClean)
        .help("All 5 core cleanup features enabled")

        Divider()

        Button {
          // Reset to defaults
          options = MagicFixOptions()
        } label: {
          Label("Reset to Defaults", systemImage: "arrow.counterclockwise")
        }
      } label: {
        Label("Presets", systemImage: "slider.horizontal.3")
          .font(.system(size: Theme.Typography.fontSizeSM, weight: .semibold))
          .padding(.horizontal, Theme.Dimensions.paddingSM)
          .padding(.vertical, Theme.Dimensions.paddingXS)
          .background(Theme.Colors.secondaryBackground)
          .cornerRadius(Theme.Dimensions.smallCornerRadius)
          .overlay(
            RoundedRectangle(cornerRadius: Theme.Dimensions.smallCornerRadius)
              .stroke(Color.secondary.opacity(Theme.Opacity.medium), lineWidth: 0.5)
          )
      }
      .menuStyle(.button)
      .buttonStyle(.plain)
      .accessibilityIdentifier(AccessibilityIdentifiers.presetsMenu)
    }
  }

  // MARK: - Core Cleanup Card (5 features only - 2025-12-31 refactor)
  // Features removed from Magic Fix UI (use canonical locations instead):
  // - Smart Crop → VideoSection.swift
  // - Auto-Framing → VideoSection.swift
  // - Auto Color → VideoSection.swift (Effects)
  // - Find Highlights → AudioSection.swift
  // - Magic Remove / Cinematic Styles → Future generative features

  private var coreCleanupCard: some View {
    ToolCard(title: "Core Cleanup", icon: "waveform.badge.magnifyingglass", color: .blue) {
      VStack(spacing: Theme.Dimensions.spacingMD) {
        // 1. Remove Silence
        InspectorToggle(
          title: "Remove Silence",
          subtitle: "Cut non-speech gaps",
          isOn: Binding(
            get: { options.removeSilence },
            set: { [clip] newValue in
              options.removeSilence = newValue
              let clipId = clip.id
              Task { @MainActor in
                appState.projectState.updateClipGating(clipId: clipId, enabled: newValue)
              }
            }
          ),
          icon: "waveform.slash",
          color: .blue,
          identifier: "Toggle_RemoveSilence"
        )
        .help("Automatically cuts segments where no speech is detected.")

        // Silence threshold slider (shown when enabled)
        if options.removeSilence {
          VStack(alignment: .leading, spacing: Theme.Dimensions.spacingSM) {
            HStack {
              Text("Threshold")
                .font(.system(size: Theme.Typography.fontSizeSM, weight: .medium))
                .foregroundColor(.secondary)
              Spacer()
              Text("\(Int(options.silenceThreshold)) dB")
                .font(.system(size: Theme.Typography.fontSizeSM, weight: .semibold, design: .monospaced))
                .foregroundColor(.primary)
            }
            Slider(value: $options.silenceThreshold, in: -60 ... -20, step: 1)
              .controlSize(.small)
              .tint(.accentColor)
          }
          .padding(.vertical, Theme.Dimensions.paddingXS)
          .padding(.horizontal, Theme.Dimensions.paddingXS)
          .background(Color.accentColor.opacity(Theme.Opacity.subtle))
          .cornerRadius(Theme.Dimensions.smallCornerRadius)
        }

        // 2. Remove Fillers
        InspectorToggle(
          title: "Remove Fillers",
          subtitle: "Cut 'um', 'uh', stutters",
          isOn: $options.removeFillers,
          icon: "bubble.left",
          color: .blue,
          identifier: "Toggle_RemoveFillers"
        )
        .help("Removes hesitation words like 'um' and 'uh' from the timeline.")

        // 3. Generate Captions
        InspectorToggle(
          title: "Generate Captions",
          subtitle: "AI transcription",
          isOn: $options.generateCaptions,
          icon: "captions.bubble",
          color: .blue,
          identifier: "Toggle_GenerateCaptions"
        )
        .help("Transcribe speech to text captions. Edit in the Transcript sidebar tab.")

        // 4. Enhance Speech
        VStack(alignment: .leading, spacing: Theme.Dimensions.spacingXS) {
          InspectorToggle(
            title: "Enhance Speech",
            subtitle: "EQ boost & noise reduction",
            isOn: Binding(
              get: { options.enhanceAudio },
              set: { [clip] newValue in
                options.enhanceAudio = newValue
                let clipId = clip.id
                Task { @MainActor in
                  appState.projectState.updateClipVoiceIsolation(clipId: clipId, enabled: newValue)
                }
              }
            ),
            icon: "mic.fill",
            color: .blue,
            identifier: "Toggle_EnhanceSpeech"
          )
          .help("Vocal presence EQ and noise reduction. Voice isolation is applied during playback only.")

          // Limitation note: Voice isolation is real-time only (AUSoundIsolation limitation)
          if options.enhanceAudio {
            Text("Voice isolation applies during playback only")
              .font(.system(size: Theme.Typography.fontSizeXS))
              .foregroundStyle(.secondary)
              .padding(.leading, 28) // Align with toggle text
          }
        }

        // 5. Smooth Cuts
        InspectorToggle(
          title: "Smooth Cuts",
          subtitle: "Blend jump cuts",
          isOn: $options.smoothJumpCuts,
          icon: "scissors",
          color: .blue,
          identifier: "Toggle_SmoothCuts"
        )
        .help("Apply morph-cut style smoothing to jump cuts created by silence/filler removal.")
      }
    }
    .frame(maxWidth: .infinity)
  }

  private var magicButton: some View {
    Group {
      if appState.projectState.isProcessing {
        // P0 FIX: Enhanced progress indicator with cancel button
        VStack(spacing: 12) {
          LoadingIndicator(
            message: appState.projectState.processingStatus,
            progress: appState.projectState.processingProgress
          )

          // P0 FIX: Cancel button
          Button {
            appState.projectState.cancelCurrentOperation()
          } label: {
            Text("Cancel")
              .font(.system(size: Theme.Typography.fontSizeSM))
          }
          .buttonStyle(.bordered)
          .controlSize(.small)
          .accessibilityIdentifier(AccessibilityIdentifiers.magicFixCancelButton)
        }
        .transition(.smoothScale)
      } else {
        // P1 FIX: Enhanced button with better visual hierarchy
        Button {
          // CRITICAL FIX: Validate clip before operation
          guard !clip.isMissing else {
            ServiceContainer.shared.toastManager.show(
              "Cannot apply Magic Fix: Clip file is missing. Use 'Locate File' in Clip Info to relink the file.",
              type: .error
            )
            return
          }

          ServiceContainer.shared.hapticsManager.impact()
          Task {
            await appState.projectState.performMagicFix(for: clip, options: options)
          }
        } label: {
          VStack(spacing: Theme.Dimensions.spacingSM) {
            HStack(spacing: Theme.Dimensions.spacingMD) {
              Image(systemName: "wand.and.stars")
                .font(.system(size: Theme.Typography.iconSizeLG, weight: .bold))

              Text("Apply Magic Fix")
                .font(.system(size: Theme.Typography.fontSizeLG, weight: .bold))
            }

            // UX FIX: Show what will be applied with better typography
            if !options.isEmpty {
              Text(options.summary)
                .font(.system(size: Theme.Typography.fontSizeXS, weight: .medium))
                .opacity(Theme.Opacity.textTertiary)
                .lineLimit(2)
                .multilineTextAlignment(.center)
            }
          }
          .frame(maxWidth: .infinity)
          .padding(.vertical, Theme.Dimensions.paddingLG)
          .background(Theme.Colors.accentGradient)
          .foregroundColor(Theme.Colors.accent.isLight() ? .black : .white)
          .cornerRadius(Theme.Dimensions.largeCornerRadius)
          .shadow(color: Theme.Colors.accent.opacity(Theme.Opacity.heavy), radius: 12, x: 0, y: 6)
        }
        .buttonStyle(.plain)
        .disabled(clip.isMissing || isOperationInProgress)
        .help(
          clip.isMissing
            ? "Clip file is missing. Use 'Locate File' in Clip Info to relink the file."
            : (isOperationInProgress
              ? "Operation in progress..."
              : "Automatically removes silence, filler words, and enhances your video")
        )
        .accessibilityIdentifier(AccessibilityIdentifiers.magicFixButton)
        .accessibilityLabel("Apply Magic Fix")
        .accessibilityHint(
          clip.isMissing
            ? "Clip file is missing. Use 'Locate File' in Clip Info to relink the file."
            : (isOperationInProgress
              ? "Operation in progress"
              : "Automatically removes silence, filler words, and enhances your video. Keyboard shortcut: Command Shift M")
        )
        .accessibilityValue(isOperationInProgress ? "Processing" : "")
      }
    }
  }

  // MARK: - Reset Magic Fix Button

  private var resetMagicFixButton: some View {
    VStack(spacing: 8) {
      Divider()
        .padding(.vertical, 4)

      Button {
        ServiceContainer.shared.hapticsManager.impact()
        Task {
          // CRITICAL FIX: Reset clears old results AND regenerates with current toggle settings
          await appState.projectState.resetMagicFix(for: clip, regenerate: true)
        }
      } label: {
        HStack(spacing: Theme.Dimensions.spacingSM) {
          Image(systemName: "arrow.counterclockwise")
            .font(.system(size: Theme.Typography.iconSizeMD, weight: .medium))

          Text("Regenerate Magic Fix")
            .font(.system(size: Theme.Typography.fontSizeMD, weight: .semibold))
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, Theme.Dimensions.paddingMD)
        .background(Color.secondary.opacity(0.1))
        .foregroundColor(.secondary)
        .cornerRadius(Theme.Dimensions.cornerRadius)
      }
      .buttonStyle(.plain)
      .disabled(isOperationInProgress)
      .help("Clear all existing Magic Fix results and regenerate with your current toggle settings")
      .accessibilityIdentifier("magicFix.regenerateButton")
      .accessibilityLabel("Regenerate Magic Fix")
      .accessibilityHint("Clears all existing Magic Fix results and automatically regenerates based on which toggles are currently enabled")
    }
  }
}

// Components moved to SmartToolsComponents.swift and MagicProgressOverlay.swift
