//
//  TimelineTracksView.swift
//  SaneVideo
//
//  Extracted from TimelineView.swift
//  Contains track rendering, playhead overlay, and drop delegate
//

import AppKit
import AVFoundation
import SwiftUI
import UniformTypeIdentifiers

// MARK: - Timeline Tracks View

struct TimelineTracksView: View {
    let zoomLevel: CGFloat
    @Binding var isScrubbing: Bool
    @Binding var scrubTime: CMTime
    @Binding var clipToDelete: VideoClip?
    @Binding var showDeleteConfirmation: Bool
    @Binding var selectedClip: VideoClip?
    @Binding var draggingClip: VideoClip?
    @Binding var selectedClipIds: Set<UUID>
    let pixelsPerSecond: CGFloat

    @Environment(AppState.self) var appState

    // SWIFT 6 FIX: Track async tasks to prevent fire-and-forget pile-up
    @State private var captionTask: Task<Void, Never>?
    @State private var highlightTask: Task<Void, Never>?

    private let timelineHeight: CGFloat = AppConstants.timelineHeight

    // CRITICAL: Compute filtered tracks ONCE to ensure headers and rows stay in sync
    private var tracksWithClips: [Track] {
        appState.projectState.currentProject?.timeline.tracks.filter { !$0.clips.isEmpty } ?? []
    }

    var body: some View {
        // Add leading padding so trim handles aren't blocked by fixed header column
        let leadingPadding: CGFloat = 10

        ZStack(alignment: .topLeading) {
            VStack(alignment: .leading, spacing: 0) {
                // Ruler - matches left column spacer height (40px)
                HStack(spacing: 0) {
                    Rectangle().fill(Color.clear).frame(width: leadingPadding)
                    TimeRulerView(
                        duration: max(60, appState.projectState.currentProject?.timeline.duration.seconds ?? 60),
                        pixelsPerSecond: pixelsPerSecond,
                        onSeek: { time in
                            let seekTime = CMTime(seconds: time, preferredTimescale: 600)
                            appState.playbackState.seek(to: seekTime)
                        }
                    )
                }
                .frame(height: 40)

                // Track rows - MUST match headers VStack spacing exactly (8px)
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(tracksWithClips) { track in
                        trackRow(for: track, leadingPadding: leadingPadding)
                    }
                }
            }

            playheadOverlay
        }
        .coordinateSpace(name: "TimelineContent")
        .clipped()
    }

    private func calculateWidth() -> CGFloat {
        let duration = max(60, appState.projectState.currentProject?.timeline.duration.seconds ?? 60)
        return duration * pixelsPerSecond
    }

    private func trackRow(for track: Track, leadingPadding: CGFloat) -> some View {
        // OPTIMIZATION: Use LazyHStack with calculated spacers instead of ZStack+Offset
        // This prevents eager loading of all 500+ clips in a complex project.
        // We assume clips are sorted by startTime.
        let sortedClips = track.clips.sorted { $0.startTime < $1.startTime }

        return LazyHStack(alignment: .top, spacing: 0) {
            // Add leading padding so trim handles aren't blocked by fixed header
            Rectangle().fill(Color.clear).frame(width: leadingPadding)

            ForEach(Array(sortedClips.enumerated()), id: \.element.id) { index, clip in
                // Calculate spacer from previous clip end (or 0)
                let previousEnd = index == 0 ? CMTime.zero : sortedClips[index - 1].startTime + sortedClips[index - 1].effectiveDuration
                let gap = max(0, clip.startTime.seconds - previousEnd.seconds)
                let gapWidth = gap * pixelsPerSecond

                if gapWidth > 0 {
                    Rectangle().fill(Color.clear).frame(width: gapWidth)
                }

                let isClipSelected = appState.selectedClipIds.contains(clip.id) || selectedClip?.id == clip.id

                TimelineClipView(
                    clip: clip,
                    pixelsPerSecond: pixelsPerSecond,
                    isSelected: isClipSelected,
                    playheadTime: appState.playbackState.currentTime,
                    onTrimStart: { newTime in
                        appState.projectState.updateClipTrim(clipId: clip.id, trimStart: newTime, trimEnd: nil)
                    },
                    onTrimEnd: { newTime in
                        appState.projectState.updateClipTrim(clipId: clip.id, trimStart: nil, trimEnd: newTime)
                    },
                    onDelete: {
                        clipToDelete = clip
                        showDeleteConfirmation = true
                    },
                    onSplit: {
                        appState.projectState.splitClip(clip, atTimelineTime: appState.playbackState.currentTime)
                    },
                    onRemoveSilence: {
                        appState.projectState.removeSilence(from: clip)
                    },
                    onRemoveFillers: {
                        appState.projectState.removeFillerWords(from: clip)
                    },
                    onGenerateCaptions: {
                        // SWIFT 6 FIX: Cancel previous task to prevent pile-up
                        captionTask?.cancel()
                        captionTask = Task {
                            _ = try? await appState.projectState.generateCaptions(for: clip)
                        }
                    },
                    onFindHighlights: {
                        // SWIFT 6 FIX: Cancel previous task to prevent pile-up
                        highlightTask?.cancel()
                        highlightTask = Task {
                            await appState.projectState.findHighlights(in: clip)
                        }
                    },
                    onDeleteFile: {
                        // CRITICAL FIX: Clear selection BEFORE deletion to prevent stale reference
                        if selectedClip?.id == clip.id {
                            selectedClip = nil
                        }
                        appState.selectedClipIds.remove(clip.id)
                        appState.projectState.deleteClipFile(clip)
                    },
                    onRelink: {
                        let panel = NSOpenPanel()
                        panel.title = String(localized: "dialog.relink.title", defaultValue: "Relink Clip")
                        panel.message = String(localized: "dialog.relink.message", defaultValue: "Select the new location for: ") + clip.url.lastPathComponent
                        panel.allowedContentTypes = [.video, .quickTimeMovie, .mpeg4Movie]
                        panel.allowsMultipleSelection = false
                        panel.canChooseDirectories = false
                        panel.canChooseFiles = true

                        if panel.runModal() == .OK, let url = panel.url {
                            appState.projectState.relinkClip(clip, to: url)
                        }
                    },
                    onSetTransition: { transitionType in
                        appState.projectState.setClipTransition(clipId: clip.id, transitionType: transitionType)
                    },
                    onSelect: { seekTime, modifiers in
                        handleClipSelection(clip: clip, modifiers: modifiers, sortedClips: sortedClips)
                        if let time = seekTime {
                            appState.playbackState.seek(to: time)
                        }
                    }
                )
            }

            // Trailing spacer to fill timeline duration if needed
            if let lastClip = sortedClips.last {
                let duration = max(60, appState.projectState.currentProject?.timeline.duration.seconds ?? 60)
                let lastEndTime = lastClip.startTime + lastClip.effectiveDuration
                let remaining = max(0, duration - lastEndTime.seconds)
                if remaining > 0 {
                    Rectangle().fill(Color.clear).frame(width: remaining * pixelsPerSecond)
                }
            } else {
                // Empty track spacer
               let duration = max(60, appState.projectState.currentProject?.timeline.duration.seconds ?? 60)
               Rectangle().fill(Color.clear).frame(width: duration * pixelsPerSecond)
            }
        }
        // OPTIMIZATION: Enable scroll target layout for better LazyHStack performance
        // and programmatic scroll position targeting (e.g., seek-to-playhead).
        .scrollTargetLayout()
        .frame(height: timelineHeight)
        .background(Color(nsColor: .controlBackgroundColor))
    }

    private var playheadOverlay: some View {
        ZStack(alignment: .top) {
            // Glow effect
            Rectangle()
                .fill(Color.red.opacity(0.3))
                .frame(width: 4)
                .blur(radius: 2)

            // Main line
            Rectangle()
                .fill(Color.red)
                .frame(width: 2)

            // Glowing circle
            Circle()
                .fill(
                    RadialGradient(
                        colors: [Color.red.opacity(0.8), Color.red.opacity(0.3)],
                        center: .center,
                        startRadius: 2,
                        endRadius: 8
                    )
                )
                .frame(width: 16, height: 16)
                .blur(radius: 2)
                .offset(y: 2)

            // Sharp circle
            Circle()
                .fill(Color.red)
                .frame(width: 10, height: 10)
                .offset(y: 4)
                .scaleEffect(isScrubbing ? 1.3 : 1.0)
                .shadow(color: .red.opacity(0.6), radius: isScrubbing ? 8 : 4)
        }
        .contentShape(Rectangle())
        // CRITICAL FIX: Only activate scrubbing if drag starts near playhead AND in ruler area
        // This prevents interference with clip selection and trim handles
        .highPriorityGesture(
            DragGesture(minimumDistance: 0, coordinateSpace: .named("TimelineContent"))
                .onChanged { value in
                    // CRITICAL FIX: Only allow scrubbing in ruler area (top 30px) to avoid clip/trim handle conflicts
                    // Clips are below the ruler, so we should never scrub when dragging on clips
                    guard value.startLocation.y <= 30 else { return }

                    // Account for leading padding when calculating playhead position
                    let leadingPadding: CGFloat = 10
                    let playheadX = (isScrubbing ? scrubTime : appState.playbackState.currentTime).seconds * pixelsPerSecond + leadingPadding
                    let dragStartX = value.startLocation.x
                    let distanceFromPlayhead = abs(dragStartX - playheadX)

                    guard isScrubbing || distanceFromPlayhead < 20 else { return }

                    if !isScrubbing {
                        withAnimation(.spring(response: 0.2, dampingFraction: 0.6)) {
                            isScrubbing = true
                        }
                        ServiceContainer.shared.hapticsManager.selection()
                    }
                    // Account for leading padding when calculating time from drag location
                    let adjustedX = max(0, value.location.x - leadingPadding)
                    let time = max(0, adjustedX / pixelsPerSecond)
                    scrubTime = CMTime(seconds: Double(time), preferredTimescale: 600)
                    appState.playbackState.seek(to: scrubTime)
                }
                .onEnded { _ in
                    withAnimation(.spring(response: 0.2, dampingFraction: 0.6)) {
                        isScrubbing = false
                    }
                    ServiceContainer.shared.hapticsManager.selection()
                }
        )
        // Account for leading padding so playhead aligns with content
        .offset(x: (isScrubbing ? scrubTime : appState.playbackState.currentTime).seconds * pixelsPerSecond + 10)
        .animation(isScrubbing ? nil : .linear(duration: 0.1), value: appState.playbackState.currentTime)
        .padding(.top, 4)
    }

    // MARK: - Selection Handling

    /// Handle clip selection with modifier keys (Cmd+Click = toggle, Shift+Click = range)
    private func handleClipSelection(clip: VideoClip, modifiers: NSEvent.ModifierFlags, sortedClips: [VideoClip]) {
        if modifiers.contains(.command) {
            // Cmd+Click: Toggle selection (add/remove from multi-select)
            if appState.selectedClipIds.contains(clip.id) {
                appState.selectedClipIds.remove(clip.id)
                // If we removed the primary selection, pick another or nil
                if selectedClip?.id == clip.id {
                    selectedClip = appState.selectedClipIds.isEmpty ? nil :
                        sortedClips.first(where: { appState.selectedClipIds.contains($0.id) })
                }
            } else {
                appState.selectedClipIds.insert(clip.id)
                selectedClip = clip
            }
        } else if modifiers.contains(.shift) {
            // Shift+Click: Range selection (from primary selection to clicked clip)
            guard let primaryClip = selectedClip,
                  let primaryIndex = sortedClips.firstIndex(where: { $0.id == primaryClip.id }),
                  let clickedIndex = sortedClips.firstIndex(where: { $0.id == clip.id }) else {
                // No primary selection - just select the clicked clip
                selectedClip = clip
                selectedClipIds = [clip.id]
                return
            }

            // Select all clips between primary and clicked (inclusive)
            let startIndex = min(primaryIndex, clickedIndex)
            let endIndex = max(primaryIndex, clickedIndex)
            for i in startIndex...endIndex {
                appState.selectedClipIds.insert(sortedClips[i].id)
            }
            // Keep primary selection, update selectedClipIds binding
            selectedClipIds = appState.selectedClipIds
        } else {
            // Normal click: Replace selection
            if !appState.selectedClipIds.contains(clip.id) {
                appState.selectedClipIds.removeAll()
                appState.selectedClipIds.insert(clip.id)
                selectedClip = clip
            }
        }
    }
}
