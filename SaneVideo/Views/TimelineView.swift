//
//  TimelineView.swift
//  SaneVideo
//
//  Main timeline orchestrator. Sub-views extracted to:
//  - TimelineControls.swift (toolbar, MagicFix)
//  - TimelineTracksView.swift (tracks, playhead, drop delegate)
//  - TrackHeaderView.swift (headers, add track button)
//

import AVFoundation
import SwiftUI

public struct SaneTimelineView: View {
    @Environment(AppState.self) var appState
    @Binding var selectedClip: VideoClip?
    @Binding var selectedClipIds: Set<UUID>

    @State private var zoomLevel: CGFloat = 1.5
    @State private var isScrubbing = false
    @State private var scrubTime: CMTime = .zero
    @State private var clipToDelete: VideoClip?
    @State private var showDeleteConfirmation = false
    @State private var showLogs = false
    @State private var draggingClip: VideoClip?

    private var pixelsPerSecond: CGFloat {
        AppConstants.pixelsPerSecond * zoomLevel
    }

    private let timelineHeight: CGFloat = AppConstants.timelineHeight

    public var body: some View {
        @Bindable var projectState = appState.projectState
        
        VStack(spacing: 0) {
            TimelineControls(
                zoomLevel: $zoomLevel,
                showLogs: $showLogs,
                magicOptions: $projectState.magicFixOptions,
                selectedClip: selectedClip,
                playbackState: appState.playbackState,
                projectState: appState.projectState,
                onSplit: splitSelectedClip
            )

            ScrollView(.horizontal, showsIndicators: true) {
                TimelineTracksView(
                    zoomLevel: zoomLevel,
                    isScrubbing: $isScrubbing,
                    scrubTime: $scrubTime,
                    clipToDelete: $clipToDelete,
                    showDeleteConfirmation: $showDeleteConfirmation,
                    selectedClip: $selectedClip,
                    draggingClip: $draggingClip,
                    selectedClipIds: $selectedClipIds,
                    pixelsPerSecond: pixelsPerSecond
                )
            }
            .frame(minHeight: 150, maxHeight: .infinity)
        }
        .alert(String(localized: "timeline.alert.delete.title", defaultValue: "Delete Clip"), isPresented: $showDeleteConfirmation, presenting: clipToDelete) { clip in
            Button(String(localized: "timeline.alert.delete.remove", defaultValue: "Remove from Project only"), role: .none) {
                appState.projectState.deleteClip(clip)
                clipToDelete = nil
            }
            .accessibilityIdentifier("timeline.alert.delete.remove")

            Button(String(localized: "timeline.alert.delete.disk", defaultValue: "Delete from Disk"), role: .destructive) {
                appState.projectState.deleteClipFile(clip)
                clipToDelete = nil
            }
            .accessibilityIdentifier("timeline.alert.delete.disk")

            Button(String(localized: "common.cancel", defaultValue: "Cancel"), role: .cancel) {
                clipToDelete = nil
            }
            .accessibilityIdentifier("timeline.alert.delete.cancel")
        } message: { clip in
            Text(String(localized: "timeline.alert.delete.message", 
                        defaultValue: "Do you want to remove the clip from the project, or permanently delete the file from your disk?") + ": '\(clip.url.lastPathComponent)'.")
        }
        .sheet(isPresented: $showLogs) {
            LogView()
        }
        .onAppear {
            if selectedClip == nil {
                autoSelectFirstClip()
            }
            fitToView()
        }
        .onChange(of: appState.projectState.currentProject?.timeline.tracks) {
            if selectedClip == nil {
                autoSelectFirstClip()
            }
            fitToView()
        }
        .overlay {
            Group {
                // Zoom In: ⌘+
                Button("") {
                    withAnimation {
                        zoomLevel = min(5.0, zoomLevel + 0.5)
                    }
                }
                .keyboardShortcut("=", modifiers: [.command])
                .opacity(0)
                .allowsHitTesting(false)
                .accessibilityIdentifier("timeline.shortcut.zoom_in")

                // Zoom Out: ⌘-
                Button("") {
                    withAnimation {
                        zoomLevel = max(0.1, zoomLevel - 0.5)
                    }
                }
                .keyboardShortcut("-", modifiers: [.command])
                .opacity(0)
                .allowsHitTesting(false)
                .accessibilityIdentifier("timeline.shortcut.zoom_out")

                // Toggle Snapping: N
                Button("") {
                    @AppStorage("snapEnabled") var snapEnabled = true
                    snapEnabled.toggle()
                }
                .keyboardShortcut("n", modifiers: [])
                .opacity(0)
                .allowsHitTesting(false)
                .accessibilityIdentifier("timeline.shortcut.snap")

                // Toggle Magnetic: M
                Button("") {
                    @AppStorage("magneticTimeline") var magneticTimeline = true
                    magneticTimeline.toggle()
                }
                .keyboardShortcut("m", modifiers: [])
                .opacity(0)
                .allowsHitTesting(false)
                .accessibilityIdentifier("timeline.shortcut.magnetic")

                // Fit to View: ⌘0
                Button("") {
                    withAnimation {
                        fitToView()
                    }
                }
                .keyboardShortcut("0", modifiers: [.command])
                .opacity(0)
                .allowsHitTesting(false)
                .accessibilityIdentifier("timeline.shortcut.fit")
            }
        }
    }

    private func fitToView() {
        guard let project = appState.projectState.currentProject else { return }
        let duration = project.timeline.duration.seconds
        guard duration > 0 else { return }

        let estimatedVisibleWidth: CGFloat = 700
        let basePPS = AppConstants.pixelsPerSecond
        let optimalZoom = estimatedVisibleWidth / (duration * basePPS)

        zoomLevel = max(0.1, min(5.0, optimalZoom))
    }

    private func autoSelectFirstClip() {
        if let project = appState.projectState.currentProject,
           let firstTrack = project.timeline.tracks.first(where: { !$0.clips.isEmpty }),
           let firstClip = firstTrack.clips.first {
            selectedClip = firstClip
        }
    }

    private func splitSelectedClip() {
        guard let clip = selectedClip else { return }
        let splitTime = appState.playbackState.currentTime
        appState.projectState.splitClip(clip, atTimelineTime: splitTime)
    }
}
