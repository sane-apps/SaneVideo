// UI for long-to-short video repurposing

import AVFoundation
import SwiftUI

struct RepurposingSheet: View {
    @Environment(\.dismiss) var dismiss
    @Environment(AppState.self) var appState

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
            headerView

            Divider()

            HStack(spacing: 0) {
                settingsPanel
                    .frame(width: 260)

                Divider()

                candidatesPanel
            }

            Divider()

            footerView
        }
        .frame(width: 800, height: 600)
        .sanePanel(radius: 18, emphasized: true, accent: Theme.Colors.accentSoft)
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
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Label("Create Shorts", systemImage: "scissors")
                        .font(.title2.bold())
                        .foregroundStyle(.white)

                    if let clip = sourceClip {
                        Text("From: \(clip.url.lastPathComponent)")
                            .saneReadableSupportText()
                    }
                }

                Spacer()

                if isAnalyzing {
                    VStack(alignment: .trailing, spacing: 4) {
                        Text(analysisPhase.rawValue)
                            .saneReadableSupportText()
                        ProgressView(value: analysisProgress)
                            .frame(width: 120)
                    }
                } else if isExporting {
                    VStack(alignment: .trailing, spacing: 4) {
                        Text("Exporting...")
                            .saneReadableSupportText()
                        ProgressView(value: exportProgress)
                            .frame(width: 120)
                    }
                }
            }

            FeatureCallout(
                title: "Local short variants",
                message: "Find the best moments and export them as short clips.",
                icon: "film.stack.fill"
            )
        }
        .padding()
    }

    // MARK: - Settings Panel

    private var settingsPanel: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                VStack(alignment: .leading, spacing: 8) {
                    Label("Platform", systemImage: "square.grid.2x2")
                        .saneReadableSectionTitle()

                    ForEach(ShortPlatform.allCases, id: \.id) { platform in
                        Button {
                            withAnimation {
                                settings.applyPlatformPreset(platform)
                            }
                        } label: {
                            HStack(spacing: 10) {
                                Image(systemName: platform.icon)
                                    .foregroundStyle(.white)
                                    .frame(width: 20)
                                Text(platform.rawValue)
                                    .foregroundStyle(.white)
                                    .font(Theme.Typography.bodyStrong)
                                Spacer()
                                if settings.platform == platform {
                                    Image(systemName: "checkmark.circle.fill")
                                        .foregroundStyle(Theme.Colors.accentSoft)
                                }
                            }
                            .padding(.vertical, 8)
                            .padding(.horizontal, 10)
                            .background(
                                RoundedRectangle(cornerRadius: 10, style: .continuous)
                                    .fill(settings.platform == platform ? Theme.Colors.rowSelected : Theme.Colors.rowIdle)
                            )
                            .overlay(
                                RoundedRectangle(cornerRadius: 10, style: .continuous)
                                    .strokeBorder(
                                        settings.platform == platform
                                            ? Theme.Colors.accentSoft.opacity(0.55)
                                            : Color.white.opacity(0.12),
                                        lineWidth: 1
                                    )
                            )
                        }
                        .buttonStyle(.plain)
                        .accessibilityIdentifier("repurposing.platform.\(platform.rawValue)")
                        .help(platform.description)
                    }
                }

                Divider().overlay(Theme.Colors.divider)

                VStack(alignment: .leading, spacing: 8) {
                    Label("Duration", systemImage: "clock")
                        .saneReadableSectionTitle()

                    Picker("", selection: $settings.targetDuration) {
                        ForEach(ShortDuration.allCases) { duration in
                            Text(duration.label).tag(duration)
                        }
                    }
                    .pickerStyle(.segmented)
                    .accessibilityIdentifier("repurposing.duration")

                    Text(settings.targetDuration.description)
                        .saneReadableSupportText()
                }

                VStack(alignment: .leading, spacing: 8) {
                    Label("Aspect Ratio", systemImage: "aspectratio")
                        .saneReadableSectionTitle()

                    Picker("", selection: $settings.aspectRatio) {
                        ForEach(ShortAspectRatio.allCases) { ratio in
                            Label(ratio.label, systemImage: ratio.icon).tag(ratio)
                        }
                    }
                    .pickerStyle(.segmented)
                    .accessibilityIdentifier("repurposing.aspect")

                    Text(settings.aspectRatio.description)
                        .saneReadableSupportText()
                }

                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Label("Max Shorts", systemImage: "number")
                            .saneReadableSectionTitle()
                        Spacer()
                        Text("\(settings.maxShorts)")
                            .saneReadableMeta(monospaced: true)
                    }

                    Slider(value: Binding(
                        get: { Double(settings.maxShorts) },
                        set: { settings.maxShorts = Int($0) }
                    ), in: 1...10, step: 1)
                    .accessibilityIdentifier("repurposing.max_shorts")
                    .help("Raise for more options; lower for a tighter shortlist.")
                }

            }
            .padding(14)
            .foregroundStyle(.white)
        }
        .background(Theme.Colors.editorBase.opacity(0.55))
    }

    // MARK: - Candidates Panel

    private var candidatesPanel: some View {
        VStack(spacing: 0) {
            HStack {
                Text("\(candidates.count) Candidates")
                    .saneReadableSectionTitle()

                Spacer()

                if !candidates.isEmpty {
                    Button("Select All") {
                        selectedCandidateIds = Set(candidates.map { $0.id })
                    }
                    .buttonStyle(SaneSheetButtonStyle(kind: .quiet, isEnabled: true))

                    Button("Clear") {
                        selectedCandidateIds.removeAll()
                    }
                    .buttonStyle(SaneSheetButtonStyle(kind: .quiet, isEnabled: true))
                }
            }
            .padding(.horizontal)
            .padding(.vertical, 8)

            Divider()

            if candidates.isEmpty {
                VStack(spacing: 14) {
                    Image(systemName: "film.stack")
                        .font(.system(size: 44, weight: .medium))
                        .foregroundStyle(.white)

                    Text(isAnalyzing ? "Analyzing video..." : "No candidates yet")
                        .font(.title3.weight(.semibold))
                        .foregroundStyle(.white)

                    if !isAnalyzing {
                        Text("Choose a platform on the left, then click Analyze.")
                            .font(Theme.Typography.support)
                            .foregroundStyle(.white)
                            .multilineTextAlignment(.center)
                            .frame(maxWidth: 280)
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .padding(24)
            } else {
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
            .buttonStyle(SaneSheetButtonStyle(kind: .secondary, isEnabled: true))
            .keyboardShortcut(.cancelAction)
            .accessibilityIdentifier("repurposing.cancel")

            Spacer()

            HStack(spacing: 12) {
                Button {
                    Task { await analyzeVideo() }
                } label: {
                    Label("Analyze", systemImage: "waveform.badge.magnifyingglass")
                }
                .buttonStyle(SaneSheetButtonStyle(kind: .secondary, isEnabled: canAnalyze))
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
                .buttonStyle(SaneSheetButtonStyle(kind: .primary, isEnabled: canExport))
                .keyboardShortcut(.defaultAction)
                .disabled(!canExport)
                .accessibilityIdentifier("repurposing.export")
            }
        }
        .padding()
        .background(Theme.Colors.editorPanelElevated.opacity(0.85))
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
                    name: appState.currentProject?.name ?? "Short",
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
