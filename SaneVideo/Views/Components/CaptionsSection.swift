//
//  CaptionsSection.swift
//  SaneVideo
//
//  Extracted from StylesInspectorView.swift
//  Contains caption-related inspector controls (Style, OCR, Mood)
//

import SwiftUI
import AVFoundation

// MARK: - CAPTIONS Section (Style + OCR + Mood)

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
                HStack(spacing: 6) {
                    Image(systemName: "info.circle")
                        .foregroundColor(.orange)
                    Text(String(localized: "captions.empty_hint", defaultValue: "Use Magic Fix to generate captions"))
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            } else {
                HStack {
                    Label(String(localized: "captions.count", defaultValue: "\(clip.captions.count) captions"), systemImage: "checkmark.circle.fill")
                        .font(.caption)
                        .foregroundColor(.green)
                    Spacer()

                    // Preview Caption Button - jumps to first caption
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

                // Style presets
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

                Divider().padding(.vertical, 4)

                // TEXT EDITING
                SubsectionHeader(title: "Edit Text")
                if let project = appState.projectState.currentProject {
                   CaptionListEditor(project: project)
                }
                
                // AI REFINEMENT
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
                .help(KeyboardShortcutHelper.helpWithShortcut(String(localized: "captions.action.refine", defaultValue: "Refine Captions"), key: "t", modifiers: [.command, .shift]))

                Divider().padding(.vertical, 4)

                // Mood Analysis
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
                    Text(result)
                        .font(.caption2)
                        .foregroundColor(.secondary)
                        .padding(6)
                        .background(Color.orange.opacity(0.1))
                        .cornerRadius(4)
                }
            }

            Divider().padding(.vertical, 4)

            // OCR / Scan for Text
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

            if !detectedText.isEmpty {
                VStack(alignment: .leading, spacing: 2) {
                    ForEach(detectedText.prefix(3), id: \.self) { text in
                        Text("• \(text)")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    }
                }
                .padding(6)
                .background(Color.blue.opacity(0.1))
                .cornerRadius(4)
            }
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
        analysisResult = "\(sentiment.sentiment.emoji) Mood: \(sentiment.sentiment.rawValue) → Suggested: \(sentiment.suggestedColorGrade.rawValue) color grading"
    }

    private func scanForText() async {
        isAnalyzing = true
        defer { isAnalyzing = false }

        do {
            let progressTracker = ProgressTracker()
            let analysisResultBinding = $analysisResult
            let texts = try await ServiceContainer.shared.textRecognitionService.scanVideoForText(videoURL: clip.url) { current, total in
                 if progressTracker.shouldUpdate() {
                    Task { @MainActor in
                        analysisResultBinding.wrappedValue = "📝 Scanning... \(current)/\(total) frames"
                    }
                }
            }
            if texts.isEmpty {
                analysisResult = "No text detected in video"
                detectedText = []
            } else {
                analysisResult = "📝 Found \(texts.count) text regions"
                detectedText = texts.map { $0.text }
            }
        } catch {
            analysisResult = "❌ OCR failed: \(error.localizedDescription)"
        }
    }

    private func refineCaptions() async {
        isRefining = true
        defer { isRefining = false }

        do {
            let refinedCaptions = try await ServiceContainer.shared.aiService.refineCaptions(clip.captions)
            appState.projectState.updateCaptions(for: clip, newCaptions: refinedCaptions)
            ServiceContainer.shared.toastManager.show(String(localized: "toast.captions_refined", defaultValue: "Captions refined! ✨"))
        } catch {
            ServiceContainer.shared.toastManager.show(String(localized: "toast.captions_refine_failed", defaultValue: "Refinement failed: \(error.localizedDescription)"), type: .error)
        }
    }
}

// MARK: - Caption Style Preview

struct CaptionStylePreview: View {
    let style: CaptionStyle

    var body: some View {
        VStack(spacing: 6) {
            // Larger preview with sample text
            ZStack {
                // Background
                RoundedRectangle(cornerRadius: 6)
                    .fill(Color.secondary.opacity(0.1))
                    .frame(width: 80, height: 50)

                // Sample caption text
                Text("Hello")
                    .font(.custom(style.fontName, size: 12))
                    .fontWeight(style.isBold ? .bold : .regular)
                    .italic(style.isItalic)
                    .foregroundColor(Color(hex: style.textColor))
                    .shadow(
                        color: Color(hex: style.shadowColor ?? "#000000").opacity(style.shadowRadius > 0 ? 0.5 : 0),
                        radius: style.shadowRadius,
                        x: 0,
                        y: 1
                    )
                    .padding(.horizontal, 6)
                    .padding(.vertical, 3)
                    .background(Color(hex: style.backgroundColor ?? "#00000000"))
                    .cornerRadius(4)
            }

            Text(style.name)
                .font(.caption)
                .foregroundColor(.secondary)
                .lineLimit(1)
        }
    }
}

// MARK: - Clip Info Section

struct ClipInfoSection: View {
    let clip: VideoClip
    @State private var resolution: String = "Loading..."

    /// Display-friendly name for the clip
    private var displayName: String {
        let filename = clip.url.deletingPathExtension().lastPathComponent
        if UUID(uuidString: filename) != nil {
            let prefix = String(filename.prefix(8))
            return "Recording \(prefix)"
        }
        return filename
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            InfoRow(label: "Name", value: displayName)
            InfoRow(label: "Duration", value: String(format: "%.2fs", clip.duration.seconds))
            InfoRow(label: "Resolution", value: resolution)
        }
        .task(id: clip.url) {
            await loadResolution()
        }
    }

    private func loadResolution() async {
        let asset = AVURLAsset(url: clip.url)
        if let track = try? await asset.loadTracks(withMediaType: .video).first {
            if let size = try? await track.load(.naturalSize) {
                resolution = "\(Int(size.width)) × \(Int(size.height))"
                return
            }
        }
        resolution = "Unknown"
    }
}

// MARK: - Cursor Enhancements View

struct CursorEnhancementsView: View {
    @Environment(AppState.self) var appState
    let clip: VideoClip

    @State private var showHighlight: Bool

    init(clip: VideoClip) {
        self.clip = clip
        _showHighlight = State(initialValue: clip.showCursorHighlight)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(String(localized: "captions.cursor.desc", defaultValue: "Enhance cursor visibility for screen recordings"))
                .font(.caption)
                .foregroundColor(.secondary)

            Toggle(String(localized: "captions.cursor.toggle", defaultValue: "Show Highlight"), isOn: $showHighlight)
                .accessibilityIdentifier("captions.cursor.toggle")
                .onChange(of: showHighlight) { _, newValue in
                    appState.projectState.updateClipCursorHighlight(clip, show: newValue)
                }
        }
    }
}
