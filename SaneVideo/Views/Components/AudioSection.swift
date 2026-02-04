//
//  AudioSection.swift
//  SaneVideo
//
//  2025-12-31: Simplified - Volume moved to toolbar. Kept: Smart Audio Tools
//

import CoreMedia
import SwiftUI

// MARK: - AUDIO Section (Smart Tools Only)

struct AudioSection: View {
    @Environment(AppState.self) var appState
    let clip: VideoClip
    @Binding var isOperationInProgress: Bool

    @State private var analysisResult: String?
    @State private var isFindingHighlights = false
    @State private var isAnalyzingAudio = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
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
            .disabled(clip.isMissing)
            .help(clip.isMissing ? "Clip file is missing" : "Find highlights in audio")

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
            .disabled(clip.isMissing)
            .help(clip.isMissing ? "Clip file is missing" : "Analyze audio content")

            if let result = analysisResult {
                Text(result)
                    .font(.caption2)
                    .foregroundColor(Color.stone)
                    .padding(6)
                    .background(Color.stone.opacity(0.1))
                    .cornerRadius(4)
                    .transition(.smoothScale)
                    .smoothAppear()
            }

            // Hint: Volume in toolbar
            HStack(spacing: 4) {
                Image(systemName: "info.circle")
                    .font(.caption2)
                Text("Volume control in toolbar below video")
                    .font(.caption2)
            }
            .foregroundColor(Color.stone)
            .padding(.top, 4)
        }
    }

    // MARK: - Actions

    private func findHighlights() async {
        guard !clip.isMissing else {
            await MainActor.run {
                analysisResult = "Clip file is missing"
                ServiceContainer.shared.toastManager.show("Clip file is missing", type: .error)
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
                    analysisResult = "No highlights detected"
                } else {
                    let times = highlights.prefix(3).map { formatTime($0.timeRange.start) }
                    analysisResult = "🎉 Found \(highlights.count) highlights at: \(times.joined(separator: ", "))"
                }
            }
        } catch {
            await MainActor.run {
                analysisResult = "❌ Analysis failed: \(error.localizedDescription)"
                ServiceContainer.shared.toastManager.show("Audio analysis failed", type: .error)
            }
        }
    }

    private func analyzeAudio() async {
        guard !clip.isMissing else {
            await MainActor.run {
                analysisResult = "Clip file is missing"
                ServiceContainer.shared.toastManager.show("Clip file is missing", type: .error)
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
                analysisResult = "🎵 \(summary)"
            }
        } catch {
            await MainActor.run {
                analysisResult = "❌ Analysis failed: \(error.localizedDescription)"
                ServiceContainer.shared.toastManager.show("Audio analysis failed", type: .error)
            }
        }
    }

    private func formatTime(_ time: CMTime) -> String {
        let seconds = Int(time.seconds)
        return String(format: "%d:%02d", seconds / 60, seconds % 60)
    }
}
