//
//  TimelineControls.swift
//  SaneVideo
//
//  Extracted from TimelineView.swift
//  Contains timeline toolbar controls and Magic Fix components
//

import AVFoundation
import SwiftUI

// MARK: - Timeline Controls

struct TimelineControls: View {
    @Binding var zoomLevel: CGFloat
    @Binding var showLogs: Bool
    @Binding var magicOptions: MagicFixOptions
    let selectedClip: VideoClip?
    var playbackState: PlaybackState
    var projectState: ProjectState
    let onSplit: () -> Void

    @AppStorage("snapEnabled") private var snapEnabled = true
    @AppStorage("magneticTimeline") private var magneticTimeline = true

    var body: some View {
        HStack(spacing: 0) {
            // LEFT: Playhead Position (Timecode)
            HStack(spacing: 12) {
                Image(systemName: "clock")
                    .foregroundColor(.secondary)
                    .font(.system(size: 11))
                Text(timecodeString(from: playbackState.currentTime))
                    .font(.system(size: 13, weight: .medium, design: .monospaced))
                    .foregroundColor(.white)
            }
            .frame(width: 140, alignment: .leading)
            .padding(.leading, 16)

            Spacer()

            // Tool Switcher
            HStack(spacing: 8) {
                ToolButton(icon: "cursorarrow", isSelected: true, id: "SelectClipButton") {
                    // Selection is default
                }
                .help(KeyboardShortcutHelper.helpWithShortcut(String(localized: "timeline.tool.select", defaultValue: "Select Tool"), key: "a", modifiers: []))

                ToolButton(icon: "scissors", isSelected: false, id: "SplitClipButton") {
                    onSplit()
                }
                .disabled(selectedClip == nil || projectState.isProcessing)
                .help(KeyboardShortcutHelper.helpWithShortcut(String(localized: "timeline.tool.split.help", defaultValue: "Split clip (B)"), key: "b", modifiers: [.command]))

                ToolButton(icon: "trash", isSelected: false, id: "DeleteClipButton") {
                    if let clip = selectedClip {
                        projectState.deleteClip(clip)
                    }
                }
                .disabled(selectedClip == nil || projectState.isProcessing)
                .help(KeyboardShortcutHelper.helpWithShortcut(String(localized: "timeline.tool.delete.help", defaultValue: "Delete selection"), key: .delete))
            }
            .padding(4)
            .background(Color.white.opacity(0.05))
            .cornerRadius(8)

            Spacer()

            // RIGHT: View Controls
            HStack(spacing: 20) {
                // Snap
                Button(action: { snapEnabled.toggle() }, label: {
                    Image(systemName: "bolt.fill")
                        .foregroundColor(snapEnabled ? .purple : .secondary)
                        .font(.system(size: 13))
                        .opacity(snapEnabled ? 1.0 : 0.7)
                })
                .buttonStyle(.plain)
                .help(KeyboardShortcutHelper.helpWithShortcut(String(localized: "timeline.help.snap", defaultValue: "Toggle Snapping"), key: "n", modifiers: []))
                .accessibilityIdentifier("timeline.toggle_snap")

                // Magnetic
                Button(action: { magneticTimeline.toggle() }, label: {
                    Image(systemName: magneticTimeline ? "arrow.left.to.line.compact" : "arrow.left.to.line")
                        .foregroundColor(magneticTimeline ? .purple : .secondary)
                        .font(.system(size: 13))
                })
                .buttonStyle(.plain)
                .help(KeyboardShortcutHelper.helpWithShortcut(String(localized: "timeline.help.magnetic", defaultValue: "Magnetic Timeline"), key: "m", modifiers: []))
                .accessibilityIdentifier("timeline.toggle_magnetic")

                // Zoom
                HStack(spacing: 8) {
                    Image(systemName: "minus.magnifyingglass")
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                    
                    Slider(value: $zoomLevel, in: 0.1 ... 5.0, step: 0.1)
                        .frame(width: 80)
                        .tint(.purple)
                        .accessibilityIdentifier("timeline.zoom_slider")
                    
                    Image(systemName: "plus.magnifyingglass")
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                }
            }
            .padding(.trailing, 16)
        }
        .frame(height: 38)
        .background(Color(white: 0.08))
        .overlay(Divider().opacity(0.1), alignment: .bottom)
        .zIndex(100)
    }

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
                .font(.system(size: 13, weight: .medium))
                .frame(width: 32, height: 32)
                .background(isSelected ? Color.purple.opacity(0.2) : Color.clear)
                .foregroundColor(isSelected ? .purple : .white)
                .cornerRadius(6)
        }
        .buttonStyle(.plain)
        .contentShape(Rectangle())
        .accessibilityIdentifier(id)
    }
}
