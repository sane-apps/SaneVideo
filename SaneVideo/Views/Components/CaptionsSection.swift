//
//  CaptionsSection.swift
//  SaneVideo
//
//  Caption-related inspector controls (Style, OCR, Mood, Refinement)
//  Sub-components extracted to: CaptionStylePreview, ClipInfoSection, CursorEnhancementsView
//

import AVFoundation
import SwiftUI

// MARK: - Captions Section

struct CaptionsSection: View {
    @Environment(AppState.self) var appState
    let clip: VideoClip
    @Binding var isOperationInProgress: Bool

    @State private var isAnalyzing = false
    @State private var isRefining = false
    @State private var isGeneratingCaptions = false // CRITICAL FIX: Track caption generation state
    @State private var detectedText: [String] = []
    @State private var analysisResult: String?
    @State private var showTranscriptEditor = false
    @State private var showTranscriptTimeline = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Header with Text-Based Editing toggle
            HStack {
                Label("Captions", systemImage: "text.bubble")
                    .font(.headline)
                Spacer()
                if !clip.captions.isEmpty {
                    HStack(spacing: 8) {
                        Button {
                            showTranscriptTimeline.toggle()
                        } label: {
                            Label("Text Editor", systemImage: "text.cursor")
                                .font(.caption)
                        }
                        .buttonStyle(.bordered)
                        .accessibilityIdentifier("captions.text_editor_button")

                        Button {
                            showTranscriptEditor.toggle()
                        } label: {
                            Label("List View", systemImage: "list.bullet")
                                .font(.caption)
                        }
                        .buttonStyle(.bordered)
                        .accessibilityIdentifier("captions.list_editor_button")
                    }
                }
            }

            // Caption count & status
            if clip.captions.isEmpty {
                emptyCaptionsHint
            } else {
                captionControls
            }

            Divider().padding(.vertical, 4)

            // OCR / Scan for Text
            textDetectionSection
        }
        .sheet(isPresented: $showTranscriptEditor) {
            TranscriptionEditorView(selectedClip: .constant(clip))
                .frame(minWidth: 600, minHeight: 400)
        }
        .sheet(isPresented: $showTranscriptTimeline) {
            TranscriptTimelineView(clip: clip)
                .frame(minWidth: 800, minHeight: 500)
        }
    }

    // MARK: - Subviews

    // P1 FIX: Empty state with Generate Captions button
    private var emptyCaptionsHint: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 6) {
                Image(systemName: "info.circle")
                    .foregroundColor(.accentColor)
                Text(String(localized: "captions.empty_hint", defaultValue: "No captions yet"))
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            // P1 FIX: Primary action button
            Button {
                Task { await generateCaptions() }
            } label: {
                HStack {
                    Image(systemName: "text.bubble.fill")
                    Text(String(localized: "captions.generate", defaultValue: "Generate Captions"))
                        .fontWeight(.medium)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 8)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.regular)
            .disabled(isOperationInProgress || clip.isMissing || isGeneratingCaptions)
            .help(clip.isMissing ? "Clip file is missing. Use 'Locate File' in Clip Info to relink the file." : (isGeneratingCaptions ? "Generating captions..." : (isOperationInProgress ? "Another operation is in progress" : "Generate captions from audio transcription")))
            .accessibilityIdentifier("captions.generate_button")
            .accessibilityHint(clip.isMissing ? "Clip file is missing. Use 'Locate File' in Clip Info to relink the file." : (isGeneratingCaptions ? "Generating captions" : (isOperationInProgress ? "Another operation is in progress" : "Generate captions from audio transcription")))
            .accessibilityValue(isGeneratingCaptions ? "Generating" : "")
            .overlay {
                if isGeneratingCaptions {
                    ProgressView()
                        .scaleEffect(0.8)
                }
            }

            // P1 FIX: Alternative hint
            Text(String(localized: "captions.alternative_hint", defaultValue: "Or use Magic Fix for full cleanup"))
                .font(.caption2)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding(12)
        .background(Color.accentColor.opacity(0.05))
        .cornerRadius(8)
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(Color.accentColor.opacity(0.2), lineWidth: 1)
        )
    }

    // P1 FIX: Generate captions action
    private func generateCaptions() async {
        guard !clip.isMissing else {
            await MainActor.run {
                ServiceContainer.shared.toastManager.show(
                    "Cannot generate captions: Clip file is missing. Use 'Locate File' in Clip Info to relink the file.",
                    type: .error
                )
            }
            return
        }

        // P0 FIX: Use separate state for caption generation
        isGeneratingCaptions = true
        defer {
            Task { @MainActor in
                isGeneratingCaptions = false
            }
        }

        do {
            // P0 FIX: Use TranscriptionCoordinator for caption generation
            await MainActor.run {
                analysisResult = "Generating captions... This may take a moment."
            }

            // Use the transcription coordinator to generate captions
            let coordinator = ServiceContainer.shared.transcriptionCoordinator
            let captions = try await coordinator.generateCaptions(
                for: clip.url,
                progressHandler: { current, total, _ in
                    Task { @MainActor in
                        let progress = total > 0 ? Double(current) / Double(total) : 0.0
                        analysisResult = "Generating captions... \(Int(progress * 100))%"
                    }
                }
            )

            await MainActor.run {
                appState.projectState.updateCaptions(for: clip, newCaptions: captions)
                ServiceContainer.shared.toastManager.show(
                    String(localized: "toast.captions_generated", defaultValue: "Captions generated!"),
                    type: .success
                )
            }
        } catch {
            await MainActor.run {
                ServiceContainer.shared.toastManager.show(
                    String(localized: "toast.captions_generation_failed", defaultValue: "Failed to generate captions: \(error.localizedDescription)"),
                    type: .error
                )
                AppLogger.project.error("Caption generation failed: \(error.localizedDescription)")
            }
        }
    }

    private var captionControls: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Status row
            HStack {
                Label(
                    String(localized: "captions.count", defaultValue: "\(clip.captions.count) captions"),
                    systemImage: "checkmark.circle.fill"
                )
                .font(.caption)
                .foregroundColor(.green)
                Spacer()
                previewButton
            }

            // Style presets
            styleSection

            Divider().padding(.vertical, 4)

            // Text editing
            textEditingSection

            // AI refinement
            refinementSection

            Divider().padding(.vertical, 4)

            // Mood analysis
            moodAnalysisSection
        }
    }

    private var previewButton: some View {
        Button {
            if let firstCaption = clip.captions.first {
                appState.playbackState.seek(to: firstCaption.startTime)
            }
        } label: {
            Label(String(localized: "action.preview", defaultValue: "Preview"), systemImage: "play.circle")
                .font(.caption)
        }
        .buttonStyle(.plain)
        .foregroundColor(Theme.Colors.accent)
        .help(String(localized: "action.preview.help", defaultValue: "Jump to first caption"))
        .accessibilityIdentifier("captions.action.preview")
    }

    private var styleSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            SubsectionHeader(title: "Style")
            // P1 FIX: Grid layout instead of horizontal scroll
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 80), spacing: 8)], spacing: 8) {
                ForEach(CaptionStyle.allPresets) { style in
                    let isSelected = appState.projectState.currentProject?.captionStyle.name == style.name

                    CaptionStylePreview(style: style)
                        .overlay(
                            // CRITICAL FIX: Show visual indicator for selected style
                            RoundedRectangle(cornerRadius: 6)
                                .stroke(isSelected ? Color.accentColor : Color.clear, lineWidth: 2)
                        )
                        .overlay(
                            // Checkmark for selected style
                            Group {
                                if isSelected {
                                    Image(systemName: "checkmark.circle.fill")
                                        .foregroundColor(.accentColor)
                                        .background(Circle().fill(Color(NSColor.controlBackgroundColor)))
                                        .font(.system(size: 16))
                                        .offset(x: 32, y: -20)
                                }
                            }
                        )
                        .onTapGesture {
                            appState.projectState.updateCaptionStyle(style)
                        }
                        .accessibilityLabel("\(style.name) caption style")
                        .accessibilityHint("Apply \(style.name) style to captions")
                        .accessibilityAddTraits(isSelected ? .isSelected : [])
                        // REMOVED: .focusable() - was causing yellow focus ring
                }
            }
        }
    }

    private var textEditingSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            SubsectionHeader(title: "Edit Text")
            if let project = appState.projectState.currentProject {
                CaptionListEditor(project: project)
            }
        }
    }

    private var refinementSection: some View {
        SmartToolButton(
            title: String(localized: "captions.action.refine", defaultValue: "Refine Captions"),
            subtitle: String(localized: "captions.action.refine.subtitle", defaultValue: "Fix grammar & tone with AI"),
            icon: "sparkles",
            color: .purple,
            isLoading: isRefining,
            id: "captions.action.refine"
        ) {
            Task { await refineCaptions() }
        }
        .keyboardShortcut("t", modifiers: [.command, .shift])
        .help(KeyboardShortcutHelper.helpWithShortcut(
            String(localized: "captions.action.refine", defaultValue: "Refine Captions"),
            key: "t",
            modifiers: [.command, .shift]
        ))
    }

    private var moodAnalysisSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            SubsectionHeader(title: "Mood Analysis")
            SmartToolButton(
                title: String(localized: "captions.action.analyze_mood", defaultValue: "Analyze Mood"),
                subtitle: String(localized: "captions.action.analyze_mood.subtitle", defaultValue: "Get color grading suggestions"),
                icon: "face.smiling",
                color: .orange,
                isLoading: isAnalyzing,
                id: "captions.action.analyze_mood"
            ) {
                Task { await analyzeMood() }
            }
            .disabled(clip.isMissing || clip.captions.isEmpty) // CRITICAL FIX: Disable if clip is missing or no captions
            .help(clip.isMissing ? "Clip file is missing. Use 'Locate File' in Clip Info to relink the file." : (clip.captions.isEmpty ? "Generate captions first to analyze mood" : "Analyze mood and get color grading suggestions"))
            .accessibilityHint(clip.isMissing ? "Clip file is missing. Use 'Locate File' in Clip Info to relink the file." : (clip.captions.isEmpty ? "Generate captions first to analyze mood" : "Analyze mood and get color grading suggestions"))

            if let result = analysisResult {
                InformationBox(text: result, color: .orange)
            }
        }
    }

    private var textDetectionSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            SubsectionHeader(title: "Text Detection")
            SmartToolButton(
                title: String(localized: "captions.action.scan_text", defaultValue: "Scan for Text"),
                subtitle: String(localized: "captions.action.scan_text.subtitle", defaultValue: "Find text in video (OCR)"),
                icon: "doc.text.viewfinder",
                color: .blue,
                isLoading: isAnalyzing, // CRITICAL FIX: Use isAnalyzing state for loading indicator
                id: "captions.action.scan_text"
            ) {
                Task { await scanForText() }
            }
            .disabled(clip.isMissing) // CRITICAL FIX: Disable if clip is missing
            .help(clip.isMissing ? "Clip file is missing. Use 'Locate File' in Clip Info to relink the file." : "Scan video for text using OCR")
            .accessibilityHint(clip.isMissing ? "Clip file is missing. Use 'Locate File' in Clip Info to relink the file." : "Scan video for text using OCR")

            DetectedItemsList(items: detectedText, color: .blue)
        }
    }

    // MARK: - Actions

    private func analyzeMood() async {
        // CRITICAL FIX: Validate captions exist
        guard !clip.captions.isEmpty else {
            await MainActor.run {
                analysisResult = "No captions to analyze. Generate captions first."
            }
            return
        }

        isAnalyzing = true
        defer {
            Task { @MainActor in
                isAnalyzing = false
            }
        }

        // CRITICAL FIX: Mood analysis doesn't throw, so no need for do-catch
        let captions = clip.captions.map {
            Caption(text: $0.text, startTime: $0.startTime, endTime: $0.endTime)
        }
        let sentiment = await ServiceContainer.shared.sentimentAnalysisService.getOverallMood(captions: captions)
        await MainActor.run {
            analysisResult = "\(sentiment.sentiment.emoji) Mood: \(sentiment.sentiment.rawValue) -> Suggested: " +
                "\(sentiment.suggestedColorGrade.rawValue) color grading"
        }
    }

    private func scanForText() async {
        // CRITICAL FIX: Validate clip before operation
        guard !clip.isMissing else {
            await MainActor.run {
                analysisResult = "Cannot scan text: Clip file is missing"
                detectedText = []
            }
            return
        }

        isAnalyzing = true
        defer {
            Task { @MainActor in
                isAnalyzing = false
            }
        }

        do {
            let progressTracker = ProgressTracker()
            let texts = try await ServiceContainer.shared.textRecognitionService.scanVideoForText(
                videoURL: clip.url
            ) { current, total in
                if progressTracker.shouldUpdate() {
                    Task { @MainActor in
                        analysisResult = "Scanning... \(current)/\(total) frames"
                    }
                }
            }
            await MainActor.run {
                if texts.isEmpty {
                    analysisResult = "No text detected in video"
                    detectedText = []
                } else {
                    analysisResult = "Found \(texts.count) text regions"
                    detectedText = texts.map { $0.text }
                }
            }
        } catch {
            await MainActor.run {
                analysisResult = "OCR failed: \(error.localizedDescription)"
                detectedText = []
                AppLogger.project.error("Text scanning failed: \(error.localizedDescription)")
            }
        }
    }

    private func refineCaptions() async {
        // CRITICAL FIX: Validate clip before operation
        guard !clip.isMissing else {
            await MainActor.run {
                ServiceContainer.shared.toastManager.show(
                    "Cannot refine captions: Clip file is missing",
                    type: .error
                )
            }
            return
        }

        guard !clip.captions.isEmpty else {
            await MainActor.run {
                ServiceContainer.shared.toastManager.show(
                    "No captions to refine. Generate captions first.",
                    type: .info
                )
            }
            return
        }

        isRefining = true
        defer {
            Task { @MainActor in
                isRefining = false
            }
        }

        do {
            // Use dynamic provider selection (prefers on-device, falls back to cloud if available)
            let refinedCaptions = try await ServiceContainer.shared.aiService.refineCaptionsWithBestProvider(clip.captions, prompt: "Refine captions for clarity and grammar")
            appState.projectState.updateCaptions(for: clip, newCaptions: refinedCaptions)
            ServiceContainer.shared.toastManager.show(
                String(localized: "toast.captions_refined", defaultValue: "Captions refined!")
            )
        } catch {
            ServiceContainer.shared.toastManager.show(
                String(localized: "toast.captions_refine_failed", defaultValue: "Refinement failed: \(error.localizedDescription)"),
                type: .error
            )
            AppLogger.project.error("Caption refinement failed: \(error.localizedDescription)")
        }
    }
}
