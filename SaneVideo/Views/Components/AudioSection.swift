//
//  AudioSection.swift
//  SaneVideo
//
//  Extracted from StylesInspectorView.swift
//  Contains audio-related inspector controls (Volume, Highlights, Analysis)
//

import CoreMedia
import SwiftUI

// MARK: - AUDIO Section (Volume + Highlights + Analysis)

struct AudioSection: View {
    @Environment(AppState.self) var appState
    let clip: VideoClip

    @State private var volume: Float
    @State private var isAnalyzing = false
    @State private var analysisResult: String?

    init(clip: VideoClip) {
        self.clip = clip
        _volume = State(initialValue: clip.volume)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Volume Control
            SubsectionHeader(title: String(localized: "audio.volume.header", defaultValue: "Volume"))
            HStack {
                Image(systemName: volume == 0 ? "speaker.slash.fill" : "speaker.wave.2.fill")
                    .foregroundColor(volume == 0 ? .red : .secondary)
                    .font(.caption)
                    .frame(width: 20)

                Slider(value: $volume, in: 0 ... 1, step: 0.05)
                    .accessibilityIdentifier("audio.volume.slider")
                    .onChange(of: volume) { _, newValue in
                        appState.projectState.updateClipVolume(clipId: clip.id, volume: newValue)
                    }

                Text(String(format: "%.0f%%", volume * 100))
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundColor(.secondary)
                    .frame(width: 35)
            }

            Divider().padding(.vertical, 4)

            // Smart Audio Tools
            SubsectionHeader(title: String(localized: "audio.smart_tools.header", defaultValue: "Smart Tools"))

            // Find Highlights
            SmartToolButton(
                title: String(localized: "audio.action.find_highlights.title", defaultValue: "Find Highlights"),
                subtitle: String(localized: "audio.action.find_highlights.subtitle", defaultValue: "Detect applause & laughter"),
                icon: "star.fill",
                color: .yellow,
                isLoading: isAnalyzing,
                id: "audio.action.find_highlights"
            ) {
                Task { await findHighlights() }
            }

            // Analyze Audio
            SmartToolButton(
                title: String(localized: "audio.action.analyze_audio.title", defaultValue: "Analyze Audio"),
                subtitle: String(localized: "audio.action.analyze_audio.subtitle", defaultValue: "Detect speech, music, silence"),
                icon: "waveform.badge.magnifyingglass",
                color: .green,
                isLoading: false,
                id: "audio.action.analyze_audio"
            ) {
                Task { await analyzeAudio() }
            }

            if let result = analysisResult {
                Text(result)
                    .font(.caption2)
                    .foregroundColor(.secondary)
                    .padding(6)
                    .background(Color.secondary.opacity(0.1))
                    .cornerRadius(4)
                    .overlay(
                        RoundedRectangle(cornerRadius: 4)
                            .stroke(Color.secondary.opacity(0.2), lineWidth: 0.5)
                    )
                    .transition(.smoothScale)
                    .smoothAppear()
            }

            Divider().padding(.vertical, 4)

            // AI Audio Tools
            SubsectionHeader(title: String(localized: "audio.ai_tools.header", defaultValue: "AI Audio"))

            VStack(spacing: 8) {
                Toggle(isOn: Binding(
                    get: { clip.isVoiceIsolationEnabled },
                    set: { appState.projectState.updateClipVoiceIsolation(clipId: clip.id, enabled: $0) }
                )) {
                    Label {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(String(localized: "audio.voice_isolation.title", defaultValue: "Voice Isolation"))
                                .font(.system(size: 13, weight: .medium))
                            Text(String(localized: "audio.voice_isolation.subtitle", defaultValue: "Remove background noise with Apple ML"))
                                .font(.system(size: 11))
                                .foregroundColor(.secondary)
                        }
                    } icon: {
                        Image(systemName: "waveform.path.badge.minus")
                            .foregroundColor(.blue)
                    }
                }
                .toggleStyle(SwitchToggleStyle(tint: .blue))

                Toggle(isOn: Binding(
                    get: { clip.isGatingEnabled },
                    set: { appState.projectState.updateClipGating(clipId: clip.id, enabled: $0) }
                )) {
                    Label {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(String(localized: "audio.ai_gating.title", defaultValue: "AI Gating"))
                                .font(.system(size: 13, weight: .medium))
                            Text(String(localized: "audio.ai_gating.subtitle", defaultValue: "Automatically mute non-speech segments"))
                                .font(.system(size: 11))
                                .foregroundColor(.secondary)
                        }
                    } icon: {
                        Image(systemName: "door.left.hand.closed")
                            .foregroundColor(.purple)
                    }
                }
                .toggleStyle(SwitchToggleStyle(tint: .purple))
            }
            .padding(.horizontal, 4)
        }
    }

    // MARK: - Actions

    private func findHighlights() async {
        do {
            let highlights = try await ServiceContainer.shared.soundAnalysisService.findHighlights(in: clip.url)
            if highlights.isEmpty {
                analysisResult = String(localized: "audio.analysis.no_highlights", defaultValue: "No highlights (applause/laughter) detected")
            } else {
                let times = highlights.prefix(3).map { formatTime($0.timeRange.start) }
                analysisResult = String(localized: "audio.analysis.found_highlights", defaultValue: "🎉 Found highlights") + " (\(highlights.count)) at: \(times.joined(separator: ", "))"
            }
        } catch {
            analysisResult = String(localized: "audio.analysis.failed", defaultValue: "❌ Audio analysis failed") + ": \(error.localizedDescription)"
        }
    }

    private func analyzeAudio() async {
        do {
            let classifications = try await ServiceContainer.shared.soundAnalysisService.analyzeAudio(in: clip.url)
            let grouped = Dictionary(grouping: classifications, by: { $0.label })
            let summary = grouped.map { "\($0.key.displayName): \($0.value.count)" }.joined(separator: ", ")
            analysisResult = String(localized: "audio.analysis.summary", defaultValue: "🎵 Audio summary") + ": \(summary)"
        } catch {
            analysisResult = String(localized: "audio.analysis.failed", defaultValue: "❌ Audio analysis failed") + ": \(error.localizedDescription)"
        }
    }

    private func formatTime(_ time: CMTime) -> String {
        let seconds = Int(time.seconds)
        return String(format: "%d:%02d", seconds / 60, seconds % 60)
    }
}
