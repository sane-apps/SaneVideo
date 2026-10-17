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
    var onFindGestures: (() -> Void)?
    var onPrivacyBlur: (() -> Void)?
    var onDeleteFile: (() -> Void)?
    var onRelink: (() -> Void)?
    var onSetTransition: ((TransitionType) -> Void)?
    /// Selection callback with seek time and modifier flags for Cmd+Click (toggle) and Shift+Click (range)
    var onSelect: ((CMTime?, NSEvent.ModifierFlags) -> Void)?

    @State private var waveformSamples: [Float]?
    @State private var isDraggingLeftHandle = false
    @State private var isDraggingRightHandle = false
    @State private var leftTrimOffset: CGFloat = 0
    @State private var rightTrimOffset: CGFloat = 0
    @State private var isHovering = false
    @State private var isHoveringHandle = false
    @State private var showingDeleteFileConfirmation = false

    @State private var waveformLoadTask: Task<Void, Never>?

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
        // Break up complex expression to help compiler type-check
        let frameWidth = max(0, clipWidth + (isDraggingRightHandle ? rightTrimOffset : 0) - (isDraggingLeftHandle ? leftTrimOffset : 0))

        return ZStack(alignment: .leading) {
            HStack(spacing: 0) {
                ClipTrimHandle(
                    isLeft: true, clipHeight: clipHeight, pixelsPerSecond: pixelsPerSecond,
                    clip: clip, playheadTime: playheadTime, snapThreshold: snapThreshold,
                    onTrimStart: onTrimStart, onTrimEnd: nil,
                    isDragging: $isDraggingLeftHandle, trimOffset: $leftTrimOffset,
                    onHoverChange: { hovering in isHoveringHandle = hovering }
                )

                // No scaleEffect: it changes layout and pushes the handles out of bounds; brightness and opacity give feedback instead.
                clipContent
                    .brightness((isHovering && !isHoveringHandle) ? 0.1 : 0.0)
                    .animation(.smoothUI, value: isHovering)

                ClipTrimHandle(
                    isLeft: false, clipHeight: clipHeight, pixelsPerSecond: pixelsPerSecond,
                    clip: clip, playheadTime: playheadTime, snapThreshold: snapThreshold,
                    onTrimStart: nil, onTrimEnd: onTrimEnd,
                    isDragging: $isDraggingRightHandle, trimOffset: $rightTrimOffset,
                    onHoverChange: { hovering in isHoveringHandle = hovering }
                )
            }
        }
        .frame(width: frameWidth, height: clipHeight)
        .accessibilityIdentifier(AccessibilityIdentifiers.timelineClip)
        .accessibilityLabel(clip.url.lastPathComponent)
        // Only offset entire clip for left handle drag
        // Right handle stays in place via its own offset
        .offset(x: isDraggingLeftHandle ? leftTrimOffset : 0)
        .background(isSelected ? Color.accentColor : Color.stone.opacity(0.3))
        .cornerRadius(Theme.Dimensions.cornerRadius)
        .shadow(color: .black.opacity(0.3), radius: 2, x: 0, y: 1)
        .overlay(RoundedRectangle(cornerRadius: 6).stroke(isSelected ? Color.accentColor : Color.clear, lineWidth: 2))
        .onHover { hovering in
            // No scaling while hovering a trim handle, so the clip doesn't grow as the user grabs it.
            guard !isHoveringHandle else { return }
            withAnimation(.smoothUI) { isHovering = hovering }
        }
        .modifier(ClipGestureModifier(
            isDraggingLeftHandle: isDraggingLeftHandle,
            isDraggingRightHandle: isDraggingRightHandle,
            clipWidth: clipWidth,
            handleWidth: handleWidth,
            clip: clip,
            onSelect: onSelect
        ))
        .task {
            // Load the waveform only when the view appears, so off-screen clips skip it.
            waveformLoadTask = Task { @MainActor in
                await loadWaveform()
            }
            // Not awaited; the view updates when waveformSamples is set.
        }
        .onDisappear {
            waveformLoadTask?.cancel()
            waveformLoadTask = nil
            Task {
                await ServiceContainer.shared.waveformService.cancelLoad(for: clip)
            }
        }
        .contextMenu {
            ClipContextMenu(
                clip: clip,
                onSplit: onSplit,
                onDelete: onDelete,
                onRemoveSilence: onRemoveSilence,
                onRemoveFillers: onRemoveFillers,
                onGenerateCaptions: onGenerateCaptions,
                onFindGestures: onFindGestures,
                onPrivacyBlur: onPrivacyBlur,
                onRelink: onRelink,
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
            if clip.isMissing {
                ZStack {
                    Rectangle()
                        .fill(Color.red.opacity(0.8))
                        .overlay(
                            Rectangle()
                                .strokeBorder(Color.red, lineWidth: 2)
                        )

                    VStack {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .font(.system(size: 16))
                            .foregroundColor(.white)
                        Text("MEDIA OFFLINE")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundColor(.white)
                    }
                }
            } else {
                ZStack(alignment: .leading) {
                    Rectangle().fill(Color.accentColor.opacity(0.3))
                    thumbnailStrip
                    clipLabel
                }
                .frame(height: clipHeight * 0.55)
                .clipped()

                ZStack(alignment: .bottom) {
                    Rectangle().fill(Color(white: 0.15))
                    waveformDisplay
                    smoothCutOverlay
                    stitchMarkerOverlay
                    durationLabel
                }
                .frame(height: clipHeight * 0.45)
                .clipped()
            }
        }
        .frame(width: max(0, clipWidth - handleWidth * 2 + (isDraggingRightHandle ? rightTrimOffset : 0) - (isDraggingLeftHandle ? leftTrimOffset : 0)), height: clipHeight)
        .offset(x: isDraggingLeftHandle ? -leftTrimOffset : 0)
        .clipped()
        .background(Color.black)
        .cornerRadius(4)
    }

    // MARK: - Components

    private var thumbnailStrip: some View {
        // Handles 10-hour videos: LazyHStack creates only the visible thumbnail cells, and each loads itself.
        let targetThumbWidth: CGFloat = 80
        let thumbCount = max(1, Int(clipWidth / targetThumbWidth))
        let singleThumbWidth = clipWidth / CGFloat(thumbCount)

        // LazyHStack with explicit frame to prevent layout thrashing
        return LazyHStack(spacing: 0) {
            ForEach(0..<thumbCount, id: \.self) { index in
                let fraction = Double(index) / Double(max(1, thumbCount))
                let time = CMTime(seconds: clip.effectiveDuration.seconds * fraction, preferredTimescale: 600)
                let originalTime = clip.originalTime(forEffectiveTime: time)

                TimelineThumbnailCell(
                    clip: clip,
                    time: originalTime,
                    size: CGSize(width: singleThumbWidth * 2, height: 80 * 2) // Request retina quality
                )
                .frame(width: singleThumbWidth, height: clipHeight * 0.55)
                .clipped()
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
            Rectangle().fill(Color.accentColor).frame(width: 1)
                .offset(x: CGFloat(progress) * max(0, clipWidth - handleWidth * 2))
        }
    }

    /// Visualizes the crossfade region used by Smooth Cuts so the timeline is WYSIWYG.
    private var smoothCutOverlay: some View {
        let innerWidth = max(0, clipWidth - handleWidth * 2)
        let overlap = TimeUtils.smoothCutOverlap(clipSpeed: clip.speed, overlapPlayedSeconds: 0.15)
        let overlapWidth = CGFloat(overlap.played.seconds) * pixelsPerSecond

        return Group {
            if clip.useSmoothCutForRemovals, !stitchMarkers.isEmpty, overlapWidth > 0, innerWidth > 0 {
                ForEach(stitchMarkers, id: \.self) { progress in
                    // Center overlay on the cut marker, clamp to the clip bounds.
                    let markerX = CGFloat(progress) * innerWidth
                    let unclampedX = markerX - (overlapWidth / 2)
                    let clampedX = max(0, min(innerWidth - overlapWidth, unclampedX))

                    Rectangle()
                        .fill(Color.accentColor.opacity(0.12))
                        .frame(width: overlapWidth, height: clipHeight * 0.45)
                        .offset(x: clampedX)
                }
            }
        }
    }

    private var durationLabel: some View {
        HStack {
            Spacer()
            Text(formatDuration(clip.effectiveDuration))
                .font(.system(size: 9)).foregroundColor(.white.opacity(0.6)).padding(2)
        }
    }

    // MARK: - Data Loading

    // Thumbnails load lazily per cell; eager loading ran out of memory on large files.

    private func loadWaveform() async {
        guard !Task.isCancelled else { return }

        if let samples = await ServiceContainer.shared.waveformService.waveform(for: clip) {
            guard !Task.isCancelled else { return }
            await MainActor.run { self.waveformSamples = samples }
        }
    }

    private func formatDuration(_ time: CMTime) -> String {
        TimeUtils.formatDuration(time)
    }
}

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
                    .fill(Color.stone.opacity(0.1))
            }
        }
        .clipped()
        .task {
            // Note: ServiceContainer handles internal caching of generated results
            guard image == nil && !isLoading else { return }
            isLoading = true

            // Detached at utility priority so thumbnail loading never blocks the UI.
            let thumb = await Task.detached(priority: .utility) {
                await ServiceContainer.shared.thumbnailService.thumbnail(
                    for: clip,
                    time: time,
                    size: size
                )
            }.value

            await MainActor.run {
                self.image = thumb?.value
                self.isLoading = false
            }
        }
    }
}

// MARK: - Gesture Modifier (to help compiler type-check)

/// Gesture logic lives in its own modifier to help the compiler type-check.
struct ClipGestureModifier: ViewModifier {
    let isDraggingLeftHandle: Bool
    let isDraggingRightHandle: Bool
    let clipWidth: CGFloat
    let handleWidth: CGFloat
    let clip: VideoClip
    let onSelect: ((CMTime?, NSEvent.ModifierFlags) -> Void)?

    func body(content: Content) -> some View {
        content
            // Lower priority than the trim handles' highPriorityGesture; the 5pt minimum avoids accidental triggers during trims.
            .gesture(
                DragGesture(minimumDistance: 5, coordinateSpace: .local)
                    .onEnded { value in
                        guard !isDraggingLeftHandle && !isDraggingRightHandle else { return }

                        let dragDistance = sqrt(pow(value.translation.width, 2) + pow(value.translation.height, 2))
                        guard dragDistance < 10 else { return } // If dragged too far, it's not a click

                        let percent = value.startLocation.x / (clipWidth - handleWidth * 2)
                        let safePercent = max(0, min(1.0, percent))
                        let timeOffset = clip.effectiveDuration.seconds * Double(safePercent)
                        let seekTime = CMTimeAdd(clip.startTime, CMTime(seconds: timeOffset, preferredTimescale: 600))

                        let modifiers = NSEvent.modifierFlags
                        onSelect?(seekTime, modifiers)
                    }
            )
    }
}
