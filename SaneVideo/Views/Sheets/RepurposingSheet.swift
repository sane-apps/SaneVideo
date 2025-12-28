//
//  RepurposingSheet.swift
//  SaneVideo
//
//  UI for long-to-short video repurposing
//  Allows users to configure settings and select candidates for export
//

import AVFoundation
import SwiftUI

struct RepurposingSheet: View {
    @Environment(\.dismiss) var dismiss
    @Environment(AppState.self) var appState

    // Source clip to repurpose
    let sourceClip: VideoClip?

    // MARK: - State

    @State private var settings = RepurposingSettings.default
    @State private var candidates: [ShortCandidate] = []
    @State private var selectedCandidateIds: Set<UUID> = []
    @State private var isAnalyzing = false
    @State private var analysisPhase: RepurposingPhase = .loading
    @State private var analysisProgress: Double = 0.0
    @State private var error: Error?
    @State private var showingError = false

    // MARK: - Computed Properties

    private var selectedCandidates: [ShortCandidate] {
        candidates.filter { selectedCandidateIds.contains($0.id) }
    }

    private var canAnalyze: Bool {
        sourceClip != nil && !isAnalyzing
    }

    private var canExport: Bool {
        !selectedCandidateIds.isEmpty && !isAnalyzing
    }

    // MARK: - Body

    var body: some View {
        VStack(spacing: 0) {
            // Header
            headerView

            Divider()

            // Main Content
            HStack(spacing: 0) {
                // Left: Settings Panel
                settingsPanel
                    .frame(width: 260)

                Divider()

                // Right: Candidates Grid
                candidatesPanel
            }

            Divider()

            // Footer with actions
            footerView
        }
        .frame(width: 800, height: 600)
        .accessibilityIdentifier("repurposing.sheet")
        .alert("Analysis Error", isPresented: $showingError, actions: {
            Button("OK", role: .cancel) {
                error = nil
            }
        }, message: {
            if let error {
                Text(error.localizedDescription)
            }
        })
    }

    // MARK: - Header

    private var headerView: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Label("Create Shorts", systemImage: "scissors")
                    .font(.title2.bold())

                if let clip = sourceClip {
                    Text("From: \(clip.url.lastPathComponent)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Spacer()

            if isAnalyzing {
                VStack(alignment: .trailing, spacing: 4) {
                    Text(analysisPhase.rawValue)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    ProgressView(value: analysisProgress)
                        .frame(width: 120)
                }
            }
        }
        .padding()
    }

    // MARK: - Settings Panel

    private var settingsPanel: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                // Platform Preset
                VStack(alignment: .leading, spacing: 8) {
                    Label("Platform", systemImage: "square.grid.2x2")
                        .font(.headline)

                    ForEach(ShortPlatform.allCases, id: \.id) { platform in
                        Button {
                            withAnimation {
                                settings.applyPlatformPreset(platform)
                            }
                        } label: {
                            HStack {
                                Image(systemName: platform.icon)
                                    .frame(width: 20)
                                Text(platform.rawValue)
                                Spacer()
                                if settings.platform == platform {
                                    Image(systemName: "checkmark")
                                        .foregroundStyle(Color.accentColor)
                                }
                            }
                            .padding(.vertical, 6)
                            .padding(.horizontal, 10)
                            .background(settings.platform == platform ? Color.accentColor.opacity(0.1) : Color.clear)
                            .cornerRadius(6)
                        }
                        .buttonStyle(.plain)
                        .accessibilityIdentifier("repurposing.platform.\(platform.rawValue)")
                    }
                }

                Divider()

                // Duration
                VStack(alignment: .leading, spacing: 8) {
                    Label("Duration", systemImage: "clock")
                        .font(.headline)

                    Picker("", selection: $settings.targetDuration) {
                        ForEach(ShortDuration.allCases) { duration in
                            Text(duration.label).tag(duration)
                        }
                    }
                    .pickerStyle(.segmented)
                    .accessibilityIdentifier("repurposing.duration")
                }

                // Aspect Ratio
                VStack(alignment: .leading, spacing: 8) {
                    Label("Aspect Ratio", systemImage: "aspectratio")
                        .font(.headline)

                    Picker("", selection: $settings.aspectRatio) {
                        ForEach(ShortAspectRatio.allCases) { ratio in
                            Label(ratio.label, systemImage: ratio.icon).tag(ratio)
                        }
                    }
                    .pickerStyle(.segmented)
                    .accessibilityIdentifier("repurposing.aspect")
                }

                // Max Shorts
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Label("Max Shorts", systemImage: "number")
                            .font(.headline)
                        Spacer()
                        Text("\(settings.maxShorts)")
                            .foregroundStyle(.secondary)
                    }

                    Slider(value: Binding(
                        get: { Double(settings.maxShorts) },
                        set: { settings.maxShorts = Int($0) }
                    ), in: 1...10, step: 1)
                    .accessibilityIdentifier("repurposing.max_shorts")
                }

                Divider()

                // Analysis Options
                VStack(alignment: .leading, spacing: 8) {
                    Label("Analysis", systemImage: "waveform.badge.magnifyingglass")
                        .font(.headline)

                    Toggle("Detect faces", isOn: $settings.detectFaces)
                        .accessibilityIdentifier("repurposing.detect_faces")
                    Toggle("Detect highlights", isOn: $settings.detectHighlights)
                        .accessibilityIdentifier("repurposing.detect_highlights")
                    Toggle("Use captions", isOn: $settings.useCaptions)
                        .accessibilityIdentifier("repurposing.use_captions")
                    Toggle("Avoid silence", isOn: $settings.avoidSilence)
                        .accessibilityIdentifier("repurposing.avoid_silence")
                }

                Divider()

                // Export Options
                VStack(alignment: .leading, spacing: 8) {
                    Label("Export Options", systemImage: "square.and.arrow.up")
                        .font(.headline)

                    Toggle("Add captions", isOn: $settings.addCaptions)
                        .accessibilityIdentifier("repurposing.add_captions")
                    Toggle("Smart crop", isOn: $settings.smartCrop)
                        .accessibilityIdentifier("repurposing.smart_crop")
                    Toggle("Normalize audio", isOn: $settings.normalizeAudio)
                        .accessibilityIdentifier("repurposing.normalize_audio")
                }
            }
            .padding()
        }
    }

    // MARK: - Candidates Panel

    private var candidatesPanel: some View {
        VStack(spacing: 0) {
            // Toolbar
            HStack {
                Text("\(candidates.count) Candidates")
                    .font(.headline)

                Spacer()

                if !candidates.isEmpty {
                    Button("Select All") {
                        selectedCandidateIds = Set(candidates.map { $0.id })
                    }
                    .buttonStyle(.borderless)

                    Button("Clear") {
                        selectedCandidateIds.removeAll()
                    }
                    .buttonStyle(.borderless)
                }
            }
            .padding(.horizontal)
            .padding(.vertical, 8)

            Divider()

            if candidates.isEmpty {
                // Empty state
                VStack(spacing: 16) {
                    Image(systemName: "film.stack")
                        .font(.system(size: 48))
                        .foregroundStyle(.secondary)

                    Text(isAnalyzing ? "Analyzing video..." : "No candidates yet")
                        .font(.title3)
                        .foregroundStyle(.secondary)

                    if !isAnalyzing {
                        Text("Click 'Analyze' to find short clips")
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                // Candidates grid
                ScrollView {
                    LazyVGrid(columns: [
                        GridItem(.adaptive(minimum: 200, maximum: 250), spacing: 12)
                    ], spacing: 12) {
                        ForEach(candidates) { candidate in
                            ShortCandidateCard(
                                candidate: candidate,
                                isSelected: selectedCandidateIds.contains(candidate.id),
                                sourceClip: sourceClip
                            ) {
                                toggleSelection(candidate)
                            }
                        }
                    }
                    .padding()
                }
            }
        }
    }

    // MARK: - Footer

    private var footerView: some View {
        HStack {
            Button("Cancel") {
                dismiss()
            }
            .keyboardShortcut(.cancelAction)
            .accessibilityIdentifier("repurposing.cancel")

            Spacer()

            HStack(spacing: 12) {
                Button {
                    Task { await analyzeVideo() }
                } label: {
                    Label("Analyze", systemImage: "waveform.badge.magnifyingglass")
                }
                .disabled(!canAnalyze)
                .accessibilityIdentifier("repurposing.analyze")

                Button {
                    exportSelectedShorts()
                } label: {
                    Label(
                        "Export \(selectedCandidates.count) Short\(selectedCandidates.count == 1 ? "" : "s")",
                        systemImage: "square.and.arrow.up"
                    )
                }
                .buttonStyle(.borderedProminent)
                .disabled(!canExport)
                .accessibilityIdentifier("repurposing.export")
            }
        }
        .padding()
    }

    // MARK: - Actions

    private func toggleSelection(_ candidate: ShortCandidate) {
        if selectedCandidateIds.contains(candidate.id) {
            selectedCandidateIds.remove(candidate.id)
        } else {
            selectedCandidateIds.insert(candidate.id)
        }
    }

    private func analyzeVideo() async {
        guard let clip = sourceClip else { return }

        isAnalyzing = true
        candidates = []
        selectedCandidateIds.removeAll()

        do {
            let orchestrator = RepurposingOrchestrator()
            let results = try await orchestrator.analyzeForShorts(
                videoURL: clip.url,
                captions: clip.captions,
                settings: settings
            ) { phase, progress in
                Task { @MainActor in
                    self.analysisPhase = phase
                    self.analysisProgress = progress
                }
            }

            await MainActor.run {
                self.candidates = results
                // Auto-select top candidates up to max
                self.selectedCandidateIds = Set(results.prefix(settings.maxShorts).map { $0.id })
                self.isAnalyzing = false
            }
        } catch {
            await MainActor.run {
                self.error = error
                self.showingError = true
                self.isAnalyzing = false
            }
        }
    }

    private func exportSelectedShorts() {
        guard !selectedCandidates.isEmpty else { return }

        // TODO: Integrate with BatchExportService
        // For now, show success toast
        ServiceContainer.shared.toastManager.show(
            "Exporting \(selectedCandidates.count) shorts...",
            type: .info
        )

        dismiss()
    }
}

// MARK: - Candidate Card

struct ShortCandidateCard: View {
    let candidate: ShortCandidate
    let isSelected: Bool
    let sourceClip: VideoClip?
    let onTap: () -> Void

    @State private var thumbnail: NSImage?

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Thumbnail
            ZStack {
                if let thumbnail {
                    Image(nsImage: thumbnail)
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                        .frame(height: 120)
                        .clipped()
                } else {
                    Rectangle()
                        .fill(Color.secondary.opacity(0.2))
                        .frame(height: 120)
                        .overlay {
                            Image(systemName: "film")
                                .font(.title)
                                .foregroundStyle(.secondary)
                        }
                }

                // Duration badge
                VStack {
                    Spacer()
                    HStack {
                        Spacer()
                        Text(candidate.durationLabel)
                            .font(.caption2.bold())
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(.ultraThinMaterial)
                            .cornerRadius(4)
                            .padding(6)
                    }
                }

                // Selection overlay
                if isSelected {
                    Rectangle()
                        .fill(Color.accentColor.opacity(0.3))
                    Image(systemName: "checkmark.circle.fill")
                        .font(.title)
                        .foregroundStyle(.white)
                }
            }
            .cornerRadius(8)

            // Info
            HStack {
                // Score badge
                Text(candidate.scoreLabel)
                    .font(.caption2.bold())
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(scoreColor.opacity(0.2))
                    .foregroundStyle(scoreColor)
                    .cornerRadius(4)

                // Time
                Text(formatTime(candidate.startTime))
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Spacer()
            }

            // Highlights
            if !candidate.highlights.isEmpty {
                HStack(spacing: 4) {
                    ForEach(candidate.highlights, id: \.self) { highlight in
                        Image(systemName: highlight.icon)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
        .padding(8)
        .background(isSelected ? Color.accentColor.opacity(0.1) : Color.secondary.opacity(0.05))
        .cornerRadius(12)
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(isSelected ? Color.accentColor : Color.clear, lineWidth: 2)
        )
        .contentShape(Rectangle())
        .onTapGesture(perform: onTap)
        .accessibilityIdentifier("repurposing.candidate.\(candidate.id)")
        .task {
            await loadThumbnail()
        }
    }

    private var scoreColor: Color {
        switch candidate.score {
        case 0.8...: return .green
        case 0.6..<0.8: return .blue
        case 0.4..<0.6: return .orange
        default: return .red
        }
    }

    private func formatTime(_ seconds: Double) -> String {
        let mins = Int(seconds) / 60
        let secs = Int(seconds) % 60
        return String(format: "%d:%02d", mins, secs)
    }

    private func loadThumbnail() async {
        guard let clip = sourceClip else { return }

        let generator = AVAssetImageGenerator(asset: AVURLAsset(url: clip.url))
        generator.appliesPreferredTrackTransform = true
        generator.maximumSize = CGSize(width: 400, height: 400)

        do {
            let (cgImage, _) = try await generator.image(at: candidate.timeRange.start)
            await MainActor.run {
                self.thumbnail = NSImage(cgImage: cgImage, size: .zero)
            }
        } catch {
            // Keep placeholder
        }
    }
}

#Preview {
    RepurposingSheet(sourceClip: nil)
        .environment(AppState())
}
