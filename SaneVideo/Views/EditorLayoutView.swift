//
//  EditorLayoutView.swift
//  SaneVideo
//
//  Created by SaneVideo Refactor
//

import AVFoundation
import CoreMedia
import SwiftUI

// Import new modifiers
// AnimationModifiers

// MARK: - Video Display Modes
enum VideoDisplayMode: String, CaseIterable {
    case fit      // Fit entire video (may have letterboxing)
    case fill     // Fill container (may crop edges)
    case actual   // Actual size (1:1 pixels, scrollable if larger)

    var label: String {
        switch self {
        case .fit: return "Fit"
        case .fill: return "Fill"
        case .actual: return "Actual Size"
        }
    }

    var icon: String {
        switch self {
        case .fit: return "rectangle.arrowtriangle.2.inward"
        case .fill: return "rectangle.arrowtriangle.2.outward"
        case .actual: return "1.square"
        }
    }
}

struct EditorLayoutView: View {
    @Environment(AppState.self) var appState
    @Binding var selectedClip: VideoClip?
    @Binding var selectedClipIds: Set<UUID> // Multi-select support

    // Collapsible panel states
    @State private var isSidebarCollapsed = false
    @State private var isInspectorCollapsed = false
    @State private var lastLoadedProjectId: UUID? // For playhead restoration

    // Video display mode - persisted per user preference
    @AppStorage("editor.videoDisplayMode") private var videoDisplayMode: VideoDisplayMode = .fit

    // Layout constants
    private let sidebarExpandedWidth: CGFloat = 260
    private let inspectorExpandedWidth: CGFloat = 320
    private let collapsedWidth: CGFloat = 20  // Collapsed width for sidebar toggle button

    var body: some View {
        VStack(spacing: 0) {

            Divider()

            // MAIN LAYOUT: HStack with explicit sizing (replaces HSplitView for better collapse behavior)
            GeometryReader { _ in
                HStack(spacing: 0) {
                    // LEFT: Sidebar (Collapsible)
                    sidebarPane
                        .frame(width: isSidebarCollapsed ? collapsedWidth : sidebarExpandedWidth)

                    // CENTER: Stage (Player + Timeline) - fills remaining space
                    centerPane
                        .frame(maxWidth: .infinity, maxHeight: .infinity)

                    // RIGHT: Inspector (Collapsible)
                    inspectorPane
                        .frame(width: isInspectorCollapsed ? collapsedWidth : inspectorExpandedWidth)
                }
            }
            .animation(.easeInOut(duration: 0.25), value: isSidebarCollapsed)
            .animation(.easeInOut(duration: 0.25), value: isInspectorCollapsed)
        }
        .onAppear {
            if let project = appState.projectState.currentProject, lastLoadedProjectId != project.id {
                // Restore state on first appear
                lastLoadedProjectId = project.id
                if project.currentTime > 0 {
                    appState.playbackState.seek(to: CMTime(seconds: project.currentTime, preferredTimescale: 600))
                    AppLogger.general.info("Restored playhead to \(project.currentTime)")
                }
            }
        }
        .onChange(of: appState.projectState.currentProject) { _, new in
            if let newProfile = new, newProfile.id != lastLoadedProjectId {
                lastLoadedProjectId = newProfile.id
                // Restore state when switching projects
                if newProfile.currentTime > 0 {
                    appState.playbackState.seek(to: CMTime(seconds: newProfile.currentTime, preferredTimescale: 600))
                    AppLogger.general.info("Restored playhead to \(newProfile.currentTime)")
                }
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: NSNotification.Name("TriggerMagicFix"))) { _ in
            withAnimation {
                isInspectorCollapsed = false
            }
            // Trigger Magic Fix for selected clip
            if let clip = selectedClip {
                Task {
                    await appState.projectState.performMagicFix(for: clip, options: appState.projectState.magicFixOptions)
                }
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: NSNotification.Name("TriggerMagicFixAll"))) { _ in
            // Batch Magic Fix for all clips (parallelized via BatchCoordinator)
            Task {
                _ = await appState.projectState.performMagicFixAll(options: appState.projectState.magicFixOptions)
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: NSNotification.Name("GenerateAllCaptions"))) { _ in
            // Batch generate captions for all clips (parallelized via BatchCoordinator)
            Task {
                _ = await appState.projectState.generateCaptionsAll()
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: NSNotification.Name("CleanAllAudio"))) { _ in
            // Clean all audio (remove silence/fillers)
            Task {
                await appState.projectState.cleanProjectAudio()
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: NSNotification.Name("ToggleSidebar"))) { _ in
            withAnimation { isSidebarCollapsed.toggle() }
        }
        .onReceive(NotificationCenter.default.publisher(for: NSNotification.Name("ToggleInspector"))) { _ in
            withAnimation { isInspectorCollapsed.toggle() }
        }
        // CONSISTENCY: Use controlBackgroundColor for main editor area
        .background(Color(nsColor: .controlBackgroundColor))
        .liquidGlass(radius: 0) // Full screen edge lighting logic if needed, or 0 for seamless base

        // MARK: - Keyboard Shortcuts (J/K/L/Space)

        .overlay {
            // Hidden buttons for keyboard shortcuts
            Group {
                // Space = Play/Pause toggle
                Button("") {
                    appState.playbackState.togglePlayPause()
                }
                .keyboardShortcut(.space, modifiers: [])
                .accessibilityIdentifier("shortcut.play_pause")

                // K = Pause (standard video editing)
                Button("") {
                    appState.playbackState.pause()
                }
                .keyboardShortcut("k", modifiers: [])
                .accessibilityIdentifier("shortcut.pause")

                // J = Play backward / slow down
                Button("") {
                    handleJKey()
                }
                .keyboardShortcut("j", modifiers: [])
                .accessibilityIdentifier("shortcut.shuttle_backward")

                // L = Play forward / speed up
                Button("") {
                    handleLKey()
                }
                .keyboardShortcut("l", modifiers: [])
                .accessibilityIdentifier("shortcut.shuttle_forward")

                // Left Arrow = Step backward 1 frame
                Button("") {
                    appState.playbackState.stepBackward()
                }
                .keyboardShortcut(.leftArrow, modifiers: [])
                .accessibilityIdentifier("shortcut.step_backward")

                // Right Arrow = Step forward 1 frame
                Button("") {
                    appState.playbackState.stepForward()
                }
                .keyboardShortcut(.rightArrow, modifiers: [])
                .accessibilityIdentifier("shortcut.step_forward")

                // Command + B = Split Clip
                Button("") {
                    if let clip = selectedClip {
                        appState.projectState.splitClip(clip, atTimelineTime: appState.playbackState.currentTime)
                    }
                }
                .keyboardShortcut("b", modifiers: [.command])
                .accessibilityIdentifier("shortcut.split_clip")

                // Backspace/Delete = Delete Clip
                Button("") {
                    if let clip = selectedClip {
                        appState.projectState.deleteClip(clip)
                        selectedClip = nil
                    }
                }
                .keyboardShortcut(.delete, modifiers: [])
                .accessibilityIdentifier("shortcut.delete_clip")
            }
            .opacity(0)
            .allowsHitTesting(false)
        }
    }

    // MARK: - Layout Panes

    @ViewBuilder
    private var sidebarPane: some View {
        ZStack(alignment: .trailing) {
            if !isSidebarCollapsed {
                SidebarView(selectedClip: $selectedClip)
                    .transition(.opacity)
            }

            CollapseButton(isCollapsed: $isSidebarCollapsed, edge: .leading)
                .accessibilityIdentifier(AccessibilityIdentifiers.sidebarToggle)
                .offset(x: 8)
                .zIndex(1)
        }
        .background(Color(nsColor: .controlBackgroundColor))
    }

    @ViewBuilder
    private var centerPane: some View {
        VStack(spacing: 0) {
            // PLAYER STAGE - Video fills available space using GeometryReader
            GeometryReader { geometry in
                ZStack {
                    Color(nsColor: .windowBackgroundColor)

                    if let player = appState.playbackState.player {
                        // Video fills the stage area - pass explicit size for proper layout
                        videoPlayerView(player: player, availableSize: geometry.size)
                    } else {
                        // EMPTY STATE
                        magicFixEmptyState
                    }
                }
            }

            // NOTE: PlayerControlBar removed - controls moved to unified TimelineControls toolbar

            // TIMELINE - includes unified toolbar with playback controls
            SaneTimelineView(
                selectedClip: $selectedClip,
                selectedClipIds: $selectedClipIds
            )
            .frame(height: 240) // Increased to accommodate unified toolbar (42px) + ruler (40px) + tracks
        }
    }

    @ViewBuilder
    private var inspectorPane: some View {
        ZStack(alignment: .leading) {
            CollapseButton(isCollapsed: $isInspectorCollapsed, edge: .trailing)
                .accessibilityIdentifier(AccessibilityIdentifiers.inspectorToggle)
                .offset(x: -8)
                .zIndex(1)

            if !isInspectorCollapsed {
                StylesInspectorView(selectedClip: $selectedClip)
                    .transition(.opacity)
            }
        }
        // CONSISTENCY: Inspector pane uses same controlBackgroundColor
        .background(Color(nsColor: .controlBackgroundColor))
    }

    // MARK: - Shuttle Playback Control

    /// J key: Play backward or decrease playback rate
    private func handleJKey() {
        let currentRate = appState.playbackState.player?.rate ?? 0
        if currentRate > 0 {
            // Playing forward, slow down or reverse
            if currentRate > 1 {
                appState.playbackState.setPlaybackRate(currentRate / 2)
            } else {
                appState.playbackState.setPlaybackRate(-1.0)
            }
        } else if currentRate == 0 {
            // Paused, start reverse playback
            appState.playbackState.setPlaybackRate(-1.0)
        } else {
            // Already playing backward, speed up reverse
            appState.playbackState.setPlaybackRate(currentRate * 2)
        }
    }

    /// L key: Play forward or increase playback rate
    private func handleLKey() {
        let currentRate = appState.playbackState.player?.rate ?? 0
        if currentRate < 0 {
            // Playing backward, slow down or forward
            if currentRate < -1 {
                appState.playbackState.setPlaybackRate(currentRate / 2)
            } else {
                appState.playbackState.setPlaybackRate(1.0)
            }
        } else if currentRate == 0 {
            // Paused, start forward playback
            appState.playbackState.play()
        } else {
            // Already playing forward, speed up
            let newRate = min(currentRate * 2, 8.0)
            appState.playbackState.setPlaybackRate(Float(newRate))
        }
    }

    // MARK: - Caption Helper

    /// Returns the caption and the corresponding media time that should be displayed at the given time for the selected clip
    private func currentCaption(for clip: VideoClip?, at time: CMTime) -> (Caption, CMTime)? {
        guard let clip = clip else {
            // No clip selected - check all clips in timeline
            guard let project = appState.projectState.currentProject else { return nil }
            for track in project.timeline.tracks {
                for trackClip in track.clips {
                    // Check if playhead is within this clip's effective time range
                    let clipEnd = CMTimeAdd(trackClip.startTime, trackClip.effectiveDuration)
                    if time >= trackClip.startTime, time < clipEnd {
                        // Use the mapping helper to account for trimStart and removedRanges
                        let timelineOffset = CMTimeSubtract(time, trackClip.startTime)
                        let mediaTime = trackClip.originalTime(forEffectiveTime: timelineOffset)

                        if let caption = trackClip.captions.first(where: { caption in
                            mediaTime >= caption.startTime && mediaTime < caption.endTime
                        }) {
                            return (caption, mediaTime)
                        }
                    }
                }
            }
            return nil
        }

        // For selected clip: use the mapping helper
        let timelineOffset = CMTimeSubtract(time, clip.startTime)
        let mediaTime = clip.originalTime(forEffectiveTime: timelineOffset)

        if let caption = clip.captions.first(where: { caption in
            mediaTime >= caption.startTime && mediaTime < caption.endTime
        }) {
            return (caption, mediaTime)
        }
        return nil
    }

    // MARK: - Video Player with Display Mode Support

    /// Calculate optimal video size to fill available space while maintaining 16:9 aspect ratio
    private func calculateVideoSize(availableSize: CGSize) -> CGSize {
        let videoAspect: CGFloat = 16.0 / 9.0
        let containerAspect = availableSize.width / availableSize.height

        // Video size calculation: fit 16:9 video into available space with minimal padding
        let padding: CGFloat = 16 // Total padding (8 per side)
        let usableWidth = availableSize.width - padding
        let usableHeight = availableSize.height - padding

        if containerAspect > videoAspect {
            // Container is wider than video - height constrained
            let height = usableHeight
            let width = height * videoAspect
            return CGSize(width: width, height: height)
        } else {
            // Container is taller than video - width constrained
            let width = usableWidth
            let height = width / videoAspect
            return CGSize(width: width, height: height)
        }
    }

    @ViewBuilder
    private func videoPlayerView(player: AVPlayer, availableSize: CGSize) -> some View {
        let videoSize = calculateVideoSize(availableSize: availableSize)
        let usableWidth = availableSize.width - 16
        let usableHeight = availableSize.height - 16

        Group {
            switch videoDisplayMode {
            case .fit:
                // Fit: Show entire video at maximum size while maintaining aspect ratio
                AdvancedVideoPlayer(player: player)
                    .overlay {
                        CanvasOverlay(clip: selectedClip, projectState: appState.projectState)
                        // CRITICAL FIX: Add caption overlay with project style
                        if let project = appState.projectState.currentProject,
                           let captionData = currentCaption(for: selectedClip, at: appState.playbackState.currentTime) {
                            CaptionOverlayView(
                                caption: captionData.0,
                                currentTime: captionData.1,
                                style: project.captionStyle,
                                offset: Binding(
                                    get: { project.captionOffset },
                                    set: { appState.projectState.updateCaptionOffset($0) }
                                )
                            )
                        }
                    }
                    .frame(width: videoSize.width, height: videoSize.height)

            case .fill:
                // Fill: Fill the container, may crop edges
                AdvancedVideoPlayer(player: player)
                    .overlay {
                        CanvasOverlay(clip: selectedClip, projectState: appState.projectState)
                        // CRITICAL FIX: Add caption overlay with project style
                        if let project = appState.projectState.currentProject,
                           let captionData = currentCaption(for: selectedClip, at: appState.playbackState.currentTime) {
                            CaptionOverlayView(
                                caption: captionData.0,
                                currentTime: captionData.1,
                                style: project.captionStyle,
                                offset: Binding(
                                    get: { project.captionOffset },
                                    set: { appState.projectState.updateCaptionOffset($0) }
                                )
                            )
                        }
                    }
                    .frame(width: usableWidth, height: usableHeight)
                    .clipped()

            case .actual:
                // Actual: 1:1 pixel mapping, scrollable if larger
                ScrollView([.horizontal, .vertical], showsIndicators: true) {
                    AdvancedVideoPlayer(player: player)
                        .overlay {
                            CanvasOverlay(clip: selectedClip, projectState: appState.projectState)
                            // CRITICAL FIX: Add caption overlay with project style
                            if let project = appState.projectState.currentProject,
                               let captionData = currentCaption(for: selectedClip, at: appState.playbackState.currentTime) {
                                CaptionOverlayView(
                                    caption: captionData.0,
                                    currentTime: captionData.1,
                                    style: project.captionStyle,
                                    offset: Binding(
                                        get: { project.captionOffset },
                                        set: { appState.projectState.updateCaptionOffset($0) }
                                    )
                                )
                            }
                        }
                        .frame(minWidth: 640, minHeight: 360) // Minimum reasonable size
                }
                .frame(width: usableWidth, height: usableHeight)
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .shadow(color: .black.opacity(0.25), radius: 8, y: 3)
        .overlay {
            RoundedRectangle(cornerRadius: 8)
                .stroke(Color.white.opacity(0.08), lineWidth: 1)
        }
    }

    @ViewBuilder
    private var magicFixEmptyState: some View {
        VStack(spacing: 32) {
            Image(systemName: "wand.and.stars")
                .font(.system(size: 64))
                .foregroundStyle(.secondary)

            VStack(spacing: 12) {
                Text("Let's Make Some Magic")
                    .font(.system(size: 28, weight: .bold))

                Text(String(localized: "editor.empty.subtitle", defaultValue: "Drop a video here or record to see the magic."))
                    .font(.system(size: 15))
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 300)
            }

            Button(
                action: { appState.importVideo() },
                label: {
                    Label("Import Your First Video", systemImage: "plus.circle.fill")
                        .font(.headline)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                }
            )
            .buttonStyle(.borderedProminent)
            .tint(.accentColor)
            .controlSize(.large)
        }
    }
}

// MARK: - Helper Components

struct GridPattern: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        let step: CGFloat = 40

        for x in stride(from: 0, through: rect.width, by: step) {
            path.move(to: CGPoint(x: x, y: 0))
            path.addLine(to: CGPoint(x: x, y: rect.height))
        }

        for y in stride(from: 0, through: rect.height, by: step) {
            path.move(to: CGPoint(x: 0, y: y))
            path.addLine(to: CGPoint(x: rect.width, y: y))
        }

        return path
    }
}

// MARK: - Collapse Button

struct CollapseButton: View {
    @Binding var isCollapsed: Bool
    let edge: HorizontalEdge

    var body: some View {
        Button {
            withAnimation(.easeInOut(duration: 0.2)) {
                isCollapsed.toggle()
            }
        } label: {
            Image(systemName: chevronName)
                .font(.system(size: 10, weight: .semibold))
                .foregroundColor(.secondary)
                .frame(width: 16, height: 44)
                .background(Color(nsColor: .controlBackgroundColor))
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(isCollapsed ? String(localized: "action.show_panel", defaultValue: "Show Panel") : String(localized: "action.hide_panel", defaultValue: "Hide Panel"))
    }

    private var chevronName: String {
        switch edge {
        case .leading:
            return isCollapsed ? "chevron.right" : "chevron.left"
        case .trailing:
            return isCollapsed ? "chevron.left" : "chevron.right"
        }
    }
}
