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
    @State private var isExporting = false
    @State private var exportProgress: Double = 0.0

    // MARK: - Computed Properties

    private var selectedCandidates: [ShortCandidate] {
        candidates.filter { selectedCandidateIds.contains($0.id) }
    }

    private var canAnalyze: Bool {
        sourceClip != nil && !isAnalyzing
    }

    private var canExport: Bool {
        !selectedCandidateIds.isEmpty && !isAnalyzing && !isExporting
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
            } else if isExporting {
                VStack(alignment: .trailing, spacing: 4) {
                    Text("Exporting...")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    ProgressView(value: exportProgress)
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
                .keyboardShortcut(.defaultAction)
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
        guard let clip = sourceClip, !selectedCandidates.isEmpty else { return }

        isExporting = true
        exportProgress = 0.0

        Task {
            let batchService = BatchExportService()

            do {
                let outputURLs = try await batchService.exportShorts(
                    selectedCandidates,
                    from: clip.url,
                    settings: settings
                ) { progress in
                    Task { @MainActor in
                        self.exportProgress = progress
                    }
                }

                await MainActor.run {
                    isExporting = false

                    if outputURLs.isEmpty {
                        ServiceContainer.shared.toastManager.show(
                            "No shorts were exported",
                            type: .info
                        )
                    } else {
                        ServiceContainer.shared.toastManager.show(
                            "Exported \(outputURLs.count) short\(outputURLs.count == 1 ? "" : "s") to ~/Movies/SaneVideo/Shorts",
                            type: .success
                        )

                        // Open the output folder
                        if let firstURL = outputURLs.first {
                            NSWorkspace.shared.selectFile(
                                firstURL.path,
                                inFileViewerRootedAtPath: firstURL.deletingLastPathComponent().path
                            )
                        }
                    }

                    dismiss()
                }
            } catch {
                await MainActor.run {
                    self.error = error
                    self.showingError = true
                    self.isExporting = false
                }
            }
        }
    }
}
#Preview {
    RepurposingSheet(sourceClip: nil)
        .environment(AppState())
}
