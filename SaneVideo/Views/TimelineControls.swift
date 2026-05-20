//
//  TimelineControls.swift
//  SaneVideo
//
//  Unified toolbar with playback, editing, and timeline controls
//  Consolidates PlayerControlBar and TimelineControls into one bar
//

import AVFoundation
import SwiftUI

// MARK: - Timeline Controls (Unified Toolbar)

struct TimelineControls: View {
    @Binding var zoomLevel: CGFloat
    @Binding var showLogs: Bool
    @Binding var magicOptions: MagicFixOptions
    let selectedClip: VideoClip?
    var playbackState: PlaybackState
    var projectState: ProjectState
    let onSplit: () -> Void

    @Environment(\.undoManager) private var undoManager

    @AppStorage("snapEnabled") private var snapEnabled = true
    @AppStorage("magneticTimeline") private var magneticTimeline = true
    @AppStorage("editor.videoDisplayMode") private var displayMode: VideoDisplayMode = .fit
    @AppStorage("editor.playbackSpeed") private var playbackSpeed: Double = 1.0

    // Volume state (0.0 to 1.0)
    @State private var volume: Float = 1.0
    @State private var isMuted: Bool = false

    // State for delete confirmation
    @State private var showDeleteConfirmation = false

    var body: some View {
        HStack(spacing: 0) {
            // LEFT: Undo/Redo + Timecode
            HStack(spacing: 12) {
                undoRedoSection
                timecodeSection
            }
            .frame(minWidth: 220, alignment: .leading)
            .padding(.leading, 12)

            Spacer()

            // CENTER-LEFT: Playback Controls + Speed
            HStack(spacing: 8) {
                playbackSection
                speedControl
            }

            Spacer()

            // CENTER: Volume + Editing Tools
            HStack(spacing: 12) {
                volumeControl
                editingSection
            }

            Spacer()

            // CENTER-RIGHT: Timeline Controls (snap, magnetic, zoom)
            timelineSection

            // RIGHT: Display Mode Toggle
            displayModeToggle
                .padding(.trailing, 12)
        }
        .frame(height: 42)
        .background(SaneVideoEditorPanelBackground(emphasized: true))
        .overlay(Divider(), alignment: .bottom)
        .zIndex(100)
        .onAppear {
            // Sync volume with player
            if let player = playbackState.player {
                volume = player.volume
                isMuted = player.isMuted
            }
        }
    }

    // MARK: - Undo/Redo Section

    private var undoRedoSection: some View {
        HStack(spacing: 4) {
            Button(
                action: { undoManager?.undo() },
                label: {
                    Image(systemName: "arrow.uturn.backward")
                        .font(.system(size: 12))
                        .foregroundColor(undoManager?.canUndo == true ? .accentColor : Color.stone.opacity(0.5))
                }
            )
            .buttonStyle(.plain)
            .disabled(!(undoManager?.canUndo ?? false))
            .help("Undo (⌘Z)")
            .accessibilityIdentifier("toolbar.undo")
            .accessibilityLabel("Undo")

            Button(
                action: { undoManager?.redo() },
                label: {
                    Image(systemName: "arrow.uturn.forward")
                        .font(.system(size: 12))
                        .foregroundColor(undoManager?.canRedo == true ? .accentColor : Color.stone.opacity(0.5))
                }
            )
            .buttonStyle(.plain)
            .disabled(!(undoManager?.canRedo ?? false))
            .help("Redo (⌘⇧Z)")
            .accessibilityIdentifier("toolbar.redo")
            .accessibilityLabel("Redo")
        }
    }

    // MARK: - Timecode Section

    private var timecodeSection: some View {
        HStack(spacing: 4) {
            Text(timecodeString(from: playbackState.currentTime))
                .foregroundColor(.primary)
                .fontWeight(.medium)
            Text("/")
                .foregroundColor(Color.stone)
            Text(timecodeString(from: projectState.currentProject?.timeline.duration ?? .zero))
                .foregroundColor(Color.stone)
        }
        .font(.system(size: 11, design: .monospaced))
    }

    // MARK: - Playback Section

    private var playbackSection: some View {
        HStack(spacing: 10) {
            // Step backward
            Button(
                action: { playbackState.stepBackward() },
                label: {
                    Image(systemName: "backward.frame.fill")
                        .font(.system(size: 12))
                        .foregroundColor(.accentColor)
                }
            )
            .buttonStyle(.plain)
            .hoverScale(1.15)
            .pressScale()
            .help("Previous frame (←)")
            .accessibilityIdentifier("player.step_backward")
            .accessibilityLabel("Previous frame")

            // Play/Pause
            Button(
                action: { playbackState.togglePlayPause() },
                label: {
                    Image(systemName: playbackState.isPlaying ? "pause.fill" : "play.fill")
                        .font(.system(size: 14))
                        .foregroundColor(.accentColor)
                        .frame(width: 28, height: 28)
                        .background(Color.accentColor.opacity(0.15), in: Circle())
                }
            )
            .buttonStyle(.plain)
            .hoverScale(1.15)
            .pressScale()
            .animation(.smoothUI, value: playbackState.isPlaying)
            .disabled(projectState.currentProject?.timeline.tracks.allSatisfy(\.clips.isEmpty) ?? true)
            .help("Play/Pause (Space)")
            .accessibilityIdentifier("player.toggle_play_pause")
            .accessibilityLabel(playbackState.isPlaying ? "Pause" : "Play")

            // Step forward
            Button(
                action: { playbackState.stepForward() },
                label: {
                    Image(systemName: "forward.frame.fill")
                        .font(.system(size: 12))
                        .foregroundColor(.accentColor)
                }
            )
            .buttonStyle(.plain)
            .hoverScale(1.15)
            .pressScale()
            .help("Next frame (→)")
            .accessibilityIdentifier("player.step_forward")
            .accessibilityLabel("Next frame")
        }
    }

    // MARK: - Speed Control

    private var speedControl: some View {
        Menu(
            content: {
                ForEach([0.25, 0.5, 0.75, 1.0, 1.25, 1.5, 2.0], id: \.self) { speed in
                    Button(
                        action: {
                            playbackSpeed = speed
                            playbackState.setPlaybackRate(Float(speed))
                        },
                        label: {
                            HStack {
                                Text("\(speed, specifier: speed == 1.0 ? "%.0f" : "%.2f")x")
                                if playbackSpeed == speed {
                                    Image(systemName: "checkmark")
                                }
                            }
                        }
                    )
                }
            },
            label: {
                Text("\(playbackSpeed, specifier: playbackSpeed == 1.0 ? "%.0f" : "%.1f")x")
                    .font(.system(size: 10, weight: .medium, design: .monospaced))
                    .foregroundColor(Color.stone)
                    .frame(width: 32)
            }
        )
        .menuStyle(.borderlessButton)
        .help("Playback Speed")
        .accessibilityIdentifier("player.speed")
    }

    // MARK: - Volume Control

    private var volumeControl: some View {
        HStack(spacing: 4) {
            Button(
                action: {
                    isMuted.toggle()
                    playbackState.player?.isMuted = isMuted
                },
                label: {
                    Image(systemName: isMuted || volume == 0 ? "speaker.slash.fill" : volumeIcon)
                        .font(.system(size: 11))
                        .foregroundColor(isMuted ? Color.stone : .accentColor)
                        .frame(width: 20)
                }
            )
            .buttonStyle(.plain)
            .help(isMuted ? "Unmute" : "Mute")
            .accessibilityIdentifier("player.mute")
            .accessibilityLabel(isMuted ? "Unmute audio" : "Mute audio")

            Slider(value: $volume, in: 0 ... 1) { _ in
                playbackState.player?.volume = volume
                if volume > 0, isMuted {
                    isMuted = false
                    playbackState.player?.isMuted = false
                }
            }
            .frame(width: 50)
            .tint(.accentColor)
            .accessibilityIdentifier("player.volume")
            .accessibilityLabel("Volume")
        }
    }

    private var volumeIcon: String {
        if volume > 0.66 {
            "speaker.wave.3.fill"
        } else if volume > 0.33 {
            "speaker.wave.2.fill"
        } else if volume > 0 {
            "speaker.wave.1.fill"
        } else {
            "speaker.slash.fill"
        }
    }

    // MARK: - Editing Section

    private var editingSection: some View {
        HStack(spacing: 6) {
            // Rotate (only when clip selected and not missing)
            if let clip = selectedClip, !clip.isMissing {
                ToolButton(icon: "arrow.triangle.2.circlepath", isSelected: false, id: "player.rotate") {
                    projectState.rotateClip(clip)
                    ServiceContainer.shared.hapticsManager.impact()
                }
                .help("Rotate 90° (R)")
                .accessibilityLabel("Rotate clip 90 degrees")
            }

            // Split
            ToolButton(icon: "scissors", isSelected: false, id: "SplitClipButton") {
                onSplit()
            }
            .disabled(selectedClip == nil || projectState.isProcessing)
            .help("Split clip (⌘B)")
            .accessibilityLabel("Split clip at playhead")

            // Delete
            ToolButton(icon: "trash", isSelected: false, id: "DeleteClipButton") {
                if selectedClip != nil {
                    showDeleteConfirmation = true
                }
            }
            .disabled(selectedClip == nil || projectState.isProcessing)
            .help("Delete (⌫)")
            .confirmationDialog("Delete Clip?", isPresented: $showDeleteConfirmation, presenting: selectedClip) { clip in
                Button("Remove from Project", role: .destructive) {
                    projectState.deleteClip(clip)
                }
                Button("Move to Trash", role: .destructive) {
                    projectState.deleteClipFile(clip)
                }
                Button("Cancel", role: .cancel) {}
            } message: { clip in
                Text("Remove '\(clip.url.lastPathComponent)' from project or move file to Trash?")
            }
        }
        // 2025-12-31: Removed .subtleGlass for consistent toolbar styling
        // All toolbar icons now have uniform appearance (no special containers)
    }

    // MARK: - Timeline Section

    private var timelineSection: some View {
        HStack(spacing: 14) {
            // Snap Toggle
            Button(
                action: { snapEnabled.toggle() },
                label: {
                    Image(systemName: "bolt.fill")
                        .foregroundColor(snapEnabled ? .accentColor : Color.stone)
                        .font(.system(size: 11))
                        .opacity(snapEnabled ? 1.0 : 0.6)
                }
            )
            .buttonStyle(.plain)
            .hoverScale(1.15)
            .animation(.smoothUI, value: snapEnabled)
            .help("Snap (N): \(snapEnabled ? "On" : "Off")")
            .accessibilityIdentifier("timeline.toggle_snap")
            .accessibilityLabel("Snap to edges, \(snapEnabled ? "on" : "off")")

            // Magnetic Toggle
            Button(
                action: { magneticTimeline.toggle() },
                label: {
                    Image(systemName: magneticTimeline ? "arrow.left.to.line.compact" : "arrow.left.to.line")
                        .foregroundColor(magneticTimeline ? .accentColor : Color.stone)
                        .font(.system(size: 11))
                }
            )
            .buttonStyle(.plain)
            .hoverScale(1.15)
            .animation(.smoothUI, value: magneticTimeline)
            .help("Magnetic (M): \(magneticTimeline ? "On" : "Off")")
            .accessibilityIdentifier("timeline.toggle_magnetic")
            .accessibilityLabel("Magnetic timeline, \(magneticTimeline ? "on" : "off")")

            // Zoom Slider
            HStack(spacing: 4) {
                Image(systemName: "minus.magnifyingglass")
                    .font(.system(size: 9))
                    .foregroundColor(Color.stone)

                Slider(value: $zoomLevel, in: TimelineZoomCalculator.minimumZoom ... TimelineZoomCalculator.maximumZoom, step: 0.01)
                    .frame(width: 60)
                    .tint(.accentColor)
                    .accessibilityIdentifier("timeline.zoom_slider")
                    .accessibilityLabel("Timeline zoom")

                Image(systemName: "plus.magnifyingglass")
                    .font(.system(size: 9))
                    .foregroundColor(Color.stone)
            }
        }
    }

    // MARK: - Display Mode Toggle

    private var displayModeToggle: some View {
        Button(
            action: {
                // Cycle through modes: Fit → Fill → Actual → Fit
                withAnimation(.easeInOut(duration: 0.15)) {
                    switch displayMode {
                    case .fit: displayMode = .fill
                    case .fill: displayMode = .actual
                    case .actual: displayMode = .fit
                    }
                }
            },
            label: {
                Image(systemName: displayMode.icon)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(.accentColor)
                    .frame(width: 26, height: 26)
                    .background(Color.accentColor.opacity(0.1))
                    .cornerRadius(6)
            }
        )
        .buttonStyle(.plain)
        .hoverScale(1.1)
        .help("Display: \(displayMode.label) (click to cycle)")
        .accessibilityIdentifier("player.displayMode.toggle")
        .accessibilityLabel("Display mode: \(displayMode.label)")
    }

    // MARK: - Helpers

    private func timecodeString(from time: CMTime) -> String {
        let totalSeconds = Int(time.seconds)
        let hours = totalSeconds / 3600
        let minutes = (totalSeconds % 3600) / 60
        let seconds = totalSeconds % 60
        let frames = Int((time.seconds - Double(totalSeconds)) * 30)
        return String(format: "%02d:%02d:%02d:%02d", hours, minutes, seconds, frames)
    }
}

// MARK: - Tool Button

struct ToolButton: View {
    let icon: String
    let isSelected: Bool
    let id: String
    let action: () -> Void

    init(icon: String, isSelected: Bool, id: String, action: @escaping () -> Void) {
        self.icon = icon
        self.isSelected = isSelected
        self.id = id
        self.action = action
    }

    var body: some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: 11, weight: .medium))
                .frame(width: 26, height: 26)
                .background(isSelected ? Color.accentColor.opacity(0.15) : Color.clear)
                .foregroundColor(isSelected ? .accentColor : .primary)
                .cornerRadius(6)
        }
        .buttonStyle(.plain)
        .contentShape(Rectangle())
        .hoverScale(1.1)
        .pressScale()
        .simultaneousGesture(
            TapGesture().onEnded {
                ServiceContainer.shared.hapticsManager.selection()
            }
        )
        .animation(.smoothUI, value: isSelected)
        .accessibilityIdentifier(id)
    }
}
