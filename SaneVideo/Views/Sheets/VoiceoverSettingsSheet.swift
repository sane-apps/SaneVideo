//
//  VoiceoverSettingsSheet.swift
//  SaneVideo
//
//  Settings sheet for voiceover generation
//  Exposes voice selection, speed, and pitch controls
//

import AppKit
import CoreMedia
import SwiftUI

/// Sheet for configuring voiceover settings before generation
struct VoiceoverSettingsSheet: View {
    @Environment(\.dismiss) private var dismiss
    var voiceoverService = ServiceContainer.shared.voiceoverService

    let captions: [Caption]
    let projectName: String
    let onGenerate: (URL) -> Void

    @State private var isGenerating = false
    @State private var errorMessage: String?

    var body: some View {
        @Bindable var voiceoverService = voiceoverService
        return VStack(spacing: 0) {
            SheetHeader(
                title: String(localized: "voiceover.header.title", defaultValue: "Generate Voiceover"),
                subtitle: "\(captions.count) captions - ~\(formattedDuration)",
                dismissAction: { dismiss() },
                accessibilityID: "voiceover.sheet.close"
            )

            Divider()

            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    voiceSection
                    Divider()
                    settingsSection
                    Divider()
                    previewSection

                    if let error = errorMessage {
                        Text(error)
                            .foregroundStyle(.red)
                            .font(.caption)
                    }
                }
                .padding(20)
            }

            Divider()

            SheetFooter(
                actionTitle: String(localized: "voiceover.action.generate", defaultValue: "Generate Voiceover"),
                isLoading: isGenerating,
                loadingTitle: String(localized: "voiceover.action.generating", defaultValue: "Generating..."),
                isDisabled: captions.isEmpty,
                cancelID: "voiceover.action.cancel",
                actionID: "voiceover.action.generate",
                onCancel: { dismiss() },
                onAction: { generateVoiceover() }
            )
        }
        .frame(width: 450, height: 520)
        .subtleGlass(radius: 12)
        .onAppear {
            voiceoverService.loadAvailableVoices()
        }
    }

    // MARK: - Sections

    private var voiceSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label(
                String(localized: "voiceover.voice.header", defaultValue: "Voice"),
                systemImage: "person.wave.2.fill"
            )
            .font(.subheadline.weight(.semibold))

            LazyVGrid(columns: [
                GridItem(.flexible()),
                GridItem(.flexible())
            ], spacing: 8) {
                ForEach(voiceoverService.availableVoices.prefix(8)) { voice in
                    VoiceButton(
                        voice: voice,
                        isSelected: voiceoverService.selectedVoiceId == voice.identifier,
                        onSelect: { voiceoverService.selectedVoiceId = voice.identifier }
                    )
                    .accessibilityIdentifier("voiceover.voice.\(voice.identifier)")
                }
            }
        }
    }

    private var settingsSection: some View {
        @Bindable var voiceoverService = voiceoverService
        // Create Double bindings from Float properties
        let speechRateBinding = Binding<Double>(
            get: { Double(voiceoverService.speechRate) },
            set: { voiceoverService.speechRate = Float($0) }
        )
        let pitchBinding = Binding<Double>(
            get: { Double(voiceoverService.pitchMultiplier) },
            set: { voiceoverService.pitchMultiplier = Float($0) }
        )

        return VStack(alignment: .leading, spacing: 16) {
            Label(
                String(localized: "voiceover.settings.header", defaultValue: "Settings"),
                systemImage: "slider.horizontal.3"
            )
            .font(.subheadline.weight(.semibold))

            LabeledSliderControl(
                label: String(localized: "voiceover.settings.speed.title", defaultValue: "Speed"),
                value: speechRateBinding,
                range: 0.25...1.0,
                step: 0.05,
                valueFormatter: { _ in speedLabel },
                minLabel: String(localized: "voiceover.settings.speed.slower", defaultValue: "Slower"),
                maxLabel: String(localized: "voiceover.settings.speed.faster", defaultValue: "Faster"),
                accessibilityID: "voiceover.settings.speed"
            )

            LabeledSliderControl(
                label: String(localized: "voiceover.settings.pitch.title", defaultValue: "Pitch"),
                value: pitchBinding,
                range: 0.5...2.0,
                step: 0.1,
                valueFormatter: { _ in pitchLabel },
                minLabel: String(localized: "voiceover.settings.pitch.lower", defaultValue: "Lower"),
                maxLabel: String(localized: "voiceover.settings.pitch.higher", defaultValue: "Higher"),
                accessibilityID: "voiceover.settings.pitch"
            )
        }
    }

    private var previewSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label(
                String(localized: "voiceover.preview.header", defaultValue: "Preview"),
                systemImage: "play.circle.fill"
            )
            .font(.subheadline.weight(.semibold))

            HStack {
                Button {
                    voiceoverService.previewVoice(voiceoverService.selectedVoiceId)
                } label: {
                    Label(
                        String(localized: "voiceover.preview.play", defaultValue: "Play Sample"),
                        systemImage: "speaker.wave.2.fill"
                    )
                }
                .buttonStyle(.bordered)
                .accessibilityIdentifier("voiceover.preview.play")

                Button {
                    voiceoverService.stopPreview()
                } label: {
                    Label(
                        String(localized: "voiceover.preview.stop", defaultValue: "Stop"),
                        systemImage: "stop.fill"
                    )
                }
                .buttonStyle(.bordered)
                .accessibilityIdentifier("voiceover.preview.stop")
            }
        }
    }

    // MARK: - Computed Properties

    private var formattedDuration: String {
        let text = captions.map { $0.text }.joined(separator: " ")
        let duration = voiceoverService.estimateDuration(for: text)
        let minutes = Int(duration) / 60
        let seconds = Int(duration) % 60
        return String(format: "%d:%02d", minutes, seconds)
    }

    private var speedLabel: String {
        if voiceoverService.speechRate < 0.4 {
            return String(localized: "voiceover.settings.speed.slow", defaultValue: "Slow")
        } else if voiceoverService.speechRate > 0.6 {
            return String(localized: "voiceover.settings.speed.fast", defaultValue: "Fast")
        } else {
            return String(localized: "voiceover.settings.speed.normal", defaultValue: "Normal")
        }
    }

    private var pitchLabel: String {
        if voiceoverService.pitchMultiplier < 0.8 {
            return String(localized: "voiceover.settings.pitch.low", defaultValue: "Low")
        } else if voiceoverService.pitchMultiplier > 1.2 {
            return String(localized: "voiceover.settings.pitch.high", defaultValue: "High")
        } else {
            return String(localized: "voiceover.settings.pitch.normal", defaultValue: "Normal")
        }
    }

    // MARK: - Actions

    private func generateVoiceover() {
        isGenerating = true
        errorMessage = nil

        Task {
            do {
                let savePanel = NSSavePanel()
                savePanel.allowedContentTypes = [.audio]
                savePanel.nameFieldStringValue = "\(projectName)_Voiceover.m4a"

                let response = await savePanel.beginSheetModal(for: NSApp.keyWindow!)

                guard response == .OK, let url = savePanel.url else {
                    isGenerating = false
                    return
                }

                try await voiceoverService.generateVoiceoverFromCaptions(captions, outputURL: url)

                await MainActor.run {
                    isGenerating = false
                    onGenerate(url)
                    dismiss()
                }
            } catch {
                await MainActor.run {
                    isGenerating = false
                    errorMessage = error.localizedDescription
                }
            }
        }
    }
}

// MARK: - Voice Button

private struct VoiceButton: View {
    let voice: VoiceInfo
    let isSelected: Bool
    let onSelect: () -> Void

    var body: some View {
        Button(action: onSelect) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 4) {
                        Text(voice.name)
                            .font(.caption.weight(.medium))
                            .lineLimit(1)
                        if voice.quality == .premium {
                            Image(systemName: "star.fill")
                                .font(.caption2)
                                .foregroundStyle(Color.accentColor)
                        }
                    }
                    Text(genderLabel)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                if isSelected {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(Color.accentColor)
                }
            }
            .frame(maxWidth: .infinity)
            .padding(8)
        }
        .buttonStyle(.bordered)
        .tint(isSelected ? Color.accentColor : .secondary)
        .accessibilityIdentifier("voiceover.voice.\(voice.identifier).button")
    }

    private var genderLabel: String {
        switch voice.gender {
        case .male: return String(localized: "voiceover.voice.gender.male", defaultValue: "Male")
        case .female: return String(localized: "voiceover.voice.gender.female", defaultValue: "Female")
        case .unspecified: return String(localized: "voiceover.voice.gender.neutral", defaultValue: "Neutral")
        @unknown default: return ""
        }
    }
}

#Preview {
    VoiceoverSettingsSheet(
        captions: [
            Caption(
                text: "Hello world",
                startTime: .zero,
                endTime: CMTime(seconds: 1, preferredTimescale: 600)
            ),
            Caption(
                text: "This is a test",
                startTime: CMTime(seconds: 1, preferredTimescale: 600),
                endTime: CMTime(seconds: 2, preferredTimescale: 600)
            )
        ],
        projectName: "TestProject",
        onGenerate: { _ in }
    )
}
