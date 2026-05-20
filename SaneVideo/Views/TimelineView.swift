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
    @State private var visibleTimelineWidth: CGFloat = 700
    @State private var fittedProjectIds: Set<UUID> = []
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

            if projectState.currentProject?.timeline.tracks.flatMap({ $0.clips }).isEmpty ?? true {
                TimelineEmptyStateView()
                    .frame(minHeight: 150, maxHeight: .infinity)
            } else {
                // CRITICAL FIX: Left column fixed, right section scrolls
                // This ensures lock/mute icons stay aligned with tracks
                HStack(alignment: .top, spacing: 0) {
                    // Fixed left column (headers) - extracted from TimelineTracksView
                    TimelineHeadersView(
                        zoomLevel: zoomLevel,
                        pixelsPerSecond: pixelsPerSecond
                    )
                    .frame(width: 100)
                    .background(SaneVideoEditorPanelBackground())
                    .fixedSize(horizontal: true, vertical: false)

                    // Scrollable right section (ruler + tracks)
                    GeometryReader { geometry in
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
                            // CRITICAL FIX: Removed .padding(.leading, 20) - padding is handled internally
                            // by spacers in ruler and trackRow to ensure proper alignment
                        }
                        .onAppear {
                            updateVisibleTimelineWidth(geometry.size.width)
                        }
                        .onChange(of: geometry.size.width) { _, newWidth in
                            updateVisibleTimelineWidth(newWidth)
                        }
                    }
                    .accessibilityIdentifier("TimelineScroll")
                    .frame(maxWidth: .infinity)
                    .background(SaneVideoEditorPanelBackground())
                }
                .background(SaneVideoEditorPanelBackground())
                .frame(maxWidth: .infinity, alignment: .topLeading)
                .frame(minHeight: 150, maxHeight: .infinity)
            }
        }
        .alert(String(localized: "timeline.alert.delete.title", defaultValue: "Delete Clip"), isPresented: $showDeleteConfirmation, presenting: clipToDelete) { clip in
            Button(String(localized: "timeline.alert.delete.remove", defaultValue: "Remove from Project only"), role: .none) {
                // CRITICAL FIX: Clear selection BEFORE deletion to prevent stale reference
                if selectedClip?.id == clip.id {
                    selectedClip = nil
                }
                appState.selectedClipIds.remove(clip.id)
                appState.projectState.deleteClip(clip)
                clipToDelete = nil
            }
            .accessibilityIdentifier("timeline.alert.delete.remove")

            Button(String(localized: "timeline.alert.delete.disk", defaultValue: "Delete from Disk"), role: .destructive) {
                // CRITICAL FIX: Clear selection BEFORE deletion to prevent stale reference
                if selectedClip?.id == clip.id {
                    selectedClip = nil
                }
                appState.selectedClipIds.remove(clip.id)
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
            ensureSelectionForCurrentProject()

            // Restore Zoom Level
            if let project = appState.projectState.currentProject, project.zoomLevel > 0 {
                self.zoomLevel = project.zoomLevel
            } else {
                fitToView()
            }
            fitNewProjectToViewIfNeeded()
        }
        .onChange(of: zoomLevel) { _, newZoom in
            appState.projectState.updateZoomLevel(newZoom)
        }
        .onChange(of: appState.projectState.currentProject?.timeline.tracks) {
            ensureSelectionForCurrentProject()
            fitNewProjectToViewIfNeeded()
        }
        .onReceive(NotificationCenter.default.publisher(for: NSNotification.Name("FitTimelineToWindow"))) { _ in
            withAnimation {
                fitToView()
            }
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
                        zoomLevel = TimelineZoomCalculator.clamp(zoomLevel - 0.5)
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

                // Split Clip: ⌘B
                Button("") {
                    splitSelectedClip()
                }
                .keyboardShortcut("b", modifiers: [.command])
                .opacity(0)
                .allowsHitTesting(false)
                .accessibilityIdentifier("timeline.shortcut.split")

                // Delete Clip: Delete / Backspace
                Button("") {
                    if let clip = selectedClip {
                        clipToDelete = clip
                        showDeleteConfirmation = true
                    }
                }
                .keyboardShortcut(.delete, modifiers: [])
                .opacity(0)
                .allowsHitTesting(false)
                .accessibilityIdentifier("timeline.shortcut.delete")
            }
        }
    }

    private func fitToView() {
        guard let project = appState.projectState.currentProject else { return }
        let duration = project.timeline.duration.seconds
        guard duration > 0 else { return }

        zoomLevel = TimelineZoomCalculator.fitZoom(
            duration: duration,
            visibleWidth: visibleTimelineWidth
        )
    }

    private func ensureSelectionForCurrentProject() {
        guard let project = appState.projectState.currentProject else { return }
        if let selectedClip, project.timeline.tracks.flatMap(\.clips).contains(where: { $0.id == selectedClip.id }) {
            return
        }

        autoSelectFirstClip(in: project)
    }

    private func autoSelectFirstClip(in project: VideoProject) {
        if let firstTrack = project.timeline.tracks.first(where: { !$0.clips.isEmpty }),
           let firstClip = firstTrack.clips.first {
            selectedClip = firstClip
            selectedClipIds = [firstClip.id]
            appState.selectedClipIds = [firstClip.id]
        }
    }

    private func updateVisibleTimelineWidth(_ width: CGFloat) {
        guard width > 0 else { return }
        visibleTimelineWidth = width
        fitNewProjectToViewIfNeeded()
    }

    private func fitNewProjectToViewIfNeeded() {
        guard let project = appState.projectState.currentProject else { return }
        guard project.timeline.duration.seconds > 0 else { return }
        guard !fittedProjectIds.contains(project.id) else { return }

        fittedProjectIds.insert(project.id)
        fitToView()
    }

    private func splitSelectedClip() {
        guard let clip = selectedClip else { return }
        let splitTime = appState.playbackState.currentTime
        appState.projectState.splitClip(clip, atTimelineTime: splitTime)
    }
}

enum TimelineZoomCalculator {
    static let minimumZoom: CGFloat = 0.02
    static let maximumZoom: CGFloat = 5.0

    static func clamp(_ zoom: CGFloat) -> CGFloat {
        max(minimumZoom, min(maximumZoom, zoom))
    }

    static func fitZoom(
        duration: TimeInterval,
        visibleWidth: CGFloat,
        basePixelsPerSecond: CGFloat = AppConstants.pixelsPerSecond
    ) -> CGFloat {
        guard duration > 0, visibleWidth > 0, basePixelsPerSecond > 0 else {
            return 1.0
        }

        let renderedDuration = max(60, duration)
        let usableWidth = max(120, visibleWidth - 24)
        return clamp(usableWidth / (CGFloat(renderedDuration) * basePixelsPerSecond))
    }
}
