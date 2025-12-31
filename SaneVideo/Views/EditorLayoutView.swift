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
        // MARK: - Timeline Navigation Keyboard Shortcuts
        .modifier(TimelineKeyboardModifier(
            onPrevBoundary: goToPreviousClipBoundary,
            onNextBoundary: goToNextClipBoundary,
            onExtendPrev: extendSelectionToPreviousClip,
            onExtendNext: extendSelectionToNextClip,
            onSelectAll: selectAllClips,
            onDeselectAll: deselectAllClips,
            onSelectAtPlayhead: selectClipAtPlayhead
        ))
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
                // CRITICAL FIX: Clear selection immediately - old clip doesn't exist in new project
                // StateChangePipeline will auto-select first clip after debounce
                selectedClip = nil
                // Restore playhead position when switching projects
                if newProfile.currentTime > 0 {
                    appState.playbackState.seek(to: CMTime(seconds: newProfile.currentTime, preferredTimescale: 600))
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

                // Shift + Left Arrow = Seek backward 10 seconds
                Button("") {
                    appState.playbackState.seekBackward10Seconds()
                }
                .keyboardShortcut(.leftArrow, modifiers: [.shift])
                .accessibilityIdentifier("shortcut.seek_backward_10s")

                // Shift + Right Arrow = Seek forward 10 seconds
                Button("") {
                    appState.playbackState.seekForward10Seconds()
                }
                .keyboardShortcut(.rightArrow, modifiers: [.shift])
                .accessibilityIdentifier("shortcut.seek_forward_10s")

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

                // PHASE 1: Escape = Deselect All
                Button("") {
                    selectedClip = nil
                    selectedClipIds.removeAll()
                }
                .keyboardShortcut(.escape, modifiers: [])
                .accessibilityIdentifier("shortcut.deselect_all")

                // PHASE 1: Cmd+A = Select All Clips
                Button("") {
                    selectAllClips()
                }
                .keyboardShortcut("a", modifiers: [.command])
                .accessibilityIdentifier("shortcut.select_all")

                // PHASE 1: Home = Go to Timeline Start
                Button("") {
                    appState.playbackState.seek(to: .zero)
                }
                .keyboardShortcut(.home, modifiers: [])
                .accessibilityIdentifier("shortcut.go_to_start")

                // PHASE 1: End = Go to Timeline End
                Button("") {
                    appState.playbackState.seek(to: appState.playbackState.duration)
                }
                .keyboardShortcut(.end, modifiers: [])
                .accessibilityIdentifier("shortcut.go_to_end")

                // PHASE 1: I = Set In Point
                Button("") {
                    appState.playbackState.inPoint = appState.playbackState.currentTime
                }
                .keyboardShortcut("i", modifiers: [])
                .accessibilityIdentifier("shortcut.set_in_point")

                // PHASE 1: O = Set Out Point
                Button("") {
                    appState.playbackState.outPoint = appState.playbackState.currentTime
                }
                .keyboardShortcut("o", modifiers: [])
                .accessibilityIdentifier("shortcut.set_out_point")

                // PHASE 1: Cmd+Shift+X = Clear In/Out Points
                Button("") {
                    appState.playbackState.clearInOutPoints()
                }
                .keyboardShortcut("x", modifiers: [.command, .shift])
                .accessibilityIdentifier("shortcut.clear_in_out")

                // PHASE 2: Up/Down Arrow and D shortcuts moved to menu commands
                // to avoid hidden button crash (use-after-free in ButtonAction.callAsFunction)

                // PHASE 2: Shift+Z = Fit Timeline to Window
                Button("") {
                    NotificationCenter.default.post(name: NSNotification.Name("FitTimelineToWindow"), object: nil)
                }
                .keyboardShortcut("z", modifiers: [.shift])
                .accessibilityIdentifier("shortcut.fit_to_window")

                // PHASE 2: Cmd+C = Copy Clip
                Button("") {
                    copySelectedClip()
                }
                .keyboardShortcut("c", modifiers: [.command])
                .accessibilityIdentifier("shortcut.copy_clip")

                // PHASE 2: Cmd+X = Cut Clip
                Button("") {
                    cutSelectedClip()
                }
                .keyboardShortcut("x", modifiers: [.command])
                .accessibilityIdentifier("shortcut.cut_clip")

                // PHASE 2: Cmd+V = Paste Clip
                Button("") {
                    pasteClip()
                }
                .keyboardShortcut("v", modifiers: [.command])
                .accessibilityIdentifier("shortcut.paste_clip")

                // PHASE 2: Cmd+D = Duplicate Clip
                Button("") {
                    duplicateSelectedClip()
                }
                .keyboardShortcut("d", modifiers: [.command])
                .accessibilityIdentifier("shortcut.duplicate_clip")

                // PHASE 3: Cmd+Shift+M = Magic Fix (Super Magic Fix)
                Button("") {
                    applyMagicFix()
                }
                .keyboardShortcut("m", modifiers: [.command, .shift])
                .accessibilityIdentifier("shortcut.magic_fix")
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

                    // PERFORMANCE: Show thumbnail until player is ready, then show AVPlayer
                    if let player = appState.playbackState.player {
                        // PLAYER READY: Show AVPlayer (playing or paused)
                        videoPlayerView(player: player, availableSize: geometry.size)
                    } else if let project = appState.projectState.currentProject,
                              project.timeline.tracks.contains(where: { !$0.clips.isEmpty }) {
                        // HAS CONTENT BUT NO PLAYER: Show thumbnail with play button
                        // This makes project switching instant - no composition until play
                        thumbnailPreviewView(for: project, availableSize: geometry.size)
                    } else {
                        // EMPTY STATE: No project or no clips
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
                    // CRITICAL FIX: Force re-render when selectedClip changes
                    .id(selectedClip?.id)
                    .transition(.opacity)
            }
        }
        // CONSISTENCY: Inspector pane uses same controlBackgroundColor
        .background(Color(nsColor: .controlBackgroundColor))
    }

    // MARK: - Selection Helpers

    /// Select all clips in the current project timeline
    private func selectAllClips() {
        guard let project = appState.projectState.currentProject else { return }
        let allClips = project.timeline.tracks.flatMap { $0.clips }
        selectedClipIds = Set(allClips.map { $0.id })
        // Select the first clip as the primary selection
        if selectedClip == nil, let first = allClips.first {
            selectedClip = first
        }
    }

    /// Select the clip under the current playhead position
    private func selectClipAtPlayhead() {
        guard let project = appState.projectState.currentProject else { return }
        let currentTime = appState.playbackState.currentTime

        for track in project.timeline.tracks {
            for clip in track.clips {
                let clipEnd = CMTimeAdd(clip.startTime, clip.effectiveDuration)
                if currentTime >= clip.startTime && currentTime < clipEnd {
                    selectedClip = clip
                    selectedClipIds = [clip.id]
                    return
                }
            }
        }
    }

    /// Deselect all clips (Escape key)
    private func deselectAllClips() {
        selectedClip = nil
        selectedClipIds.removeAll()
    }

    /// Extend selection to include the previous clip (Shift+Up)
    private func extendSelectionToPreviousClip() {
        guard let project = appState.projectState.currentProject else { return }

        // Get all clips sorted by start time
        let allClips = project.timeline.tracks
            .flatMap { $0.clips }
            .sorted { $0.startTime < $1.startTime }

        guard !allClips.isEmpty else { return }

        // Find the earliest selected clip
        let selectedClips = allClips.filter { selectedClipIds.contains($0.id) }
        guard let earliestSelected = selectedClips.min(by: { $0.startTime < $1.startTime }) else {
            // No selection - select the clip at playhead or first clip
            if let first = allClips.first {
                selectedClip = first
                selectedClipIds = [first.id]
            }
            return
        }

        // Find the clip before the earliest selected
        if let earliestIndex = allClips.firstIndex(where: { $0.id == earliestSelected.id }),
           earliestIndex > 0 {
            let previousClip = allClips[earliestIndex - 1]
            selectedClipIds.insert(previousClip.id)
            selectedClip = previousClip // Move primary selection
            appState.playbackState.seek(to: previousClip.startTime)
        }
    }

    /// Extend selection to include the next clip (Shift+Down)
    private func extendSelectionToNextClip() {
        guard let project = appState.projectState.currentProject else { return }

        // Get all clips sorted by start time
        let allClips = project.timeline.tracks
            .flatMap { $0.clips }
            .sorted { $0.startTime < $1.startTime }

        guard !allClips.isEmpty else { return }

        // Find the latest selected clip
        let selectedClips = allClips.filter { selectedClipIds.contains($0.id) }
        guard let latestSelected = selectedClips.max(by: { $0.startTime < $1.startTime }) else {
            // No selection - select the clip at playhead or first clip
            if let first = allClips.first {
                selectedClip = first
                selectedClipIds = [first.id]
            }
            return
        }

        // Find the clip after the latest selected
        if let latestIndex = allClips.firstIndex(where: { $0.id == latestSelected.id }),
           latestIndex < allClips.count - 1 {
            let nextClip = allClips[latestIndex + 1]
            selectedClipIds.insert(nextClip.id)
            selectedClip = nextClip // Move primary selection
            let clipEnd = CMTimeAdd(nextClip.startTime, nextClip.effectiveDuration)
            appState.playbackState.seek(to: clipEnd)
        }
    }

    // MARK: - Clip Boundary Navigation

    /// Navigate to the previous clip boundary (start or end of any clip)
    private func goToPreviousClipBoundary() {
        guard let project = appState.projectState.currentProject else { return }
        let currentTime = appState.playbackState.currentTime

        // Collect all clip boundaries (start and end times)
        var boundaries: [CMTime] = [.zero] // Always include timeline start
        for track in project.timeline.tracks {
            for clip in track.clips {
                boundaries.append(clip.startTime)
                boundaries.append(CMTimeAdd(clip.startTime, clip.effectiveDuration))
            }
        }

        // Sort and find the largest boundary that's before current time
        boundaries.sort { $0 < $1 }
        let tolerance = CMTime(seconds: 0.01, preferredTimescale: 600) // Small tolerance to avoid getting stuck

        if let prevBoundary = boundaries.last(where: { $0 < CMTimeSubtract(currentTime, tolerance) }) {
            appState.playbackState.seek(to: prevBoundary)
        }
    }

    /// Navigate to the next clip boundary (start or end of any clip)
    private func goToNextClipBoundary() {
        guard let project = appState.projectState.currentProject else { return }
        let currentTime = appState.playbackState.currentTime
        let duration = appState.playbackState.duration

        // Collect all clip boundaries (start and end times)
        var boundaries: [CMTime] = [duration] // Always include timeline end
        for track in project.timeline.tracks {
            for clip in track.clips {
                boundaries.append(clip.startTime)
                boundaries.append(CMTimeAdd(clip.startTime, clip.effectiveDuration))
            }
        }

        // Sort and find the smallest boundary that's after current time
        boundaries.sort { $0 < $1 }
        let tolerance = CMTime(seconds: 0.01, preferredTimescale: 600)

        if let nextBoundary = boundaries.first(where: { $0 > CMTimeAdd(currentTime, tolerance) }) {
            appState.playbackState.seek(to: nextBoundary)
        }
    }

    // MARK: - Clipboard Operations

    /// Clipboard storage for copy/cut/paste operations
    @State private var clipboardClip: VideoClip?

    /// Copy the selected clip to clipboard
    private func copySelectedClip() {
        guard let clip = selectedClip else { return }
        clipboardClip = clip
        ServiceContainer.shared.toastManager.show("Copied: \(clip.url.lastPathComponent)", type: .success)
    }

    /// Cut the selected clip (copy + delete)
    private func cutSelectedClip() {
        guard let clip = selectedClip else { return }
        clipboardClip = clip
        appState.projectState.deleteClip(clip)
        selectedClip = nil
        selectedClipIds.removeAll()
        ServiceContainer.shared.toastManager.show("Cut: \(clip.url.lastPathComponent)", type: .success)
    }

    /// Paste clip from clipboard at current playhead position
    private func pasteClip() {
        guard let clip = clipboardClip else {
            ServiceContainer.shared.toastManager.show("Nothing to paste", type: .error)
            return
        }

        // Create a copy of the clip at the current playhead position
        let currentTime = appState.playbackState.currentTime
        appState.projectState.duplicateClip(clip, atTime: currentTime)
        ServiceContainer.shared.toastManager.show("Pasted: \(clip.url.lastPathComponent)", type: .success)
    }

    /// Duplicate the selected clip immediately after it
    private func duplicateSelectedClip() {
        guard let clip = selectedClip else { return }
        let insertTime = CMTimeAdd(clip.startTime, clip.effectiveDuration)
        appState.projectState.duplicateClip(clip, atTime: insertTime)
        ServiceContainer.shared.toastManager.show("Duplicated: \(clip.url.lastPathComponent)", type: .success)
    }

    /// Apply Magic Fix to the selected clip (Cmd+Shift+M)
    private func applyMagicFix() {
        guard let clip = selectedClip else {
            ServiceContainer.shared.toastManager.show("Select a clip first", type: .error)
            return
        }

        guard !clip.isMissing else {
            ServiceContainer.shared.toastManager.show("Cannot apply Magic Fix: Clip file is missing", type: .error)
            return
        }

        // Ensure Inspector is visible
        withAnimation {
            isInspectorCollapsed = false
        }

        // Trigger Magic Fix
        Task {
            await appState.projectState.performMagicFix(for: clip, options: appState.projectState.magicFixOptions)
        }
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

    // MARK: - Thumbnail Preview (Instant Project Switching)

    /// Show a static thumbnail instead of AVPlayer until user clicks play
    /// This makes project switching instant - no composition needed until playback
    @ViewBuilder
    private func thumbnailPreviewView(for project: VideoProject, availableSize: CGSize) -> some View {
        let videoSize = calculateVideoSize(availableSize: availableSize)

        ZStack {
            // Background
            Color.black

            // Show thumbnail from first clip
            if let firstClip = project.timeline.tracks.flatMap({ $0.clips }).first {
                ThumbnailPreviewImage(clip: firstClip, size: videoSize)
            }

            // Play button overlay
            Button {
                appState.playbackState.play()
            } label: {
                ZStack {
                    Circle()
                        .fill(.black.opacity(0.5))
                        .frame(width: 80, height: 80)

                    Image(systemName: "play.fill")
                        .font(.system(size: 32))
                        .foregroundColor(.white)
                }
            }
            .buttonStyle(.plain)
            .opacity(appState.playbackState.player == nil ? 0.9 : 0.7)

            // Loading indicator if composition is in progress
            if appState.playbackState.player == nil {
                VStack {
                    Spacer()
                    HStack {
                        ProgressView()
                            .scaleEffect(0.7)
                            .tint(.white)
                        Text("Loading...")
                            .font(.caption)
                            .foregroundColor(.white.opacity(0.8))
                    }
                    .padding(8)
                    .background(.black.opacity(0.6), in: Capsule())
                    .padding(.bottom, 16)
                }
            }

            // Caption overlay (if applicable)
            if let captionData = currentCaption(for: selectedClip, at: appState.playbackState.currentTime) {
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
        .clipShape(RoundedRectangle(cornerRadius: 8))
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

// MARK: - Timeline Keyboard Modifier
// Extracted to help compiler type-check the complex EditorLayoutView body

struct TimelineKeyboardModifier: ViewModifier {
    let onPrevBoundary: () -> Void
    let onNextBoundary: () -> Void
    let onExtendPrev: () -> Void
    let onExtendNext: () -> Void
    let onSelectAll: () -> Void
    let onDeselectAll: () -> Void
    let onSelectAtPlayhead: () -> Void

    func body(content: Content) -> some View {
        content
            .focusable()
            .focusEffectDisabled()
            // Up Arrow: Shift = extend selection, plain = previous boundary
            .onKeyPress(.upArrow, phases: .down) { press in
                if press.modifiers.contains(.shift) {
                    onExtendPrev()
                } else {
                    onPrevBoundary()
                }
                return .handled
            }
            // Down Arrow: Shift = extend selection, plain = next boundary
            .onKeyPress(.downArrow, phases: .down) { press in
                if press.modifiers.contains(.shift) {
                    onExtendNext()
                } else {
                    onNextBoundary()
                }
                return .handled
            }
            // Cmd+A = select all
            .onKeyPress(KeyEquivalent("a"), phases: .down) { press in
                if press.modifiers.contains(.command) {
                    onSelectAll()
                    return .handled
                }
                return .ignored
            }
            // Escape = deselect all
            .onKeyPress(.escape) {
                onDeselectAll()
                return .handled
            }
            // D = select clip at playhead
            .onKeyPress(KeyEquivalent("d")) {
                onSelectAtPlayhead()
                return .handled
            }
    }
}
