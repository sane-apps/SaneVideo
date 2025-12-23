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

struct EditorLayoutView: View {
    @Environment(AppState.self) var appState
    @Binding var selectedClip: VideoClip?
    @Binding var selectedClipIds: Set<UUID> // Multi-select support

    // Collapsible panel states
    @State private var isSidebarCollapsed = false
    @State private var isInspectorCollapsed = false
    @State private var lastLoadedProjectId: UUID? // For playhead restoration

    var body: some View {
        VStack(spacing: 0) {

            Divider()

            // MAIN SPLIT VIEW (3 Panes) - Using native HSplitView for resizing
            HSplitView {
                // ... (content omitted for brevity, match existing)
                // LEFT: Sidebar (Collapsible)
                ZStack(alignment: .trailing) {
                    if !isSidebarCollapsed {
                        SidebarView(selectedClip: $selectedClip)
                            .frame(minWidth: 200, idealWidth: 260, maxWidth: 400)
                            .transition(.move(edge: .leading).combined(with: .opacity))
                            .animation(.spring(response: 0.4, dampingFraction: 0.8), value: isSidebarCollapsed)
                    }
                    
                    CollapseButton(isCollapsed: $isSidebarCollapsed, edge: .leading)
                        .accessibilityIdentifier("SidebarToggle")
                        .offset(x: 8)
                        .zIndex(1)
                }

                // CENTER: Stage (Player + Timeline)
                VSplitView {
                    // PLAYER STAGE
                    ZStack {
                        // ... existing backdrop code ...
                        Color(nsColor: .windowBackgroundColor)
                            .ignoresSafeArea()
                        
                        // Subtle grid pattern
                        GridPattern()
                            .stroke(Color.white.opacity(0.04), lineWidth: 0.5)

                        if let player = appState.playbackState.player {
                            VStack(spacing: 0) {
                                Spacer()
                                
                                // Video Window with Heavy Professional Shadow
                                AdvancedVideoPlayer(player: player)
                                    .overlay {
                                        CanvasOverlay(clip: selectedClip, projectState: appState.projectState)
                                    }
                                    .aspectRatio(16/9, contentMode: .fit)
                                    .padding(40)
                                    .shadow(color: .black.opacity(0.3), radius: 10, y: 5)
                                    .overlay {
                                        RoundedRectangle(cornerRadius: 12)
                                            .stroke(Color.white.opacity(0.1), lineWidth: 1)
                                    }
                                
                                Spacer()
                                
                                PlayerControlBar(
                                    playbackState: appState.playbackState,
                                    projectState: appState.projectState
                                )
                                .padding(.bottom, 12)
                            }
                        } else {
                            // EMPTY STATE: Elevated Magic Fix
                            magicFixEmptyState
                        }
                    }
                    .frame(minHeight: 250)
                    .clipShape(Rectangle())

                    // TIMELINE
                    SaneTimelineView(
                        selectedClip: $selectedClip,
                        selectedClipIds: $selectedClipIds
                    )
                    .frame(minHeight: 180)
                }
                .frame(minWidth: 400, maxWidth: .infinity, maxHeight: .infinity)

                // RIGHT: Inspector (Collapsible)
                ZStack(alignment: .leading) {
                    CollapseButton(isCollapsed: $isInspectorCollapsed, edge: .trailing)
                        .accessibilityIdentifier("InspectorToggle")
                        .offset(x: -8)
                        .zIndex(1)

                    if !isInspectorCollapsed {
                        StylesInspectorView(selectedClip: $selectedClip)
                            .frame(minWidth: 260, idealWidth: 320, maxWidth: 450)
                            .transition(.move(edge: .trailing).combined(with: .opacity))
                    }
                }
            }
            .animation(.easeInOut(duration: 0.2), value: isSidebarCollapsed)
            .animation(.easeInOut(duration: 0.2), value: isInspectorCollapsed)
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
        .onChange(of: appState.projectState.currentProject) { old, new in
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
            // Batch Magic Fix for all clips
            Task {
                guard let project = appState.projectState.currentProject else { return }
                for track in project.timeline.tracks {
                    for clip in track.clips {
                        await appState.projectState.performMagicFix(for: clip, options: appState.projectState.magicFixOptions)
                    }
                }
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: NSNotification.Name("GenerateAllCaptions"))) { _ in
            // Batch generate captions for all clips
            Task {
                guard let project = appState.projectState.currentProject else { return }
                for track in project.timeline.tracks {
                    for clip in track.clips {
                        _ = try? await appState.projectState.generateCaptions(for: clip)
                    }
                }
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
        .background(.thickMaterial)
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
                .background(Color.secondary.opacity(0.1))
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
