import AVFoundation
import CoreMedia
import SwiftUI

struct EditorLayoutView: View {
    @Environment(AppState.self) var appState
    @Binding var selectedClip: VideoClip?
    @Binding var selectedClipIds: Set<UUID>

    @State private var isSidebarCollapsed = false
    @State private var isInspectorCollapsed = false
    @State private var lastLoadedProjectId: UUID? // For playhead restoration

    @AppStorage("editor.videoDisplayMode") private var videoDisplayMode: VideoDisplayMode = .fit

    // Kept so each new run cancels the previous one; rapid hotkey presses otherwise pile up tasks.
    @State private var magicFixTask: Task<Void, Never>?
    @State private var captionTask: Task<Void, Never>?
    @State private var audioCleanTask: Task<Void, Never>?

    private let sidebarExpandedWidth: CGFloat = 290
    private let inspectorExpandedWidth: CGFloat = 320
    private let collapsedWidth: CGFloat = 20 // Collapsed width for sidebar toggle button

    var body: some View {
        VStack(spacing: 0) {
            Divider()

            // HStack with explicit widths instead of HSplitView, which handles collapsing panels poorly.
            GeometryReader { _ in
                HStack(spacing: 0) {
                    sidebarPane
                        .frame(width: isSidebarCollapsed ? collapsedWidth : sidebarExpandedWidth)

                    centerPane
                        .frame(maxWidth: .infinity, maxHeight: .infinity)

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
                // Clear selection immediately - old clip doesn't exist in new project
                // StateChangePipeline will auto-select first clip after debounce
                selectedClip = nil
                selectedClipIds.removeAll()
                appState.selectedClipIds.removeAll()
                if newProfile.currentTime > 0 {
                    appState.playbackState.seek(to: CMTime(seconds: newProfile.currentTime, preferredTimescale: 600))
                }
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: NSNotification.Name("TriggerMagicFix"))) { _ in
            withAnimation {
                isInspectorCollapsed = false
            }
            if let clip = selectedClip {
                magicFixTask?.cancel()
                magicFixTask = Task {
                    await appState.projectState.performMagicFix(for: clip, options: appState.projectState.magicFixOptions)
                }
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: NSNotification.Name("TriggerMagicFixAll"))) { _ in
            magicFixTask?.cancel()
            magicFixTask = Task {
                _ = await appState.projectState.performMagicFixAll(options: appState.projectState.magicFixOptions)
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: NSNotification.Name("GenerateAllCaptions"))) { _ in
            captionTask?.cancel()
            captionTask = Task {
                _ = await appState.projectState.generateCaptionsAll()
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: NSNotification.Name("CleanAllAudio"))) { _ in
            audioCleanTask?.cancel()
            audioCleanTask = Task {
                await appState.projectState.cleanProjectAudio()
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: NSNotification.Name("ToggleSidebar"))) { _ in
            withAnimation { isSidebarCollapsed.toggle() }
        }
        .onReceive(NotificationCenter.default.publisher(for: NSNotification.Name("ToggleInspector"))) { _ in
            withAnimation { isInspectorCollapsed.toggle() }
        }
        .onReceive(NotificationCenter.default.publisher(for: NSNotification.Name("ShowSidebarProjects"))) { _ in
            // Expand sidebar if collapsed, then SidebarView will select Projects tab
            if isSidebarCollapsed {
                withAnimation { isSidebarCollapsed = false }
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: NSNotification.Name("ShowSidebarTranscript"))) { _ in
            // Expand sidebar if collapsed, then SidebarView will select Transcript tab
            if isSidebarCollapsed {
                withAnimation { isSidebarCollapsed = false }
            }
        }
        .background(SaneVideoEditorChromeBackground())
        .liquidGlass(radius: 0)

        // MARK: - Keyboard Shortcuts (J/K/L/Space)

        .overlay {
            // Hidden buttons for keyboard shortcuts
            Group {
                Button("") {
                    appState.playbackState.togglePlayPause()
                }
                .keyboardShortcut(.space, modifiers: [])
                .accessibilityIdentifier("shortcut.play_pause")

                Button("") {
                    appState.playbackState.pause()
                }
                .keyboardShortcut("k", modifiers: [])
                .accessibilityIdentifier("shortcut.pause")

                Button("") {
                    handleJKey()
                }
                .keyboardShortcut("j", modifiers: [])
                .accessibilityIdentifier("shortcut.shuttle_backward")

                Button("") {
                    handleLKey()
                }
                .keyboardShortcut("l", modifiers: [])
                .accessibilityIdentifier("shortcut.shuttle_forward")

                Button("") {
                    appState.playbackState.stepBackward()
                }
                .keyboardShortcut(.leftArrow, modifiers: [])
                .accessibilityIdentifier("shortcut.step_backward")

                Button("") {
                    appState.playbackState.stepForward()
                }
                .keyboardShortcut(.rightArrow, modifiers: [])
                .accessibilityIdentifier("shortcut.step_forward")

                Button("") {
                    appState.playbackState.seekBackward10Seconds()
                }
                .keyboardShortcut(.leftArrow, modifiers: [.shift])
                .accessibilityIdentifier("shortcut.seek_backward_10s")

                Button("") {
                    appState.playbackState.seekForward10Seconds()
                }
                .keyboardShortcut(.rightArrow, modifiers: [.shift])
                .accessibilityIdentifier("shortcut.seek_forward_10s")

                Button("") {
                    if let clip = selectedClip {
                        appState.projectState.splitClip(clip, atTimelineTime: appState.playbackState.currentTime)
                    }
                }
                .keyboardShortcut("b", modifiers: [.command])
                .accessibilityIdentifier("shortcut.split_clip")

                Button("") {
                    if let clip = selectedClip {
                        appState.projectState.deleteClip(clip)
                        selectedClip = nil
                    }
                }
                .keyboardShortcut(.delete, modifiers: [])
                .accessibilityIdentifier("shortcut.delete_clip")

                Button("") {
                    selectedClip = nil
                    selectedClipIds.removeAll()
                }
                .keyboardShortcut(.escape, modifiers: [])
                .accessibilityIdentifier("shortcut.deselect_all")

                Button("") {
                    selectAllClips()
                }
                .keyboardShortcut("a", modifiers: [.command])
                .accessibilityIdentifier("shortcut.select_all")

                Button("") {
                    appState.playbackState.seek(to: .zero)
                }
                .keyboardShortcut(.home, modifiers: [])
                .accessibilityIdentifier("shortcut.go_to_start")

                Button("") {
                    appState.playbackState.seek(to: appState.playbackState.duration)
                }
                .keyboardShortcut(.end, modifiers: [])
                .accessibilityIdentifier("shortcut.go_to_end")

                Button("") {
                    appState.playbackState.inPoint = appState.playbackState.currentTime
                }
                .keyboardShortcut("i", modifiers: [])
                .accessibilityIdentifier("shortcut.set_in_point")

                Button("") {
                    appState.playbackState.outPoint = appState.playbackState.currentTime
                }
                .keyboardShortcut("o", modifiers: [])
                .accessibilityIdentifier("shortcut.set_out_point")

                Button("") {
                    appState.playbackState.clearInOutPoints()
                }
                .keyboardShortcut("x", modifiers: [.command, .shift])
                .accessibilityIdentifier("shortcut.clear_in_out")

                // Up/Down arrow and D shortcuts live in menu commands: hidden buttons for them crashed
                // with a use-after-free in ButtonAction.callAsFunction.

                Button("") {
                    NotificationCenter.default.post(name: NSNotification.Name("FitTimelineToWindow"), object: nil)
                }
                .keyboardShortcut("z", modifiers: [.shift])
                .accessibilityIdentifier("shortcut.fit_to_window")

                Button("") {
                    copySelectedClip()
                }
                .keyboardShortcut("c", modifiers: [.command])
                .accessibilityIdentifier("shortcut.copy_clip")

                Button("") {
                    cutSelectedClip()
                }
                .keyboardShortcut("x", modifiers: [.command])
                .accessibilityIdentifier("shortcut.cut_clip")

                Button("") {
                    pasteClip()
                }
                .keyboardShortcut("v", modifiers: [.command])
                .accessibilityIdentifier("shortcut.paste_clip")

                Button("") {
                    duplicateSelectedClip()
                }
                .keyboardShortcut("d", modifiers: [.command])
                .accessibilityIdentifier("shortcut.duplicate_clip")

                Button("") {
                    applyMagicFix()
                }
                .keyboardShortcut("m", modifiers: [.command, .shift])
                .accessibilityIdentifier("shortcut.magic_fix")
            }
            .disabled(!appState.projectCommandsEnabled)
            .opacity(0)
            .allowsHitTesting(false)
        }
    }

    // MARK: - Layout Panes

    private var sidebarPane: some View {
        ZStack(alignment: .trailing) {
            if !isSidebarCollapsed {
                SidebarView(selectedClip: $selectedClip)
                    .frame(width: sidebarExpandedWidth, alignment: .leading)
                    .clipped()
                    .transition(.opacity)
            }

            CollapseButton(isCollapsed: $isSidebarCollapsed, edge: .leading)
                .accessibilityIdentifier(AccessibilityIdentifiers.sidebarToggle)
                .offset(x: 8)
                .zIndex(1)
        }
        .background(SaneVideoEditorPanelBackground())
    }

    private var centerPane: some View {
        VStack(spacing: 0) {
            GeometryReader { geometry in
                ZStack {
                    SaneVideoEditorChromeBackground()

                    // Show thumbnail until player is ready, then show AVPlayer
                    if let player = appState.playbackState.player {
                        EditorVideoPlayerView(
                            player: player,
                            availableSize: geometry.size,
                            displayMode: videoDisplayMode,
                            selectedClip: selectedClip,
                            projectState: appState.projectState,
                            captionData: currentCaption(for: selectedClip, at: appState.playbackState.currentTime),
                            project: appState.projectState.currentProject
                        )
                    } else if let project = appState.projectState.currentProject,
                              project.timeline.tracks.contains(where: { !$0.clips.isEmpty }) {
                        // This makes project switching instant - no composition until play
                        EditorThumbnailPreviewView(
                            project: project,
                            availableSize: geometry.size,
                            selectedClip: selectedClip,
                            currentTime: appState.playbackState.currentTime,
                            onPlay: { appState.playbackState.play() },
                            isPlayerReady: appState.playbackState.player != nil,
                            isPreparingPreview: appState.playbackState.isPreparingComposition,
                            captionData: currentCaption(for: selectedClip, at: appState.playbackState.currentTime)
                        )
                    } else {
                        EditorEmptyStateView(
                            onImport: { appState.importVideo() },
                            onRecord: {
                                withAnimation(.smoothUI) {
                                    appState.appMode = .recording
                                }
                            }
                        )
                    }
                }
            }

            SaneTimelineView(
                selectedClip: $selectedClip,
                selectedClipIds: $selectedClipIds
            )
            .frame(height: 240) // Fits the toolbar (42pt), ruler (40pt) and tracks.
        }
    }

    private var inspectorPane: some View {
        ZStack(alignment: .leading) {
            CollapseButton(isCollapsed: $isInspectorCollapsed, edge: .trailing)
                .accessibilityIdentifier(AccessibilityIdentifiers.inspectorToggle)
                .offset(x: -8)
                .zIndex(1)

            if !isInspectorCollapsed {
                StylesInspectorView(selectedClip: $selectedClip)
                    // Force re-render when selectedClip changes
                    .id(selectedClip?.id)
                    .transition(.opacity)
            }
        }
        .background(SaneVideoEditorPanelBackground(emphasized: true))
    }

    // MARK: - Selection Helpers

    private func selectAllClips() {
        guard let project = appState.projectState.currentProject else { return }
        let allClips = project.timeline.tracks.flatMap(\.clips)
        selectedClipIds = Set(allClips.map(\.id))
        if selectedClip == nil, let first = allClips.first {
            selectedClip = first
        }
    }

    private func selectClipAtPlayhead() {
        guard let project = appState.projectState.currentProject else { return }
        let currentTime = appState.playbackState.currentTime

        for track in project.timeline.tracks {
            for clip in track.clips {
                let clipEnd = CMTimeAdd(clip.startTime, clip.effectiveDuration)
                if currentTime >= clip.startTime, currentTime < clipEnd {
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

        let allClips = project.timeline.tracks
            .flatMap(\.clips)
            .sorted { $0.startTime < $1.startTime }

        guard !allClips.isEmpty else { return }

        let selectedClips = allClips.filter { selectedClipIds.contains($0.id) }
        guard let earliestSelected = selectedClips.min(by: { $0.startTime < $1.startTime }) else {
            if let first = allClips.first {
                selectedClip = first
                selectedClipIds = [first.id]
            }
            return
        }

        if let earliestIndex = allClips.firstIndex(where: { $0.id == earliestSelected.id }),
           earliestIndex > 0 {
            let previousClip = allClips[earliestIndex - 1]
            selectedClipIds.insert(previousClip.id)
            selectedClip = previousClip
            appState.playbackState.seek(to: previousClip.startTime)
        }
    }

    /// Extend selection to include the next clip (Shift+Down)
    private func extendSelectionToNextClip() {
        guard let project = appState.projectState.currentProject else { return }

        let allClips = project.timeline.tracks
            .flatMap(\.clips)
            .sorted { $0.startTime < $1.startTime }

        guard !allClips.isEmpty else { return }

        let selectedClips = allClips.filter { selectedClipIds.contains($0.id) }
        guard let latestSelected = selectedClips.max(by: { $0.startTime < $1.startTime }) else {
            if let first = allClips.first {
                selectedClip = first
                selectedClipIds = [first.id]
            }
            return
        }

        if let latestIndex = allClips.firstIndex(where: { $0.id == latestSelected.id }),
           latestIndex < allClips.count - 1 {
            let nextClip = allClips[latestIndex + 1]
            selectedClipIds.insert(nextClip.id)
            selectedClip = nextClip
            let clipEnd = CMTimeAdd(nextClip.startTime, nextClip.effectiveDuration)
            appState.playbackState.seek(to: clipEnd)
        }
    }

    // MARK: - Clip Boundary Navigation

    /// Navigate to the previous clip boundary (start or end of any clip)
    private func goToPreviousClipBoundary() {
        guard let project = appState.projectState.currentProject else { return }
        let currentTime = appState.playbackState.currentTime

        var boundaries: [CMTime] = [.zero]
        for track in project.timeline.tracks {
            for clip in track.clips {
                boundaries.append(clip.startTime)
                boundaries.append(CMTimeAdd(clip.startTime, clip.effectiveDuration))
            }
        }

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

        var boundaries: [CMTime] = [duration]
        for track in project.timeline.tracks {
            for clip in track.clips {
                boundaries.append(clip.startTime)
                boundaries.append(CMTimeAdd(clip.startTime, clip.effectiveDuration))
            }
        }

        boundaries.sort { $0 < $1 }
        let tolerance = CMTime(seconds: 0.01, preferredTimescale: 600)

        if let nextBoundary = boundaries.first(where: { $0 > CMTimeAdd(currentTime, tolerance) }) {
            appState.playbackState.seek(to: nextBoundary)
        }
    }

    // MARK: - Clipboard Operations

    @State private var clipboardClip: VideoClip?

    private func copySelectedClip() {
        guard let clip = selectedClip else { return }
        clipboardClip = clip
        ServiceContainer.shared.toastManager.show("Copied: \(clip.url.lastPathComponent)", type: .success)
    }

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

        withAnimation {
            isInspectorCollapsed = false
        }

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
        guard let clip else {
            // No clip selected - check all clips in timeline
            guard let project = appState.projectState.currentProject else { return nil }
            for track in project.timeline.tracks {
                for trackClip in track.clips {
                    let clipEnd = CMTimeAdd(trackClip.startTime, trackClip.effectiveDuration)
                    if time >= trackClip.startTime, time < clipEnd {
                        // Use the mapping helper to account for trimStart and removedRanges
                        let timelineOffset = CMTimeSubtract(time, trackClip.startTime)
                        let mediaTime = trackClip.originalTime(forEffectiveTime: timelineOffset)

                        if let caption = trackClip.captions.first(where: { caption in
                            mediaTime >= caption.startTime && mediaTime < caption.endTime
                        })?.removingWords(in: trackClip.removedRanges) {
                            return (caption, mediaTime)
                        }
                    }
                }
            }
            return nil
        }

        let timelineOffset = CMTimeSubtract(time, clip.startTime)
        let mediaTime = clip.originalTime(forEffectiveTime: timelineOffset)

        if let caption = clip.captions.first(where: { caption in
            mediaTime >= caption.startTime && mediaTime < caption.endTime
        })?.removingWords(in: clip.removedRanges) {
            return (caption, mediaTime)
        }
        return nil
    }

}
