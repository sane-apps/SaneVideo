//
//  TranscriptTimelineView.swift
//  SaneVideo
//
//  Text-based editing view - Descript-style transcript editing
//  Displays transcript alongside timeline with word-level precision
//

import AVFoundation
import SwiftUI

/// Text-based editing view that displays transcript alongside timeline
/// Enables Descript-style editing: click text to jump, delete text to delete video
struct TranscriptTimelineView: View {
    @Environment(AppState.self) var appState
    @State private var selectedTextRange: NSRange?
    @State private var hoveredWordIndex: Int?
    @FocusState private var isEditing: Bool
    
    let clip: VideoClip
    
    // Computed transcript from captions
    private var transcript: String {
        clip.captions
            .sorted { $0.startTime.seconds < $1.startTime.seconds }
            .map { $0.text }
            .joined(separator: " ")
    }
    
    // Word-level segments with timestamps
    // Uses word-level timestamps from captions if available, otherwise estimates
    private var wordSegments: [WordSegment] {
        var segments: [WordSegment] = []
        var currentOffset = 0
        
        for caption in clip.captions.sorted(by: { $0.startTime.seconds < $1.startTime.seconds }) {
            // Check if we have word-level timestamps
            if let words = caption.words, !words.isEmpty {
                // Use precise word-level timestamps
                for word in words {
                    let startTime = CMTime(seconds: word.start, preferredTimescale: 600)
                    let endTime = CMTime(seconds: word.end, preferredTimescale: 600)
                    
                    segments.append(WordSegment(
                        text: word.text,
                        startTime: startTime,
                        endTime: endTime,
                        captionId: caption.id,
                        textOffset: currentOffset,
                        textLength: word.text.count
                    ))
                    
                    currentOffset += word.text.count + 1 // +1 for space
                }
            } else {
                // Fallback: estimate word timestamps from caption duration
                let words = caption.text.split(separator: " ")
                guard !words.isEmpty else { continue }
                
                let wordDuration = (caption.endTime.seconds - caption.startTime.seconds) / Double(words.count)
                
                for (index, word) in words.enumerated() {
                    let startTime = caption.startTime.seconds + (Double(index) * wordDuration)
                    let endTime = startTime + wordDuration
                    
                    segments.append(WordSegment(
                        text: String(word),
                        startTime: CMTime(seconds: startTime, preferredTimescale: 600),
                        endTime: CMTime(seconds: endTime, preferredTimescale: 600),
                        captionId: caption.id,
                        textOffset: currentOffset,
                        textLength: word.count
                    ))
                    
                    currentOffset += word.count + 1 // +1 for space
                }
            }
        }
        
        return segments
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header
            HStack {
                Label("Transcript Editor", systemImage: "text.bubble")
                    .font(.headline)
                Spacer()
                Button {
                    // Toggle word-level vs sentence-level view
                } label: {
                    Text("Word Level")
                        .font(.caption)
                }
                .buttonStyle(.borderless)
            }
            .padding()
            
            Divider()
            
            // Transcript Text View
            ScrollView {
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(sentenceSegments, id: \.id) { sentence in
                        TranscriptSentenceView(
                            sentence: sentence,
                            wordSegments: wordSegments.filter { segment in
                                segment.startTime.seconds >= sentence.startTime.seconds &&
                                segment.endTime.seconds <= sentence.endTime.seconds
                            },
                            currentTime: appState.playbackState.currentTime,
                            clipStart: clip.startTime,
                            onWordClick: { segment in
                                seekToWord(segment)
                            },
                            onWordSelect: { range in
                                selectTextRange(range)
                            },
                            onDelete: {
                                deleteSentence(sentence)
                            }
                        )
                    }
                }
                .padding()
            }
            .frame(maxHeight: 300)
            
            Divider()
            
            // Timeline sync indicator
            HStack {
                Text("Synced with timeline")
                    .font(.caption)
                    .foregroundColor(.secondary)
                Spacer()
                if let selectedRange = selectedTextRange {
                    Text("Selected: \(selectedRange.length) characters")
                        .font(.caption)
                        .foregroundColor(.accentColor)
                }
            }
            .padding()
        }
        .background(.regularMaterial)
        .cornerRadius(8)
    }
    
    // MARK: - Sentence Segmentation
    
    private var sentenceSegments: [SentenceSegment] {
        var sentences: [SentenceSegment] = []
        var currentSentence = ""
        var sentenceStart: CMTime?
        var sentenceWords: [WordSegment] = []
        
        // Use NaturalLanguage framework for better sentence detection
        let wordSegs = wordSegments
        
        for (index, wordSeg) in wordSegs.enumerated() {
            if currentSentence.isEmpty {
                sentenceStart = wordSeg.startTime
            }
            
            currentSentence += (currentSentence.isEmpty ? "" : " ") + wordSeg.text
            sentenceWords.append(wordSeg)
            
            // Check for sentence boundaries (period, exclamation, question mark)
            let text = wordSeg.text
            let isSentenceEnd = text.hasSuffix(".") || text.hasSuffix("!") || text.hasSuffix("?")
            
            // Also check if next word starts a new sentence (capital letter after punctuation)
            let isNextWordNewSentence = index < wordSegs.count - 1 && 
                wordSegs[index + 1].text.first?.isUppercase == true &&
                (text.hasSuffix(".") || text.hasSuffix("!") || text.hasSuffix("?"))
            
            if isSentenceEnd || isNextWordNewSentence || index == wordSegs.count - 1 {
                let sentenceEnd = wordSeg.endTime
                sentences.append(SentenceSegment(
                    id: UUID(),
                    text: currentSentence,
                    startTime: sentenceStart ?? wordSeg.startTime,
                    endTime: sentenceEnd
                ))
                currentSentence = ""
                sentenceStart = nil
                sentenceWords = []
            }
        }
        
        // Add any remaining text as final sentence
        if !currentSentence.isEmpty, let start = sentenceStart {
            sentences.append(SentenceSegment(
                id: UUID(),
                text: currentSentence,
                startTime: start,
                endTime: clip.duration
            ))
        }
        
        return sentences
    }
    
    // MARK: - Actions
    
    private func seekToWord(_ segment: WordSegment) {
        let timelineTime = CMTimeAdd(clip.startTime, segment.startTime)
        appState.playbackState.seek(to: timelineTime)
    }
    
    private func selectTextRange(_ range: NSRange) {
        selectedTextRange = range
        
        // Use ProjectState helper to map text range to time range
        if let timeRange = appState.projectState.textRangeToTimeRange(range, in: clip) {
            // Select the clip and seek to the start of the selected range
            appState.selectedClipIds = [clip.id]
            let timelineTime = CMTimeAdd(clip.startTime, timeRange.start)
            appState.playbackState.seek(to: timelineTime)
            
            AppLogger.project.info("📝 Text selection mapped to time range: \(timeRange.start.seconds)-\(timeRange.end.seconds)")
        }
    }
    
    private func deleteSentence(_ sentence: SentenceSegment) {
        let timeRange = CMTimeRange(start: sentence.startTime, duration: CMTimeSubtract(sentence.endTime, sentence.startTime))
        // Use ripple delete for sentence deletion (shifts subsequent content left)
        appState.projectState.removeRange(timeRange, from: clip, rippleDelete: true)
        ServiceContainer.shared.toastManager.show("✂️ Deleted sentence and shifted timeline")
    }
}

// MARK: - Supporting Types

struct WordSegment: Identifiable {
    let id = UUID()
    let text: String
    let startTime: CMTime
    let endTime: CMTime
    let captionId: UUID
    let textOffset: Int
    let textLength: Int
}

struct SentenceSegment: Identifiable {
    let id: UUID
    let text: String
    let startTime: CMTime
    let endTime: CMTime
}

// MARK: - Sentence View

struct TranscriptSentenceView: View {
    let sentence: SentenceSegment
    let wordSegments: [WordSegment]
    let currentTime: CMTime
    let clipStart: CMTime
    let onWordClick: (WordSegment) -> Void
    let onWordSelect: (NSRange) -> Void
    let onDelete: () -> Void
    
    @State private var isHovered = false
    @State private var selectedWordIndices: Set<Int> = []
    
    private var isActive: Bool {
        let mediaTime = CMTimeSubtract(currentTime, clipStart)
        return mediaTime >= sentence.startTime && mediaTime < sentence.endTime
    }
    
    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            // Timestamp
            Text(formatTime(sentence.startTime))
                .font(.caption2.monospaced())
                .foregroundColor(isActive ? .accentColor : .secondary)
                .frame(width: 50, alignment: .leading)
            
            // Sentence text with word-level highlighting
            HStack(spacing: 4) {
                ForEach(Array(wordSegments.enumerated()), id: \.element.id) { index, segment in
                    WordView(
                        segment: segment,
                        currentTime: currentTime,
                        clipStart: clipStart,
                        isSelected: selectedWordIndices.contains(index),
                        onClick: { 
                            onWordClick(segment)
                            // Toggle selection
                            if selectedWordIndices.contains(index) {
                                selectedWordIndices.remove(index)
                            } else {
                                selectedWordIndices.insert(index)
                            }
                            // Update text selection range
                            if !selectedWordIndices.isEmpty {
                                let sortedIndices = selectedWordIndices.sorted()
                                let firstIndex = sortedIndices.first!
                                let lastIndex = sortedIndices.last!
                                let startOffset = wordSegments[firstIndex].textOffset
                                let endOffset = wordSegments[lastIndex].textOffset + wordSegments[lastIndex].textLength
                                let range = NSRange(location: startOffset, length: endOffset - startOffset)
                                onWordSelect(range)
                            }
                        }
                    )
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            
            // Delete button
            if isHovered {
                Button(action: onDelete) {
                    Image(systemName: "trash")
                        .font(.caption)
                        .foregroundColor(.red)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.vertical, 4)
        .padding(.horizontal, 8)
        .background(isActive ? Color.accentColor.opacity(0.1) : Color.clear)
        .cornerRadius(4)
        .onHover { hovering in
            isHovered = hovering
        }
    }
    
    private func formatTime(_ time: CMTime) -> String {
        let totalSeconds = Int(time.seconds)
        let mins = totalSeconds / 60
        let secs = totalSeconds % 60
        return String(format: "%02d:%02d", mins, secs)
    }
}

// MARK: - Word View

struct WordView: View {
    let segment: WordSegment
    let currentTime: CMTime
    let clipStart: CMTime
    let isSelected: Bool
    let onClick: () -> Void
    
    @State private var isHovered = false
    
    private var isActive: Bool {
        let mediaTime = CMTimeSubtract(currentTime, clipStart)
        return mediaTime >= segment.startTime && mediaTime < segment.endTime
    }
    
    var body: some View {
        Text(segment.text)
            .font(.system(size: 13))
            .foregroundColor(isSelected ? .white : (isActive ? .accentColor : .primary))
            .underline(isActive || isSelected)
            .background(
                Group {
                    if isSelected {
                        Color.accentColor
                    } else if isHovered {
                        Color.accentColor.opacity(0.2)
                    } else {
                        Color.clear
                    }
                }
            )
            .cornerRadius(2)
            .padding(.horizontal, 2)
            .onTapGesture {
                onClick()
            }
            .onHover { hovering in
                isHovered = hovering
            }
    }
}

