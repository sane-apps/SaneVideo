import AVFoundation
import SwiftUI

struct SmartToolsSection: View {
  @Environment(AppState.self) var appState
  let clip: VideoClip

  @Binding var options: MagicFixOptions
  @Binding var isOperationInProgress: Bool

  var body: some View {
    // No nested ScrollView: the parent StylesInspectorView already scrolls.
    VStack(alignment: .leading, spacing: 12) {
      coreCleanupCard

      magicButton

      if appState.projectState.hasMagicFixResults(for: clip) {
        resetMagicFixButton
      }
    }
  }

  private var presetsMenu: some View {
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
          options = MagicFixOptions()
        } label: {
          Label("Reset to Defaults", systemImage: "arrow.counterclockwise")
        }
      } label: {
        Text("Presets")
          .font(.system(size: 13, weight: .medium))
      }
      .menuStyle(.borderlessButton)
      .fixedSize()
      .accessibilityIdentifier(AccessibilityIdentifiers.presetsMenu)
  }

  // MARK: - Core Cleanup Card (5 features only - 2025-12-31 refactor)

  private var coreCleanupCard: some View {
    VStack(alignment: .leading, spacing: 2) {
      HStack {
        Text("Choose what to fix, then press Clean Up.")
          .font(.system(size: 13))
          .foregroundStyle(Theme.Colors.textPrimary.opacity(0.85))
        Spacer()
        presetsMenu
      }
      .padding(.bottom, 4)
      VStack(spacing: 0) {
        InspectorToggle(
          title: "Remove Silence",
          subtitle: "Cut pauses where nobody talks",
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

        if options.removeSilence {
          VStack(alignment: .leading, spacing: 4) {
            HStack {
              Text("Quieter than")
                .font(.system(size: Theme.Typography.fontSizeSM, weight: .medium))
                .foregroundColor(.white)
              Spacer()
              Text("\(Int(options.silenceThreshold)) dB")
                .font(.system(size: Theme.Typography.fontSizeSM, weight: .semibold, design: .monospaced))
                .foregroundColor(.white)
            }
            Slider(value: $options.silenceThreshold, in: -60 ... -20, step: 1)
              .controlSize(.small)
              .tint(Theme.Colors.accent)
          }
          .padding(.leading, 30)
          .padding(.bottom, 6)
        }

        InspectorToggle(
          title: "Remove Fillers",
          subtitle: "Cut 'um', 'uh', stutters",
          isOn: $options.removeFillers,
          icon: "bubble.left",
          color: .blue,
          identifier: "Toggle_RemoveFillers"
        )
        .help("Removes hesitation words like 'um' and 'uh' from the timeline.")

        InspectorToggle(
          title: "Generate Captions",
          subtitle: "On-device transcription",
          isOn: $options.generateCaptions,
          icon: "captions.bubble",
          color: .blue,
          identifier: "Toggle_GenerateCaptions"
        )
        .help("Transcribe speech to text captions. Edit in the Transcript sidebar tab.")

        VStack(alignment: .leading, spacing: Theme.Dimensions.spacingXS) {
          InspectorToggle(
            title: "Enhance Speech",
            subtitle: "Clearer, more even voice",
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
          .help("Makes speech clearer and evens out the volume. For the cleanest voice, turn on Voice Isolation in the microphone menu before recording.")


        }

        InspectorToggle(
          title: "Smooth Cuts",
          subtitle: "Soften the jump at each cut",
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
        VStack(spacing: 12) {
          LoadingIndicator(
            message: appState.projectState.processingStatus,
            progress: appState.projectState.processingProgress
          )

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
        Button {
          guard !clip.isMissing else {
            ServiceContainer.shared.toastManager.show(
              "Cannot clean up: the clip file is missing. Use 'Locate File' in Clip Info to relink the file.",
              type: .error
            )
            return
          }

          ServiceContainer.shared.hapticsManager.impact()
          Task {
            await appState.projectState.performMagicFix(for: clip, options: options)
          }
        } label: {
          Label("Clean Up", systemImage: "wand.and.stars")
            .font(.system(size: 15, weight: .semibold))
            .frame(maxWidth: .infinity)
            .padding(.vertical, 6)
        }
        .buttonStyle(.borderedProminent)
        .controlSize(.large)
        .disabled(clip.isMissing || isOperationInProgress)
        .help(
          clip.isMissing
            ? "Clip file is missing. Use 'Locate File' in Clip Info to relink the file."
            : (isOperationInProgress
              ? "Operation in progress..."
              : "Automatically removes silence, filler words, and enhances your video")
        )
        .accessibilityIdentifier(AccessibilityIdentifiers.magicFixButton)
        .accessibilityLabel("Clean Up")
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
      Button {
        ServiceContainer.shared.hapticsManager.impact()
        Task {
          // Reset clears old results AND regenerates with current toggle settings
          await appState.projectState.resetMagicFix(for: clip, regenerate: true)
        }
      } label: {
        Label("Run Again With These Settings", systemImage: "arrow.counterclockwise")
          .font(.system(size: 13, weight: .medium))
          .frame(maxWidth: .infinity)
      }
      .buttonStyle(.borderless)
      .disabled(isOperationInProgress)
      .help("Clear all existing Magic Fix results and regenerate with your current toggle settings")
      .accessibilityIdentifier("magicFix.regenerateButton")
      .accessibilityLabel("Run Clean Up again")
      .accessibilityHint("Clears all existing Magic Fix results and automatically regenerates based on which toggles are currently enabled")
    }
  }
}
