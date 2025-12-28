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
    @Binding var isOperationInProgress: Bool

    // CRITICAL FIX: Sync state with clip properties
    @State private var volume: Float
    @State private var analysisResult: String?
    
    // P0 FIX: Separate loading states for each operation
    @State private var isFindingHighlights = false
    @State private var isAnalyzingAudio = false
    
    // CRITICAL FIX: Debounce slider updates
    @State private var pendingVolumeUpdate: Task<Void, Never>?

    init(clip: VideoClip, isOperationInProgress: Binding<Bool>) {
        self.clip = clip
        self._isOperationInProgress = isOperationInProgress
        _volume = State(initialValue: clip.volume)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // P1 FIX: Enhanced Volume Control with mute button
            SubsectionHeader(title: String(localized: "audio.volume.header", defaultValue: "Volume"))
            HStack(spacing: 8) {
                // P1 FIX: Mute button
                Button {
                    let newVolume: Float = volume > 0 ? 0 : 1.0
                    volume = newVolume
                    appState.projectState.updateClipVolume(clipId: clip.id, volume: newVolume)
                } label: {
                    Image(systemName: volume == 0 ? "speaker.slash.fill" : "speaker.wave.2.fill")
                        .foregroundColor(volume == 0 ? .red : .secondary)
                        .font(.system(size: 14))
                        .frame(width: 28, height: 28)
                        .background(volume == 0 ? Color.red.opacity(0.1) : Color.secondary.opacity(0.1))
                        .cornerRadius(6)
                }
                .buttonStyle(.plain)
                .help(volume == 0 ? "Unmute" : "Mute")
                .accessibilityIdentifier("audio.mute_button")

                // P1 FIX: Wider slider
                Slider(value: $volume, in: 0 ... 1, step: 0.05)
                    .accessibilityIdentifier("audio.volume.slider")
                    .onChange(of: volume) { _, newValue in
                        // CRITICAL FIX: Debounce slider updates to prevent excessive saves
                        pendingVolumeUpdate?.cancel()
                        pendingVolumeUpdate = Task {
                            // Wait 300ms after user stops dragging
                            try? await Task.sleep(nanoseconds: 300_000_000)
                            guard !Task.isCancelled else { return }
                            await MainActor.run {
                                appState.projectState.updateClipVolume(clipId: clip.id, volume: newValue)
                            }
                        }
                    }

                // P1 FIX: Larger percentage display
                Text(String(format: "%.0f%%", volume * 100))
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundColor(.secondary)
                    .frame(width: 40)
            }
            // CRITICAL FIX: Sync volume when clip changes externally
            .onChange(of: clip.volume) { _, newVolume in
                if abs(volume - newVolume) > 0.01 { // Only update if significantly different
                    volume = newVolume
                }
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
                isLoading: isFindingHighlights,
                id: "audio.action.find_highlights"
            ) {
                Task { await findHighlights() }
            }
            .disabled(clip.isMissing) // CRITICAL FIX: Disable if clip is missing
            .help(clip.isMissing ? "Clip file is missing. Use 'Locate File' in Clip Info to relink the file." : "Find highlights (applause, laughter) in audio")
            .accessibilityHint(clip.isMissing ? "Clip file is missing. Use 'Locate File' in Clip Info to relink the file." : "Find highlights (applause, laughter) in audio")

            // Analyze Audio
            SmartToolButton(
                title: String(localized: "audio.action.analyze_audio.title", defaultValue: "Analyze Audio"),
                subtitle: String(localized: "audio.action.analyze_audio.subtitle", defaultValue: "Detect speech, music, silence"),
                icon: "waveform.badge.magnifyingglass",
                color: .green,
                isLoading: isAnalyzingAudio,
                id: "audio.action.analyze_audio"
            ) {
                Task { await analyzeAudio() }
            }
            .disabled(clip.isMissing) // CRITICAL FIX: Disable if clip is missing
            .help(clip.isMissing ? "Clip file is missing. Use 'Locate File' in Clip Info to relink the file." : "Analyze audio to detect speech, music, and silence")
            .accessibilityHint(clip.isMissing ? "Clip file is missing. Use 'Locate File' in Clip Info to relink the file." : "Analyze audio to detect speech, music, and silence")

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

            // UX FIX: Removed duplicate AI Audio toggles (Voice Isolation, AI Gating)
            // These features are already accessible in Smart Tools section as:
            // - "Enhance Speech" = Voice Isolation
            // - "Remove Silence" preview = AI Gating
            // Having them in two places was confusing users
        }
    }

    // MARK: - Actions

    private func findHighlights() async {
        // CRITICAL FIX: Validate clip before operation
        guard !clip.isMissing else {
            await MainActor.run {
                analysisResult = "Cannot analyze: Clip file is missing. Use 'Locate File' in Clip Info to relink the file."
                ServiceContainer.shared.toastManager.show(
                    "Clip file is missing. Check Clip Info section to relink the file.",
                    type: .error
                )
            }
            return
        }
        
        isFindingHighlights = true
        defer {
            Task { @MainActor in
                isFindingHighlights = false
            }
        }
        
        do {
            let highlights = try await ServiceContainer.shared.soundAnalysisService.findHighlights(in: clip.url)
            await MainActor.run {
                if highlights.isEmpty {
                    analysisResult = String(localized: "audio.analysis.no_highlights", defaultValue: "No highlights (applause/laughter) detected")
                } else {
                    let times = highlights.prefix(3).map { formatTime($0.timeRange.start) }
                    analysisResult = String(localized: "audio.analysis.found_highlights", defaultValue: "🎉 Found highlights") + " (\(highlights.count)) at: \(times.joined(separator: ", "))"
                }
            }
        } catch {
            await MainActor.run {
                analysisResult = String(localized: "audio.analysis.failed", defaultValue: "❌ Audio analysis failed") + ": \(error.localizedDescription)"
                ServiceContainer.shared.toastManager.show(
                    "Audio analysis failed: \(error.localizedDescription)",
                    type: .error
                )
            }
        }
    }

    private func analyzeAudio() async {
        // CRITICAL FIX: Validate clip before operation
        guard !clip.isMissing else {
            await MainActor.run {
                analysisResult = "Cannot analyze: Clip file is missing. Use 'Locate File' in Clip Info to relink the file."
                ServiceContainer.shared.toastManager.show(
                    "Clip file is missing. Check Clip Info section to relink the file.",
                    type: .error
                )
            }
            return
        }
        
        isAnalyzingAudio = true
        defer {
            Task { @MainActor in
                isAnalyzingAudio = false
            }
        }
        
        do {
            let classifications = try await ServiceContainer.shared.soundAnalysisService.analyzeAudio(in: clip.url)
            let grouped = Dictionary(grouping: classifications, by: { $0.label })
            let summary = grouped.map { "\($0.key.displayName): \($0.value.count)" }.joined(separator: ", ")
            await MainActor.run {
                analysisResult = String(localized: "audio.analysis.summary", defaultValue: "🎵 Audio summary") + ": \(summary)"
            }
        } catch {
            await MainActor.run {
                analysisResult = String(localized: "audio.analysis.failed", defaultValue: "❌ Audio analysis failed") + ": \(error.localizedDescription)"
                ServiceContainer.shared.toastManager.show(
                    "Audio analysis failed: \(error.localizedDescription)",
                    type: .error
                )
            }
        }
    }

    private func formatTime(_ time: CMTime) -> String {
        let seconds = Int(time.seconds)
        return String(format: "%d:%02d", seconds / 60, seconds % 60)
    }
}
