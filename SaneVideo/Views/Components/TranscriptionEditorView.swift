//
//  TranscriptionEditorView.swift
//  SaneVideo
//
//  Created by SaneVideo Refactor
//

import SwiftUI
import CoreMedia

/// Unified Captions Hub (2025-12-31)
/// PRIMARY location for caption editing, styling, and generation.
/// Combines transcription editing with style controls.
struct TranscriptionEditorView: View {
    @Environment(AppState.self) var appState
    @Binding var selectedClip: VideoClip?

    @State private var searchText = ""
    @State private var isRefining = false
    @State private var isTranslating = false
    @State private var isGeneratingTranscript = false
    @State private var showStylePicker = false

    // CRITICAL FIX (2025-12-31): Get fresh clip from project to ensure we have latest captions
    // The binding may point to a stale clip value. When captions are updated via ProjectState,
    // the project is updated but the binding may not refresh until the parent re-renders.
    // This mirrors the pattern used in StylesInspectorView.validatedClip.
    private var currentClip: VideoClip? {
        guard let clip = selectedClip,
              let project = appState.projectState.currentProject else {
            return nil
        }
        // Get fresh clip from project by ID
        for track in project.timeline.tracks {
            if let freshClip = track.clips.first(where: { $0.id == clip.id }) {
                return freshClip
            }
        }
        return nil
    }

    var filteredCaptions: [Caption] {
        guard let clip = currentClip else { return [] }
        if searchText.isEmpty {
            return clip.captions
        }
        return clip.captions.filter { $0.text.localizedCaseInsensitiveContains(searchText) }
    }
    
    var body: some View {
        VStack(spacing: 0) {
            // MARK: - Style Picker Bar (2025-12-31: Unified caption styling)
            stylePickerBar

            Divider()

            // Search & Tools Bar
            HStack {
                Image(systemName: "magnifyingglass")
                    .foregroundColor(Color.stone)
                TextField(String(localized: "transcript.search", defaultValue: "Search transcript..."), text: $searchText)
                    .textFieldStyle(.plain)

                if !filteredCaptions.isEmpty {
                    Button {
                        refineCaptions()
                    } label: {
                        Image(systemName: "sparkles")
                            .foregroundColor(.accentColor)
                    }
                    .buttonStyle(.plain)
                    .help(String(localized: "transcript.refine.help", defaultValue: "AI Refine Grammar & Punctuation"))
                    .disabled(isRefining)

                    if #available(macOS 15.0, *) {
                        Button {
                            translateCaptions()
                        } label: {
                            Image(systemName: "character.book.closed")
                                .foregroundColor(.accentColor)
                        }
                        .buttonStyle(.plain)
                        .help(String(localized: "transcript.translate.help", defaultValue: "Translate to Spanish (macOS 15+)"))
                        .disabled(isTranslating)
                    }
                }
            }
            .padding(10)
            .background(Color.black.opacity(0.2))

            Divider()
            
            if let clip = currentClip {
                if clip.captions.isEmpty {
                    emptyStateView(for: clip)
                } else {
                    List {
                        ForEach(filteredCaptions) { caption in
                            CaptionEditorRow(
                                caption: caption,
                                isCurrent: isPlayheadAt(caption, in: clip),
                                onSelect: {
                                    appState.playbackState.seek(to: CMTimeAdd(clip.startTime, caption.startTime))
                                },
                                onTextChange: { newText in
                                    updateCaptionText(caption, newText)
                                },
                                onDelete: {
                                    deleteCaptionSegment(caption, in: clip)
                                }
                            )
                        }
                    }
                    .listStyle(.plain)
                }
            } else {
                VStack {
                    Spacer()
                    Text(String(localized: "transcript.no_clip", defaultValue: "Select a clip to edit transcript"))
                        .foregroundColor(Color.stone)
                    Spacer()
                }
            }
        }
    }
    
    private func emptyStateView(for clip: VideoClip) -> some View {
        VStack(spacing: 12) {
            Spacer()
            Image(systemName: "captions.bubble")
                .font(.system(size: 32))
                .foregroundColor(Color.stone)
            Text(String(localized: "transcript.empty.title", defaultValue: "No Transcript"))
                .font(.headline)
            Button {
                Task {
                    await generateTranscript(for: clip)
                }
            } label: {
                HStack(spacing: 8) {
                    if isGeneratingTranscript {
                        ProgressView()
                            .controlSize(.small)
                    } else {
                        Image(systemName: "text.bubble.fill")
                    }

                    Text(
                        isGeneratingTranscript
                            ? String(
                                localized: "transcript.action.generating",
                                defaultValue: "Generating..."
                            )
                            : String(
                                localized: "transcript.action.generate",
                                defaultValue: "Generate AI Transcript"
                            )
                    )
                }
            }
            .buttonStyle(.borderedProminent)
            .disabled(isGeneratingTranscript)
            .help(
                String(
                    localized: "transcript.action.generate.help",
                    defaultValue: "Generate an on-device transcript for this clip."
                )
            )

            Text(
                String(
                    localized: "transcript.empty.helper",
                    defaultValue: "First run can take longer while on-device transcription warms up."
                )
            )
            .multilineTextAlignment(.center)
            .saneReadableSupportText()
            .frame(maxWidth: 280)
            Spacer()
        }
        .padding()
    }

    private func generateTranscript(for clip: VideoClip) async {
        guard !isGeneratingTranscript else { return }

        if clip.isMissing {
            ServiceContainer.shared.toastManager.show(
                "Cannot generate a transcript because the clip file is missing.",
                type: .error
            )
            return
        }

        isGeneratingTranscript = true
        defer { isGeneratingTranscript = false }

        do {
            _ = try await appState.projectState.generateCaptions(for: clip)
        } catch {
            ServiceContainer.shared.toastManager.show(
                "Transcript generation failed: \(error.localizedDescription)",
                type: .error
            )
        }
    }
    
    private func isPlayheadAt(_ caption: Caption, in clip: VideoClip) -> Bool {
        let currentTime = appState.playbackState.currentTime
        let mediaTime = clip.originalTime(forEffectiveTime: CMTimeSubtract(currentTime, clip.startTime))
        return mediaTime >= caption.startTime && mediaTime < caption.endTime
    }
    
    private func updateCaptionText(_ caption: Caption, _ newText: String) {
        guard let clip = currentClip else { return }

        // Update caption text while preserving timestamps
        var updatedCaptions = clip.captions
        if let index = updatedCaptions.firstIndex(where: { $0.id == caption.id }) {
            var updatedCaption = updatedCaptions[index]
            updatedCaption.text = newText
            updatedCaptions[index] = updatedCaption

            // Apply changes to project
            appState.projectState.updateCaptions(updatedCaptions, for: clip)

            AppLogger.project.info("📝 Updated caption \(caption.id): '\(newText)'")
        }
    }

    private func deleteCaptionSegment(_ caption: Caption, in clip: VideoClip) {
        // Text-based editing: deleting a segment adds it to removedRanges
        let range = CMTimeRange(start: caption.startTime, end: caption.endTime)
        appState.projectState.removeRange(range, from: clip)
    }

    private func refineCaptions() {
        guard let clip = currentClip else { return }
        isRefining = true
        Task {
            do {
                // Use dynamic provider selection (prefers on-device, falls back to cloud if available)
                let refined = try await ServiceContainer.shared.aiService.refineCaptions(clip.captions)
                await MainActor.run {
                    appState.projectState.updateCaptions(refined, for: clip)
                    isRefining = false
                    ServiceContainer.shared.toastManager.show(String(localized: "toast.transcript.refined", defaultValue: "✨ Transcript refined!"))
                }
            } catch {
                await MainActor.run {
                    isRefining = false
                    ServiceContainer.shared.toastManager.show(error.localizedDescription, type: .error)
                }
            }
        }
    }

    private func translateCaptions() {
        guard let clip = currentClip else { return }
        isTranslating = true
        Task {
            if #available(macOS 26.0, *) {
                do {
                    var translatedCaptions: [Caption] = []
                    for caption in clip.captions {
                        let translatedText = try await ServiceContainer.shared.translationService.translate(caption.text, to: "es") // Default to Spanish for now
                        var newCaption = caption
                        newCaption.text = translatedText
                        translatedCaptions.append(newCaption)
                    }

                    await MainActor.run {
                        appState.projectState.updateCaptions(translatedCaptions, for: clip)
                        isTranslating = false
                        ServiceContainer.shared.toastManager.show(String(localized: "toast.transcript.translated", defaultValue: "Transcript translated to Spanish!"))
                    }
                } catch {
                    await MainActor.run {
                        isTranslating = false
                        ServiceContainer.shared.toastManager.show(error.localizedDescription, type: .error)
                    }
                }
            }
        }
    }

    // MARK: - Style Picker (2025-12-31: Unified caption styling)

    private var stylePickerBar: some View {
        VStack(spacing: 0) {
            // Compact header with expand/collapse
            HStack {
                Label("Caption Style", systemImage: "textformat")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(Color.stone)

                Spacer()

                // Current style indicator
                if let project = appState.projectState.currentProject {
                    Text(project.captionStyle.name)
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundColor(.accentColor)
                }

                Button {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        showStylePicker.toggle()
                    }
                } label: {
                    Image(systemName: showStylePicker ? "chevron.up" : "chevron.down")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundColor(Color.stone)
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(Color.black.opacity(0.1))
            .contentShape(Rectangle())
            .onTapGesture {
                withAnimation(.easeInOut(duration: 0.2)) {
                    showStylePicker.toggle()
                }
            }

            // Expandable style grid
            if showStylePicker {
                styleGrid
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
    }

    private var styleGrid: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                // Show first 8 popular styles for quick access
                ForEach(Array(CaptionStyle.allPresets.prefix(8))) { style in
                    let isSelected = appState.projectState.currentProject?.captionStyle.name == style.name

                    Button {
                        appState.projectState.updateCaptionStyle(style)
                    } label: {
                        VStack(spacing: 4) {
                            CaptionStylePreview(style: style)
                                .frame(width: 60, height: 40)

                            Text(style.name)
                                .font(.system(size: 9, weight: isSelected ? .bold : .regular))
                                .foregroundColor(isSelected ? .accentColor : Color.stone)
                                .lineLimit(1)
                        }
                        .padding(4)
                        .background(isSelected ? Color.accentColor.opacity(0.15) : Color.clear)
                        .cornerRadius(6)
                        .overlay(
                            RoundedRectangle(cornerRadius: 6)
                                .stroke(isSelected ? Color.accentColor : Color.clear, lineWidth: 1.5)
                        )
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
        }
        .background(Color.black.opacity(0.15))
    }
}

struct CaptionEditorRow: View {
    let caption: Caption
    let isCurrent: Bool
    let onSelect: () -> Void
    let onTextChange: (String) -> Void
    let onDelete: () -> Void
    
    @State private var text: String
    
    init(caption: Caption, isCurrent: Bool, onSelect: @escaping () -> Void, onTextChange: @escaping (String) -> Void, onDelete: @escaping () -> Void) {
        self.caption = caption
        self.isCurrent = isCurrent
        self.onSelect = onSelect
        self.onTextChange = onTextChange
        self.onDelete = onDelete
        _text = State(initialValue: caption.text)
    }
    
    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            // Timestamp
            Text(formatTime(caption.startTime))
                .font(.system(.caption2, design: .monospaced))
                .foregroundColor(isCurrent ? .accentColor : Color.stone)
                .frame(width: 45, alignment: .leading)
            
            // Editable Text
            TextEditor(text: $text)
                .font(.system(size: 13))
                .frame(minHeight: 20)
                .fixedSize(horizontal: false, vertical: true)
                .scrollDisabled(true)
                .ifAvailable {
                    if #available(macOS 15.0, *) {
                        $0.writingToolsBehavior(.complete)
                    } else {
                        $0
                    }
                }
                .onChange(of: text) { _, newValue in
                    onTextChange(newValue)
                }
            
            // Actions
            if isCurrent {
                Button(action: onDelete) {
                    Image(systemName: "scissors")
                        .font(.caption)
                        .foregroundColor(.red)
                }
                .buttonStyle(.plain)
                .help(String(localized: "transcript.delete_segment", defaultValue: "Delete this segment from video"))
            }
        }
        .padding(6)
        .background(isCurrent ? Color.accentColor.opacity(0.1) : Color.clear)
        .cornerRadius(6)
        .onTapGesture {
            onSelect()
        }
    }
    
    private func formatTime(_ time: CMTime) -> String {
        let totalSeconds = Int(CMTimeGetSeconds(time))
        let minutes = totalSeconds / 60
        let seconds = totalSeconds % 60
        return String(format: "%02d:%02d", minutes, seconds)
    }
}
