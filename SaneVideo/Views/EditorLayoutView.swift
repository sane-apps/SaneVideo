//
//  EditorLayoutView.swift
//  SaneVideo
//
//  Created by SaneVideo Refactor
//

import AVFoundation
import CoreMedia
import SwiftUI

struct EditorLayoutView: View {
    @Environment(AppState.self) var appState
    @Binding var selectedClip: VideoClip?
    @Binding var selectedClipIds: Set<UUID> // Multi-select support

    // Collapsible panel states
    @State private var isSidebarCollapsed = false
    @State private var isInspectorCollapsed = false

    var body: some View {
        VStack(spacing: 0) {
            // Top Bar - Compact
            ModeSwitcherView()
                .padding(.vertical, 4)
                .background(.regularMaterial)

            Divider()

            // MAIN SPLIT VIEW (3 Panes)
            HStack(spacing: 0) {
                // LEFT: Sidebar (Collapsible)
                if !isSidebarCollapsed {
                    SidebarView(selectedClip: $selectedClip)
                        .frame(minWidth: 180, idealWidth: 240, maxWidth: 300)
                        .transition(.move(edge: .leading).combined(with: .opacity))
                }

                // Sidebar Toggle Button
                CollapseButton(isCollapsed: $isSidebarCollapsed, edge: .leading)
                    .accessibilityIdentifier("SidebarToggle")

                Divider()

                // CENTER: Player & Timeline
                VSplitView {
                    // Player Area with gradient background
                    GeometryReader { geometry in
                        ZStack {
                            // Background: Dark gradient (CapCut-style)
                            LinearGradient(
                                colors: [
                                    Color(white: 0.08),
                                    Color(white: 0.04),
                                    Color(white: 0.08)
                                ],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )

                            if let player = appState.playbackState.player {
                                // Video Player - centered
                                AdvancedVideoPlayer(player: player)
                                    .overlay {
                                        CanvasOverlay(clip: selectedClip, projectState: appState.projectState)
                                    }
                                    .overlay(alignment: .bottom) {
                                        // Caption Overlay - shows current caption at playhead position
                                        if let (caption, mediaTime) = currentCaption(for: selectedClip, at: appState.playbackState.currentTime) {
                                            CaptionOverlayView(
                                                caption: caption,
                                                currentTime: mediaTime,
                                                style: appState.projectState.currentProject?.captionStyle ?? .classic,
                                                offset: .constant(.zero)
                                            )
                                            .padding(.bottom, 60) // Above control bar
                                        }
                                    }
                                    .aspectRatio(16 / 9, contentMode: .fit)
                                    .frame(maxWidth: geometry.size.width, maxHeight: geometry.size.height)
                                    .shadow(color: .black.opacity(0.5), radius: 10)

                                // Control Bar Overlay
                                VStack {
                                    Spacer()
                                    PlayerControlBar(
                                        playbackState: appState.playbackState,
                                        projectState: appState.projectState
                                    )
                                    .padding(.bottom, 8)
                                }
                            } else {
                                VStack(spacing: 12) {
                                    Image(systemName: "film")
                                        .font(.system(size: 40))
                                        .foregroundStyle(.tertiary)
                                    Text(String(localized: "editor.no_project", defaultValue: "No Project Loaded"))
                                        .font(.headline)
                                        .foregroundColor(.gray)
                                }
                            }
                        }
                    }
                    .frame(minHeight: 200)

                    // Timeline
                    SaneTimelineView(
                        selectedClip: $selectedClip,
                        selectedClipIds: $selectedClipIds
                    )
                    .frame(minHeight: 180)
                }
                .frame(minWidth: 400, maxWidth: .infinity, maxHeight: .infinity)

                Divider()

                // Inspector Toggle Button
                CollapseButton(isCollapsed: $isInspectorCollapsed, edge: .trailing)
                    .accessibilityIdentifier("InspectorToggle")

                // RIGHT: Inspector (Collapsible)
                if !isInspectorCollapsed {
                    StylesInspectorView(selectedClip: $selectedClip)
                        .frame(minWidth: 200, idealWidth: 280, maxWidth: 350)
                        .transition(.move(edge: .trailing).combined(with: .opacity))
                }
            }
            .animation(.easeInOut(duration: 0.2), value: isSidebarCollapsed)
            .animation(.easeInOut(duration: 0.2), value: isInspectorCollapsed)
        }
        .onReceive(NotificationCenter.default.publisher(for: NSNotification.Name("ToggleSidebar"))) { _ in
            withAnimation { isSidebarCollapsed.toggle() }
        }
        .onReceive(NotificationCenter.default.publisher(for: NSNotification.Name("ToggleInspector"))) { _ in
            withAnimation { isInspectorCollapsed.toggle() }
        }
        .background(
            LinearGradient(
                colors: [Color(white: 0.02), Color(white: 0.05)],
                startPoint: .top,
                endPoint: .bottom
            )
        )
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
