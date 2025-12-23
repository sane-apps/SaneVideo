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

    @State private var isAnalyzing = false
    @State private var isRefining = false
    @State private var detectedText: [String] = []
    @State private var analysisResult: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
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
    }

    // MARK: - Subviews

    private var emptyCaptionsHint: some View {
        HStack(spacing: 6) {
            Image(systemName: "info.circle")
                .foregroundColor(.orange)
            Text(String(localized: "captions.empty_hint", defaultValue: "Use Magic Fix to generate captions"))
                .font(.caption)
                .foregroundColor(.secondary)
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
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(CaptionStyle.allPresets) { style in
                        CaptionStylePreview(style: style)
                            .onTapGesture {
                                appState.projectState.updateCaptionStyle(style)
                            }
                    }
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
                isLoading: false,
                id: "captions.action.scan_text"
            ) {
                Task { await scanForText() }
            }

            DetectedItemsList(items: detectedText, color: .blue)
        }
    }

    // MARK: - Actions

    private func analyzeMood() async {
        isAnalyzing = true
        defer { isAnalyzing = false }

        let captions = clip.captions.map {
            Caption(text: $0.text, startTime: $0.startTime, endTime: $0.endTime)
        }
        let sentiment = await ServiceContainer.shared.sentimentAnalysisService.getOverallMood(captions: captions)
        analysisResult = "\(sentiment.sentiment.emoji) Mood: \(sentiment.sentiment.rawValue) -> Suggested: " +
            "\(sentiment.suggestedColorGrade.rawValue) color grading"
    }

    private func scanForText() async {
        isAnalyzing = true
        defer { isAnalyzing = false }

        do {
            let progressTracker = ProgressTracker()
            let analysisResultBinding = $analysisResult
            let texts = try await ServiceContainer.shared.textRecognitionService.scanVideoForText(
                videoURL: clip.url
            ) { current, total in
                if progressTracker.shouldUpdate() {
                    Task { @MainActor in
                        analysisResultBinding.wrappedValue = "Scanning... \(current)/\(total) frames"
                    }
                }
            }
            if texts.isEmpty {
                analysisResult = "No text detected in video"
                detectedText = []
            } else {
                analysisResult = "Found \(texts.count) text regions"
                detectedText = texts.map { $0.text }
            }
        } catch {
            analysisResult = "OCR failed: \(error.localizedDescription)"
        }
    }

    private func refineCaptions() async {
        isRefining = true
        defer { isRefining = false }

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
        }
    }
}
