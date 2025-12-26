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
    VStack(alignment: .leading, spacing: Theme.Dimensions.spacingXL) {
      // MARK: - Header & Presets
      headerView

      // MARK: - Action Card logic
      // UX FIX: Improved spacing for better visual breathing room
      VStack(spacing: Theme.Dimensions.spacingMD) {
        // Responsive Layout: Stacks vertically when width is constrained
        ViewThatFits(in: .horizontal) {
          // Option 1: Side-by-side (Wide)
          HStack(alignment: .top, spacing: Theme.Dimensions.spacingMD) {
            audioCard
            videoCard
          }

          // Option 2: Stacked (Narrow)
          VStack(spacing: Theme.Dimensions.spacingMD) {
            audioCard
            videoCard
          }
        }

        // Generative Card (full width)
        ToolCard(title: "Generative AI", icon: "sparkles", color: .orange) {
          ViewThatFits(in: .horizontal) {
            // Option 1: Side-by-side (Wide)
            HStack(spacing: Theme.Dimensions.spacingMD) {
              generativeToggles
            }

            // Option 2: Stacked (Narrow)
            VStack(spacing: Theme.Dimensions.spacingMD) {
              generativeToggles
            }
          }
        }
      }

      // Global Action Button
      magicButton

      Text(
        String(
          localized: "smart_tools.footer.description",
          defaultValue: "One-click AI cleanup for your entire clip.")
      )
      .font(.system(size: Theme.Typography.fontSizeXS))
      .foregroundColor(.secondary.opacity(Theme.Opacity.textTertiary))
      .frame(maxWidth: .infinity, alignment: .center)
      .padding(.top, Theme.Dimensions.spacingSM)
    }
    .padding(Theme.Dimensions.paddingLG)
  }

  private var headerView: some View {
    VStack(alignment: .leading, spacing: Theme.Dimensions.spacingSM) {
      HStack(alignment: .top) {
        VStack(alignment: .leading, spacing: Theme.Dimensions.spacingXS) {
          Text("Magic Fix")
            .font(.system(size: Theme.Typography.fontSizeXL, weight: .bold))
            .foregroundColor(.primary)
          Text("AI-Powered Polish")
            .font(.system(size: Theme.Typography.fontSizeSM))
            .foregroundColor(.secondary)
        }
        Spacer()
        Menu {
          Button {
            options = .minimal
          } label: {
            Label("Minimal Fix", systemImage: "scissors")
          }
          .accessibilityIdentifier(AccessibilityIdentifiers.presetMinimal)

          Button {
            options = .proClean
          } label: {
            Label("Pro Clean-up", systemImage: "sparkles")
          }
          .accessibilityIdentifier(AccessibilityIdentifiers.presetProClean)

          Button {
            options = .socialMedia
          } label: {
            Label("Social Media Ready", systemImage: "square.stack.3d.up")
          }
          .accessibilityIdentifier(AccessibilityIdentifiers.presetSocialMedia)
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

      // Preset description and privacy badge
      HStack(alignment: .center) {
        if !options.presetName.isEmpty && options.presetName != "Custom" {
          Text(options.presetDescription)
            .font(.system(size: Theme.Typography.fontSizeXS))
            .foregroundColor(.secondary)
            .lineLimit(1)
        }
        Spacer()
        PrivacyBadge()
      }
    }
  }

  private var audioCard: some View {
    ToolCard(title: "Audio Cleanup", icon: "waveform", color: .blue) {
      VStack(spacing: Theme.Dimensions.spacingMD) {
        InspectorToggle(
          title: "Remove Silence",
          subtitle: "Cut non-speech gaps",
          isOn: Binding(
            get: { options.removeSilence },
            set: { newValue in
              options.removeSilence = newValue
              // LIVE PREVIEW: Use Gating as proxy for silence removal preview
              appState.projectState.updateClipGating(clipId: clip.id, enabled: newValue)
            }
          ),
          icon: "waveform.slash",
          color: .blue,
          identifier: "Toggle_RemoveSilence"
        )
        .help(
          "Automatically cuts segments of the video where no speech is detected (Timeline Edit).")

        // UX FIX: Improved spacing and typography for advanced settings
        if options.removeSilence {
          VStack(alignment: .leading, spacing: Theme.Dimensions.spacingSM) {
            HStack {
              Text("Threshold")
                .font(.system(size: Theme.Typography.fontSizeSM, weight: .medium))
                .foregroundColor(.secondary)
              Spacer()
              Text("\(Int(options.silenceThreshold)) dB")
                .font(
                  .system(size: Theme.Typography.fontSizeSM, weight: .semibold, design: .monospaced)
                )
                .foregroundColor(.primary)
            }
            Slider(value: $options.silenceThreshold, in: -60 ... -20, step: 1)
              .controlSize(.small)
              .tint(.blue)
              .help("Audio levels below this threshold will be considered silence.")
          }
          .padding(.vertical, Theme.Dimensions.paddingXS)
          .padding(.horizontal, Theme.Dimensions.paddingXS)
          .background(Color.blue.opacity(Theme.Opacity.subtle))
          .cornerRadius(Theme.Dimensions.smallCornerRadius)
        }

        InspectorToggle(
          title: "Remove Fillers",
          subtitle: "Cut 'um', 'uh', stutters",
          isOn: $options.removeFillers,
          icon: "bubble.left",
          color: .blue,
          identifier: "Toggle_RemoveFillers"
        )
        .help("Detects and removes hesitation words like 'um' and 'uh' from the timeline.")

        InspectorToggle(
          title: "Enhance Speech",
          subtitle: "Isolate voice & remove noise",
          isOn: Binding(
            get: { options.enhanceAudio },
            set: { newValue in
              options.enhanceAudio = newValue
              // LIVE PREVIEW: Use Voice Isolation for enhancement preview
              appState.projectState.updateClipVoiceIsolation(clipId: clip.id, enabled: newValue)
            }
          ),
          icon: "mic.fill",
          color: .blue,
          identifier: "Toggle_EnhanceSpeech"
        )
        .help("Applies EQ, Compression, and AI Voice Isolation to clean up background noise.")
      }
    }
    .frame(maxWidth: .infinity)
  }

  private var videoCard: some View {
    ToolCard(title: "Video & Framing", icon: "video", color: .purple) {
      VStack(spacing: Theme.Dimensions.spacingMD) {
        InspectorToggle(
          title: "Auto Color",
          subtitle: "Light & color fix",
          isOn: Binding(
            get: { options.autoEnhance },
            set: { newValue in
              options.autoEnhance = newValue
              // LIVE PREVIEW: Apply or remove effect immediately
              if newValue {
                appState.projectState.applyEffect(to: clip, effect: VideoEffect(type: .autoEnhance))
              } else {
                appState.projectState.removeEffect(from: clip, type: .autoEnhance)
              }
            }
          ),
          icon: "paintpalette",
          color: .purple,
          identifier: "Toggle_AutoColor"
        )
        .help("Automatically adjusts brightness, contrast, and saturation (Instant Preview).")

        InspectorToggle(
          title: "Smart Crop (9:16)",
          subtitle: "Auto vertical reframe",
          isOn: $options.smartCrop,
          icon: "iphone",
          color: .purple
        )
        .help("Reframes horizontal video to vertical (9:16) keeping the subject centered.")

        InspectorToggle(
          title: "Auto-Framing",
          subtitle: "Track faces & focus",
          isOn: $options.autoFraming,
          icon: "target",
          color: .purple
        )
        .help("Keeps the subject centered in the frame even if they move.")
      }
    }
    .frame(maxWidth: .infinity)
  }

  // Helper to avoid duplication in ViewThatFits
  @ViewBuilder
  private var generativeToggles: some View {
    InspectorToggle(
      title: "Magic Remove",
      subtitle: "AI object removal",
      isOn: $options.magicRemovePeople,
      icon: "person.badge.minus",
      color: .orange
    )
    .help("Automatically detects and removes people or distracting objects from the background.")

    InspectorToggle(
      title: "Cinematic Styles",
      subtitle: "Prompt-based restyling",
      isOn: $options.generativeStyle,
      icon: "camera.filters",
      color: .orange
    )
    .help(
      "Applies generative filters to give your video a specific look (e.g. 'Vintage', 'Cyberpunk')."
    )
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
}

// MARK: - Visual Components

struct ToolCard<Content: View>: View {
  let title: String
  let icon: String
  let color: Color
  let content: Content

  init(title: String, icon: String, color: Color, @ViewBuilder content: () -> Content) {
    self.title = title
    self.icon = icon
    self.color = color
    self.content = content()
  }

  var body: some View {
    VStack(alignment: .leading, spacing: Theme.Dimensions.spacingMD) {
      HStack(spacing: Theme.Dimensions.spacingSM) {
        Image(systemName: icon)
          .foregroundColor(color)
          .font(.system(size: Theme.Typography.iconSizeXS, weight: .semibold))
        Text(title.uppercased())
          .font(.system(size: Theme.Typography.fontSizeXS, weight: .bold))
          .foregroundColor(.secondary)
          .tracking(0.5)
        Spacer()
      }

      content
    }
    .padding(Theme.Dimensions.paddingMD)
    .background(Color.secondary.opacity(Theme.Opacity.subtle))
    .cornerRadius(Theme.Dimensions.cornerRadius)
    .overlay(
      RoundedRectangle(cornerRadius: Theme.Dimensions.cornerRadius)
        .stroke(Color.secondary.opacity(Theme.Opacity.light), lineWidth: 0.5)
    )
    .enhancedLiquidGlass(radius: Theme.Dimensions.cornerRadius, opacity: Theme.Opacity.strong)
    .smoothAppear()
    .frame(minWidth: 160, maxWidth: .infinity)
  }
}

// Reusing style from likely existing components or defining here for safety
private struct InspectorToggle: View {
  let title: String
  let subtitle: String
  @Binding var isOn: Bool
  let icon: String
  var color: Color = .purple  // Default for safety, but calls should override
  var identifier: String?

  var body: some View {
    HStack(alignment: .center, spacing: Theme.Dimensions.spacingMD) {
      // Icon - UX FIX: Better sizing and visual feedback
      Image(systemName: icon)
        .font(.system(size: Theme.Typography.iconSizeSM))
        .frame(width: 28, height: 28)
        .background(
          isOn ? color.opacity(Theme.Opacity.light) : Color.gray.opacity(Theme.Opacity.light)
        )
        .foregroundColor(isOn ? color : .secondary)
        .cornerRadius(Theme.Dimensions.smallCornerRadius)

      // Text content - UX FIX: Improved typography and spacing
      VStack(alignment: .leading, spacing: Theme.Dimensions.spacingXS) {
        Text(title)
          .font(.system(size: Theme.Typography.fontSizeMD, weight: .semibold))
          .foregroundColor(.primary)
          .lineLimit(2)
          .multilineTextAlignment(.leading)
        Text(subtitle)
          .font(.system(size: Theme.Typography.fontSizeSM))
          .foregroundColor(.secondary)
          .lineLimit(2)
          .multilineTextAlignment(.leading)
      }
      .frame(minWidth: 100, maxWidth: .infinity, alignment: .leading)

      // Spacer with minimum length
      Spacer(minLength: Theme.Dimensions.spacingXS)

      // Toggle - UX FIX: Better sizing
      Toggle("", isOn: $isOn)
        .labelsHidden()
        .toggleStyle(.switch)
        .tint(color)
        .accessibilityLabel(title)
        .accessibilityIdentifier(identifier ?? "Toggle_\(title)")
        .controlSize(.small)
    }
    .frame(minWidth: 160, maxWidth: .infinity, alignment: .leading)
    .padding(.vertical, Theme.Dimensions.spacingXS)
    .accessibilityIdentifier(
      identifier != nil
        ? "Row_\(identifier!.replacingOccurrences(of: "Toggle_", with: ""))" : "Row_\(title)")
  }
}

// Helper for contrast
extension Color {
  func isLight() -> Bool {
    // Simple heuristic for contrast text
    // In a real design system we'd check luminance
    // For standard Yellow/Cyan this is usually true, for Blue/Purple false
    return false  // Defaulting to white text for now as most accents are dark enough or we want white on buttons
  }
}

// MARK: - Magic Progress Island

struct MagicProgressOverlay: View {
  let isProcessing: Bool
  let status: String?
  let progress: Double

  // Smooth animation namespace
  @Namespace private var namespace

  var body: some View {
    Group {
      if isProcessing {
        HStack(spacing: 16) {
          // 1. Animated Icon
          ZStack {
            Circle()
              .fill(Theme.Colors.accent.opacity(0.2))
              .frame(width: 32, height: 32)

            Image(systemName: "sparkles")
              .font(.system(size: Theme.Typography.iconSizeSM, weight: .semibold))
              .foregroundStyle(Theme.Colors.accent)
              .symbolEffect(.bounce.up.byLayer, options: .repeating)
          }

          VStack(alignment: .leading, spacing: Theme.Dimensions.spacingXS) {
            // 2. Status Text (Animated transition)
            Text(status ?? "Processing...")
              .font(.system(size: Theme.Typography.fontSizeMD, weight: .medium))
              .foregroundStyle(.primary)
              .contentTransition(.numericText(value: 0))
              .animation(.snappy, value: status)
              .lineLimit(1)

            // 3. Progress Bar
            GeometryReader { geo in
              ZStack(alignment: .leading) {
                Capsule()
                  .fill(Color.primary.opacity(Theme.Opacity.light))
                  .frame(height: 4)

                Capsule()
                  .fill(Theme.Colors.accentGradient)
                  .frame(width: geo.size.width * CGFloat(progress), height: 4)
                  .animation(.smooth(duration: 0.4), value: progress)
              }
            }
            .frame(height: 4)
          }
          .frame(maxWidth: .infinity, alignment: .leading)

          // 4. Percentage text
          Text("\(Int(progress * 100))%")
            .font(.system(size: Theme.Typography.fontSizeSM, weight: .bold))
            .foregroundStyle(.secondary)
            .monospacedDigit()
            .contentTransition(.numericText())
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .frame(width: 320)
        .background(.ultraThinMaterial)
        .background(
          RoundedRectangle(cornerRadius: 30)
            .fill(Color(nsColor: .windowBackgroundColor).opacity(0.5))
        )
        .clipShape(RoundedRectangle(cornerRadius: 30))
        .overlay(
          RoundedRectangle(cornerRadius: 30)
            .stroke(Theme.Colors.accent.opacity(0.3), lineWidth: 1)
        )
        .shadow(color: Color.black.opacity(0.2), radius: 20, x: 0, y: 10)
        // Use a standard transition instead of asymmetric which might be causing type-check issues if too complex
        .transition(.move(edge: .top).combined(with: .opacity))
      }
    }
    .animation(.spring(response: 0.5, dampingFraction: 0.7), value: isProcessing)
    .padding(.top, 40)  // Position nicely below toolbar
    .accessibilityIdentifier(AccessibilityIdentifiers.magicProgressOverlay)
  }
}
