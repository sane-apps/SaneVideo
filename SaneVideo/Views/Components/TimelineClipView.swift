//
//  TimelineClipView.swift
//  SaneVideo
//
//  Created by SaneVideo Refactor
//

import AVFoundation
import CoreMedia
import SwiftUI
import AppKit

struct TimelineClipView: View {
    let clip: VideoClip
    let pixelsPerSecond: CGFloat
    let isSelected: Bool
    let playheadTime: CMTime
    var onTrimStart: ((CMTime) -> Void)?
    var onTrimEnd: ((CMTime) -> Void)?
    var onDelete: (() -> Void)?
    var onSplit: (() -> Void)?
    var onRemoveSilence: (() -> Void)?
    var onRemoveFillers: (() -> Void)?
    var onGenerateCaptions: (() -> Void)?
    var onSmartCrop: ((CGFloat) -> Void)?
    var onAutoFrame: (() -> Void)?
    var onFindGestures: (() -> Void)?
    var onPrivacyBlur: (() -> Void)?
    var onFindHighlights: (() -> Void)?
    var onDeleteFile: (() -> Void)?
    var onSetTransition: ((TransitionType) -> Void)?
    var onSelect: ((CMTime?) -> Void)?

    @State private var waveformSamples: [Float]?
    @State private var isDraggingLeftHandle = false
    @State private var isDraggingRightHandle = false
    @State private var leftTrimOffset: CGFloat = 0
    @State private var rightTrimOffset: CGFloat = 0
    @State private var isHovering = false
    @State private var showingDeleteFileConfirmation = false

    private let handleWidth: CGFloat = 14
    private let clipHeight: CGFloat = 80
    private let snapThreshold: CGFloat = 10
    
    var clipWidth: CGFloat {
        max(60, CGFloat(clip.effectiveDuration.seconds) * pixelsPerSecond)
    }
    
    var computedSamples: [Float]? {
        guard let originalSamples = waveformSamples else { return nil }
        guard !clip.removedRanges.isEmpty else { return originalSamples }
        return ClipWaveformCalculator.computeStitchedSamples(originalSamples: originalSamples, clip: clip)
    }
    
    var stitchMarkers: [Double] {
        ClipWaveformCalculator.computeStitchMarkers(clip: clip)
    }

    var body: some View {
        ZStack(alignment: .leading) {
            HStack(spacing: 0) {
                // LEFT TRIM HANDLE
                ClipTrimHandle(
                    isLeft: true, clipHeight: clipHeight, pixelsPerSecond: pixelsPerSecond,
                    clip: clip, playheadTime: playheadTime, snapThreshold: snapThreshold,
                    onTrimStart: onTrimStart, onTrimEnd: nil,
                    isDragging: $isDraggingLeftHandle, trimOffset: $leftTrimOffset
                )
                
                // CLIP CONTENT
                clipContent
                
                // RIGHT TRIM HANDLE
                ClipTrimHandle(
                    isLeft: false, clipHeight: clipHeight, pixelsPerSecond: pixelsPerSecond,
                    clip: clip, playheadTime: playheadTime, snapThreshold: snapThreshold,
                    onTrimStart: nil, onTrimEnd: onTrimEnd,
                    isDragging: $isDraggingRightHandle, trimOffset: $rightTrimOffset
                )
            }
        }
        .frame(width: max(0, clipWidth + (isDraggingRightHandle ? rightTrimOffset : 0) - (isDraggingLeftHandle ? leftTrimOffset : 0)), height: clipHeight)
        .accessibilityIdentifier("TimelineClip")
        .accessibilityLabel(clip.url.lastPathComponent)
        .offset(x: isDraggingLeftHandle ? leftTrimOffset : 0)
        .background(isSelected ? Color.accentColor : Color.secondary.opacity(0.3))
        .cornerRadius(Theme.Dimensions.cornerRadius)
        .shadow(color: .black.opacity(0.3), radius: 2, x: 0, y: 1)
        .overlay(RoundedRectangle(cornerRadius: 6).stroke(isSelected ? Color.yellow : Color.clear, lineWidth: 2))
        .onHover { hovering in
            withAnimation(.easeInOut(duration: 0.15)) { isHovering = hovering }
        }
        .simultaneousGesture(
            DragGesture(minimumDistance: 0, coordinateSpace: .local)
                .onEnded { value in
                    if !isDraggingLeftHandle && !isDraggingRightHandle {
                        let percent = value.startLocation.x / (clipWidth - handleWidth * 2)
                        let safePercent = max(0, min(1.0, percent))
                        let timeOffset = clip.effectiveDuration.seconds * Double(safePercent)
                        let seekTime = CMTimeAdd(clip.startTime, CMTime(seconds: timeOffset, preferredTimescale: 600))
                        onSelect?(seekTime)
                    }
                }
        )
        .task {
            // ROBUSTNESS: Thumbnails are now JIT loaded by the cells themselves to avoid OOM
            await loadWaveform()
        }
        .contextMenu {
            ClipContextMenu(
                clip: clip,
                onSplit: onSplit, onDelete: onDelete, onRemoveSilence: onRemoveSilence,
                onRemoveFillers: onRemoveFillers, onGenerateCaptions: onGenerateCaptions,
                onSmartCrop: onSmartCrop, onAutoFrame: onAutoFrame, onFindGestures: onFindGestures,
                onPrivacyBlur: onPrivacyBlur, onFindHighlights: onFindHighlights,
                onDeleteFile: { showingDeleteFileConfirmation = true },
                onSetTransition: onSetTransition
            )
        }
        .alert(String(localized: "timeline.clip.delete_file.title", defaultValue: "Delete File?"), isPresented: $showingDeleteFileConfirmation) {
            Button(String(localized: "action.cancel", defaultValue: "Cancel"), role: .cancel) { }
                .accessibilityIdentifier("timeline.clip.delete_file.cancel")
            Button(String(localized: "action.delete_forever", defaultValue: "Delete Forever"), role: .destructive) { onDeleteFile?() }
                .accessibilityIdentifier("timeline.clip.delete_file.confirm")
        } message: {
            Text(String(localized: "timeline.clip.delete_file.message", defaultValue: "This will move the file to the Trash") + ": '\(clip.url.lastPathComponent)'.")
        }
    }
    
    // MARK: - Clip Content
    
    private var clipContent: some View {
        VStack(spacing: 0) {
            // VIDEO TRACK (Top ~55%)
            ZStack(alignment: .leading) {
                Rectangle().fill(Color.accentColor.opacity(0.3))
                thumbnailStrip
                clipLabel
            }
            .frame(height: clipHeight * 0.55)
            .clipped()
            
            // AUDIO TRACK (Bottom ~45%)
            ZStack(alignment: .bottom) {
                Rectangle().fill(Color(white: 0.15))
                waveformDisplay
                stitchMarkerOverlay
                durationLabel
            }
            .frame(height: clipHeight * 0.45)
            .clipped()
        }
        .frame(width: max(0, clipWidth - handleWidth * 2 + (isDraggingRightHandle ? rightTrimOffset : 0) - (isDraggingLeftHandle ? leftTrimOffset : 0)), height: clipHeight)
        .offset(x: isDraggingLeftHandle ? -leftTrimOffset : 0)
        .clipped()
        .background(Color.black)
        .cornerRadius(4)
        .overlay(alignment: .topTrailing) { hoverButtons }
    }
    
    // MARK: - Components
    
    private var thumbnailStrip: some View {
        // ROBUSTNESS: 10-hour video support
        // We calculate how many thumbnails we need based on width, but we DO NOT load them all.
        // LazyHStack ensures we only create the Views for visible area.
        // Each View then triggers its own async load.
        let targetThumbWidth: CGFloat = 80
        // Ensure at least 1 thumb
        let thumbCount = max(1, Int(clipWidth / targetThumbWidth))
        let singleThumbWidth = clipWidth / CGFloat(thumbCount)
        
        return LazyHStack(spacing: 0) {
            ForEach(0..<thumbCount, id: \.self) { index in
                // Calculate time for this specific thumnnail slot
                let fraction = Double(index) / Double(max(1, thumbCount))
                let time = CMTime(seconds: clip.effectiveDuration.seconds * fraction, preferredTimescale: 600)
                let originalTime = clip.originalTime(forEffectiveTime: time)
                
                TimelineThumbnailCell(
                    clip: clip,
                    time: originalTime,
                    size: CGSize(width: singleThumbWidth * 2, height: 80 * 2) // Request retina quality
                )
                .frame(width: singleThumbWidth)
            }
        }
    }
    
    private var clipLabel: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack {
                Text(clip.url.deletingPathExtension().lastPathComponent)
                    .font(.caption2.bold()).foregroundColor(.white).shadow(color: .black, radius: 2)
                if !clip.removedRanges.isEmpty {
                    Image(systemName: "scissors.badge.ellipsis").font(.system(size: 8)).foregroundColor(.orange)
                }
            }
            Spacer()
        }.padding(4)
    }
    
    private var waveformDisplay: some View {
        Group {
            if let samples = computedSamples {
                WaveformView(samples: samples).foregroundColor(.green).padding(.vertical, 2)
            } else if let samples = waveformSamples {
                WaveformView(samples: samples).foregroundColor(.green).padding(.vertical, 2)
            } else {
                Rectangle().fill(Color.green.opacity(0.2)).frame(height: 2)
            }
        }
    }
    
    private var stitchMarkerOverlay: some View {
        ForEach(stitchMarkers, id: \.self) { progress in
            Rectangle().fill(Color.orange).frame(width: 1)
                .offset(x: CGFloat(progress) * max(0, clipWidth - handleWidth * 2))
        }
    }
    
    private var durationLabel: some View {
        HStack {
            Spacer()
            Text(formatDuration(clip.effectiveDuration))
                .font(.system(size: 9)).foregroundColor(.white.opacity(0.6)).padding(2)
        }
    }
    
    @ViewBuilder
    private var hoverButtons: some View {
        if isHovering || isSelected {
            HStack(spacing: 8) {
                Button(action: { onSplit?() }, label: {
                    Image(systemName: "scissors").font(.system(size: 12)).foregroundColor(.white)
                        .frame(width: 28, height: 28).background(Color.orange).clipShape(Circle())
                        .shadow(color: .black.opacity(0.3), radius: 2)
                })
                .buttonStyle(.plain)
                .accessibilityIdentifier("timeline.clip.action.split")
                .help(KeyboardShortcutHelper.helpWithShortcut(String(localized: "timeline.clip.action.split.help", defaultValue: "Split clip at playhead"), key: "b", modifiers: [.command]))
                
                Button(action: { onDelete?() }, label: {
                    Image(systemName: "trash").font(.system(size: 12)).foregroundColor(.white)
                        .frame(width: 28, height: 28).background(Color.red).clipShape(Circle())
                        .shadow(color: .black.opacity(0.3), radius: 2)
                })
                .buttonStyle(.plain)
                .accessibilityIdentifier("timeline.clip.action.delete")
                .help(KeyboardShortcutHelper.helpWithShortcut(String(localized: "timeline.clip.action.delete.help", defaultValue: "Delete clip"), key: .delete))
            }.padding(8)
        }
    }
    
    // MARK: - Data Loading
    
    // Removed eager loadThumbnails() to prevent OOM on large files
    
    private func loadWaveform() async {
        if let samples = await ServiceContainer.shared.waveformService.waveform(for: clip) {
            await MainActor.run { self.waveformSamples = samples }
        }
    }
    
    private func formatDuration(_ time: CMTime) -> String {
        let seconds = CMTimeGetSeconds(time)
        return String(format: "%d:%02d", Int(seconds) / 60, Int(seconds) % 60)
    }
}

// Extension to set cursor
extension View {
    func cursor(_ cursor: NSCursor) -> some View {
        self.onHover { inside in
            if inside { cursor.push() } else { NSCursor.pop() }
        }
    }
}

// MARK: - Robust Thumbnail Cell

/// A self-loading thumbnail cell for JIT (Just-In-Time) rendering in LazyHStacks.
/// Prevents OOM crashes on massive timeline assets (e.g. 10hr videos).
struct TimelineThumbnailCell: View {
    let clip: VideoClip
    let time: CMTime
    let size: CGSize
    
    @State private var image: NSImage?
    @State private var isLoading = false
    
    var body: some View {
        ZStack {
            if let image = image {
                Image(nsImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
            } else {
                Rectangle()
                    .fill(Color.secondary.opacity(0.1))
            }
        }
        .clipped()
        .task {
            // Check cache or load
            // Note: ServiceContainer handles internal caching of generated results
            guard image == nil && !isLoading else { return }
            isLoading = true
            
            // Prioritize Visible Area: Detached task with userInteractive QoS
            // This ensures scrolling feels snappy
            let thumb = await ServiceContainer.shared.timelineThumbnailService.thumbnail(
                for: clip,
                time: time,
                size: size
            )
            
            await MainActor.run {
                self.image = thumb
                self.isLoading = false
            }
        }
    }
}
