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

    private let timelineHeight: CGFloat = AppConstants.timelineHeight

    var body: some View {
        HStack(spacing: 0) {
            // FIXED LEFT COLUMN: Track Headers
            // LEFT COLUMN: Track Headers REMOVED per user request
            // VStack(spacing: 0) { ... } .frame(width: 100)
            // Functionality (Mute/Lock) may need to be moved elsewhere or triggered via context menu in future.

            // SCROLLING RIGHT SECTION: Ruler + Track Content
            ZStack(alignment: .topLeading) {
                VStack(alignment: .leading, spacing: 0) {
                    TimeRulerView(
                        duration: max(60, appState.projectState.currentProject?.timeline.duration.seconds ?? 60),
                        pixelsPerSecond: pixelsPerSecond
                    )
                    .frame(height: 30)

                    VStack(spacing: 8) {
                        if let project = appState.projectState.currentProject {
                            ForEach(project.timeline.tracks) { track in
                                trackRow(for: track)
                            }
                        }
                    }
                }

                playheadOverlay
            }
            .coordinateSpace(name: "TimelineContent")
        }
    }

    private func calculateWidth() -> CGFloat {
        let duration = max(60, appState.projectState.currentProject?.timeline.duration.seconds ?? 60)
        return duration * pixelsPerSecond
    }

    private func trackRow(for track: Track) -> some View {
        // OPTIMIZATION: Use LazyHStack with calculated spacers instead of ZStack+Offset
        // This prevents eager loading of all 500+ clips in a complex project.
        // We assume clips are sorted by startTime.
        let sortedClips = track.clips.sorted { $0.startTime < $1.startTime }
        
        return LazyHStack(alignment: .top, spacing: 0) {
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
                        Task {
                            _ = try? await appState.projectState.generateCaptions(for: clip)
                        }
                    },
                    onFindHighlights: {
                        Task {
                            await appState.projectState.findHighlights(in: clip)
                        }
                    },
                    onDeleteFile: {
                        appState.projectState.deleteClipFile(clip)
                    },
                    onSetTransition: { transitionType in
                        appState.projectState.setClipTransition(clipId: clip.id, transitionType: transitionType)
                    },
                    onSelect: { seekTime in
                        if !appState.selectedClipIds.contains(clip.id) {
                            appState.selectedClipIds.removeAll()
                            appState.selectedClipIds.insert(clip.id)
                            selectedClip = clip
                        }
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
        .frame(height: timelineHeight)
        .background(Color.secondary.opacity(0.1))
    }

    private var playheadOverlay: some View {
        ZStack(alignment: .top) {
            Rectangle()
                .fill(Color.red)
                .frame(width: 2)

            Circle()
                .fill(Color.red)
                .frame(width: 10, height: 10)
                .offset(y: 4)
                .scaleEffect(isScrubbing ? 1.2 : 1.0)
                .animation(.spring(response: 0.2, dampingFraction: 0.6), value: isScrubbing)
        }
        .contentShape(Rectangle())
        .highPriorityGesture(
            DragGesture(coordinateSpace: .named("TimelineContent"))
                .onChanged { value in
                    if !isScrubbing {
                        isScrubbing = true
                        ServiceContainer.shared.hapticsManager.selection()
                    }
                    let time = max(0, value.location.x / pixelsPerSecond)
                    scrubTime = CMTime(seconds: Double(time), preferredTimescale: 600)
                    appState.playbackState.seek(to: scrubTime)
                }
                .onEnded { _ in
                    isScrubbing = false
                    ServiceContainer.shared.hapticsManager.selection()
                }
        )
        .offset(x: (isScrubbing ? scrubTime : appState.playbackState.currentTime).seconds * pixelsPerSecond)
        .animation(isScrubbing ? nil : .linear(duration: 0.1), value: appState.playbackState.currentTime)
        .padding(.top, 4)
    }
}
