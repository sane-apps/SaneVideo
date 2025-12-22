//
//  TranscriptionEditorView.swift
//  SaneVideo
//
//  Created by SaneVideo Refactor
//

import SwiftUI
import CoreMedia

struct TranscriptionEditorView: View {
    @Environment(AppState.self) var appState
    @Binding var selectedClip: VideoClip?
    
    @State private var searchText = ""
    @State private var isRefining = false
    
    var filteredCaptions: [Caption] {
        guard let clip = selectedClip else { return [] }
        if searchText.isEmpty {
            return clip.captions
        }
        return clip.captions.filter { $0.text.localizedCaseInsensitiveContains(searchText) }
    }
    
    var body: some View {
        VStack(spacing: 0) {
            // Search & Tools Bar
            HStack {
                Image(systemName: "magnifyingglass")
                    .foregroundColor(.secondary)
                TextField(String(localized: "transcript.search", defaultValue: "Search transcript..."), text: $searchText)
                    .textFieldStyle(.plain)
                
                if !filteredCaptions.isEmpty {
                    Button {
                        refineCaptions()
                    } label: {
                        Image(systemName: "magicmouse")
                            .foregroundColor(.accentColor)
                    }
                    .buttonStyle(.plain)
                    .help(String(localized: "transcript.refine.help", defaultValue: "AI Refine Grammar & Punctuation"))
                    .disabled(isRefining)
                }
            }
            .padding(10)
            .background(Color.black.opacity(0.2))
            
            Divider()
            
            if let clip = selectedClip {
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
                        .foregroundColor(.secondary)
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
                .foregroundColor(.secondary)
            Text(String(localized: "transcript.empty.title", defaultValue: "No Transcript"))
                .font(.headline)
            Button(String(localized: "transcript.action.generate", defaultValue: "Generate AI Transcript")) {
                Task {
                    _ = try? await appState.projectState.generateCaptions(for: clip)
                }
            }
            .buttonStyle(.borderedProminent)
            Spacer()
        }
        .padding()
    }
    
    private func isPlayheadAt(_ caption: Caption, in clip: VideoClip) -> Bool {
        let currentTime = appState.playbackState.currentTime
        let mediaTime = clip.originalTime(forEffectiveTime: CMTimeSubtract(currentTime, clip.startTime))
        return mediaTime >= caption.startTime && mediaTime < caption.endTime
    }
    
    private func updateCaptionText(_ caption: Caption, _ newText: String) {
        // Implementation for text update
    }
    
    private func deleteCaptionSegment(_ caption: Caption, in clip: VideoClip) {
        // Text-based editing: deleting a segment adds it to removedRanges
        let range = CMTimeRange(start: caption.startTime, end: caption.endTime)
        appState.projectState.removeRange(range, from: clip)
    }
    
    private func refineCaptions() {
        guard let clip = selectedClip else { return }
        isRefining = true
        Task {
            do {
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
                .foregroundColor(isCurrent ? .accentColor : .secondary)
                .frame(width: 45, alignment: .leading)
            
            // Editable Text
            TextEditor(text: $text)
                .font(.system(size: 13))
                .frame(minHeight: 20)
                .fixedSize(horizontal: false, vertical: true)
                .scrollDisabled(true)
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
