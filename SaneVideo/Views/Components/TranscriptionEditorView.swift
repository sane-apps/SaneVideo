import SwiftUI
import CoreMedia

/// Main place to edit, style and generate captions.
struct TranscriptionEditorView: View {
    @Environment(AppState.self) var appState
    @Binding var selectedClip: VideoClip?

    @State private var searchText = ""
    @State private var isRefining = false
    @State private var isGeneratingTranscript = false
    @State private var showStylePicker = false

    // Read the clip fresh from the project: the binding can hold a stale value until the parent re-renders.
    private var currentClip: VideoClip? {
        guard let clip = selectedClip,
              let project = appState.projectState.currentProject else {
            return nil
        }
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
                            .foregroundColor(Theme.Colors.accent)
                    }
                    .buttonStyle(.plain)
                    .help(String(localized: "transcript.refine.help", defaultValue: "Fix grammar and punctuation (undo with ⌘Z)"))
                    .disabled(isRefining)
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

            appState.projectState.updateCaptions(updatedCaptions, for: clip)

            AppLogger.project.info("📝 Updated caption \(caption.id) (\(newText.count) characters)")
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

    // MARK: - Style Picker (2025-12-31: Unified caption styling)

    private var stylePickerBar: some View {
        VStack(spacing: 0) {
            HStack {
                Label("Caption Style", systemImage: "textformat")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(Color.stone)

                Spacer()

                if let project = appState.projectState.currentProject {
                    Text(project.captionStyle.name)
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundColor(Theme.Colors.accent)
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

            if showStylePicker {
                styleGrid
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
    }

    private var styleGrid: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
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
                                .foregroundColor(isSelected ? Theme.Colors.accent : Color.stone)
                                .lineLimit(1)
                        }
                        .padding(4)
                        .background(isSelected ? Theme.Colors.accent.opacity(0.15) : Color.clear)
                        .cornerRadius(6)
                        .overlay(
                            RoundedRectangle(cornerRadius: 6)
                                .stroke(isSelected ? Theme.Colors.accent : Color.clear, lineWidth: 1.5)
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
            Text(formatTime(caption.startTime))
                .font(.system(.caption2, design: .monospaced))
                .foregroundColor(isCurrent ? Theme.Colors.accent : Color.stone)
                .frame(width: 45, alignment: .leading)
            
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
        .background(isCurrent ? Theme.Colors.accent.opacity(0.1) : Color.clear)
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
