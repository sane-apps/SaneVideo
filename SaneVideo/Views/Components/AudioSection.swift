//
//  AudioSection.swift
//  SaneVideo
//
//  2025-12-31: Simplified - Volume moved to toolbar. Kept: Smart Audio Tools
//

import AppKit
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
    @State private var showSyncRepairSheet = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Smart Audio Tools
            SubsectionHeader(title: String(localized: "audio.smart_tools.header", defaultValue: "Smart Tools"))

            SmartToolButton(
                title: "Repair Sync",
                subtitle: "Shift, stretch, trim, or pad to fix A/V drift",
                icon: "waveform.path.ecg.rectangle",
                color: .orange,
                isLoading: false,
                id: "audio.action.repair_sync"
            ) {
                showSyncRepairSheet = true
            }
            .disabled(clip.isMissing)
            .help(clip.isMissing ? "Clip file is missing" : "Open sync repair tools")

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

            HStack(spacing: 4) {
                Image(systemName: "info.circle")
                    .font(.caption2)
                Text("Volume control in toolbar below video")
                    .font(.caption2)
            }
            .foregroundColor(Color.stone)
            .padding(.top, 4)
        }
        .sheet(isPresented: $showSyncRepairSheet) {
            SyncRepairSheet(clip: clip)
                .environment(appState)
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

private struct SyncRepairSheet: View {
    @Environment(AppState.self) private var appState
    @Environment(\.dismiss) private var dismiss

    let clip: VideoClip

    @State private var inspection: SyncInspection?
    @State private var selectedMode: SyncRepairMode = .shiftWholeTrack
    @State private var markerTime: Double = 0
    @State private var offsetSeconds: Double = 0
    @State private var tailTempo: Double = 1.0
    @State private var replaceClipInProject = true
    @State private var isProcessing = false
    @State private var errorMessage: String?
    @State private var outputURL: URL?

    private var needsMarker: Bool {
        selectedMode == .shiftFromMarker || selectedMode == .stretchTailFromMarker
    }

    private var needsOffset: Bool {
        selectedMode == .shiftWholeTrack || selectedMode == .shiftFromMarker
    }

    private var needsTempo: Bool {
        selectedMode == .stretchTailFromMarker
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 6) {
                Text("Sync Repair")
                    .font(.title3.weight(.semibold))
                Text(clip.url.lastPathComponent)
                    .font(.caption)
                    .foregroundColor(Color.stone)
                    .textSelection(.enabled)
            }

            Group {
                if let inspection {
                    summaryView(inspection: inspection)
                } else {
                    ProgressView("Inspecting tracks…")
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }

            Picker("Repair Mode", selection: $selectedMode) {
                ForEach(SyncRepairMode.allCases) { mode in
                    Text(mode.title).tag(mode)
                }
            }
            .pickerStyle(.menu)

            Text(selectedMode.subtitle)
                .font(.caption)
                .foregroundColor(Color.stone)

            if needsMarker {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Marker Time (seconds)")
                        .font(.caption.weight(.semibold))
                    TextField("Marker", value: $markerTime, format: .number.precision(.fractionLength(3)))
                        .textFieldStyle(.roundedBorder)

                    if let suggestion = inspection?.suggestedMarker {
                        Button("Use Suggested Marker (\(formatSeconds(suggestion)))") {
                            markerTime = suggestion
                        }
                        .buttonStyle(.link)
                    }
                }
            }

            if needsOffset {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Audio Offset (seconds)")
                        .font(.caption.weight(.semibold))
                    TextField("Offset", value: $offsetSeconds, format: .number.precision(.fractionLength(3)))
                        .textFieldStyle(.roundedBorder)
                    Text("Negative moves audio earlier. Positive delays audio.")
                        .font(.caption2)
                        .foregroundColor(Color.stone)
                }
            }

            if needsTempo {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Tail Speed")
                        .font(.caption.weight(.semibold))
                    TextField("Speed", value: $tailTempo, format: .number.precision(.fractionLength(3)))
                        .textFieldStyle(.roundedBorder)

                    if let suggestion = inspection?.suggestedTailTempo {
                        Button("Use Suggested Tail Speed (\(String(format: "%.3f", suggestion))x)") {
                            tailTempo = suggestion
                        }
                        .buttonStyle(.link)
                    }

                    Text("Values below 1.0 slow the audio tail down. Values above 1.0 speed it up.")
                        .font(.caption2)
                        .foregroundColor(Color.stone)
                }
            }

            Toggle("Replace selected clip in this project when the repaired copy finishes", isOn: $replaceClipInProject)

            if let errorMessage {
                Text(errorMessage)
                    .font(.caption)
                    .foregroundColor(.red)
            }

            if let outputURL {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Last Output")
                        .font(.caption.weight(.semibold))
                    Text(outputURL.path)
                        .font(.caption2)
                        .foregroundColor(Color.stone)
                        .textSelection(.enabled)

                    Button("Reveal in Finder") {
                        NSWorkspace.shared.activateFileViewerSelecting([outputURL])
                    }
                    .buttonStyle(.link)
                }
            }

            Spacer()

            HStack {
                Button("Close") {
                    dismiss()
                }
                .keyboardShortcut(.cancelAction)

                Spacer()

                Button {
                    Task { await createRepair() }
                } label: {
                    if isProcessing {
                        ProgressView()
                            .controlSize(.small)
                    } else {
                        Text("Create Repaired Copy")
                    }
                }
                .buttonStyle(.borderedProminent)
                .disabled(isProcessing || inspection == nil)
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(20)
        .frame(width: 560, height: 620)
        .task {
            await loadInspection()
        }
        .onChange(of: selectedMode) { _, newValue in
            guard let inspection else { return }
            applySuggestions(for: newValue, inspection: inspection, force: false)
        }
    }

    @ViewBuilder
    private func summaryView(inspection: SyncInspection) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            LabeledContent("Video Duration") {
                Text(formatSeconds(inspection.videoDuration))
                    .monospacedDigit()
            }

            LabeledContent("Audio Tracks") {
                Text("\(inspection.audioDurations.count)")
            }

            if let primaryAudioDuration = inspection.primaryAudioDuration {
                LabeledContent("Primary Audio Duration") {
                    Text(formatSeconds(primaryAudioDuration))
                        .monospacedDigit()
                }
            }

            if inspection.detectedTailGap > 0.25 {
                Text("Detected the main audio ending \(formatSeconds(inspection.detectedTailGap)) before the video.")
                    .font(.caption)
                    .foregroundColor(.orange)
            } else {
                Text("No major tail gap was detected automatically. Use the controls below for manual drift fixes.")
                    .font(.caption)
                    .foregroundColor(Color.stone)
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.stone.opacity(0.08))
        .cornerRadius(10)
    }

    private func loadInspection() async {
        do {
            let inspection = try await ServiceContainer.shared.ffmpegService.inspectSync(inputURL: clip.url)
            await MainActor.run {
                self.inspection = inspection
                applySuggestions(for: selectedMode, inspection: inspection, force: true)
            }
        } catch {
            await MainActor.run {
                errorMessage = error.localizedDescription
            }
        }
    }

    private func applySuggestions(for mode: SyncRepairMode, inspection: SyncInspection, force: Bool) {
        if force {
            selectedMode = inspection.detectedTailGap > 0.25 ? .trimVideoToPrimaryAudio : .shiftWholeTrack
        }

        if let suggestedMarker = inspection.suggestedMarker,
           markerTime == 0 || force || mode == .stretchTailFromMarker {
            markerTime = suggestedMarker
        }

        if let suggestedTempo = inspection.suggestedTailTempo,
           tailTempo == 1.0 || force || mode == .stretchTailFromMarker {
            tailTempo = suggestedTempo
        }
    }

    private func createRepair() async {
        guard !isProcessing else { return }
        guard let inspection else { return }

        isProcessing = true
        errorMessage = nil

        do {
            let ffmpeg = ServiceContainer.shared.ffmpegService
            let output = await ffmpeg.suggestedSyncRepairOutputURL(inputURL: clip.url, mode: selectedMode)
            try await ffmpeg.repairSync(
                inputURL: clip.url,
                outputURL: output,
                mode: selectedMode,
                markerTime: needsMarker ? markerTime : nil,
                offsetSeconds: needsOffset ? offsetSeconds : 0,
                tailTempo: needsTempo ? tailTempo : 1.0
            )

            await MainActor.run {
                outputURL = output
                if replaceClipInProject {
                    appState.projectState.relinkClip(clip, to: output)
                }

                let message: String
                if replaceClipInProject {
                    message = "Created repaired copy and replaced the selected clip."
                } else {
                    message = "Created repaired copy next to the original clip."
                }
                ServiceContainer.shared.toastManager.show(message, type: .success)
            }
        } catch {
            await MainActor.run {
                let advice = inspection.detectedTailGap > 0.25
                    ? " Try 'Trim Video To Audio End' for hard tail corruption."
                    : ""
                errorMessage = error.localizedDescription + advice
                ServiceContainer.shared.toastManager.show("Sync repair failed", type: .error)
            }
        }

        isProcessing = false
    }

    private func formatSeconds(_ seconds: Double) -> String {
        guard seconds.isFinite else { return "0.000s" }

        let totalSeconds = Int(seconds.rounded(.down))
        let hours = totalSeconds / 3600
        let minutes = (totalSeconds % 3600) / 60
        let remainingSeconds = totalSeconds % 60
        let milliseconds = Int(((seconds - Double(totalSeconds)) * 1000).rounded())

        if hours > 0 {
            return String(format: "%02d:%02d:%02d.%03d", hours, minutes, remainingSeconds, milliseconds)
        }

        return String(format: "%02d:%02d.%03d", minutes, remainingSeconds, milliseconds)
    }
}
