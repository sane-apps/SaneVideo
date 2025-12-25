//
//  PlayerControlBar.swift
//  SaneVideo
//
//  Created by SaneVideo Refactor
//

import AppKit
import AVFoundation
import SwiftUI

struct PlayerControlBar: View {
    var playbackState: PlaybackState
    var projectState: ProjectState

    var body: some View {
        HStack {
            // Left: Timecode
            HStack(spacing: 4) {
                Text(timecodeString(from: playbackState.currentTime))
                    .foregroundColor(.white)
                    .fontWeight(.medium)
                Text("/")
                    .foregroundColor(.gray)
                Text(timecodeString(from: projectState.currentProject?.timeline.duration ?? .zero))
                    .foregroundColor(.gray)
            }
            .font(.system(size: 11, design: .monospaced))

            Spacer()

            // Center: Play/Pause with contextual hints
            HStack(spacing: 16) {
                // Step backward button
                Button(action: { playbackState.stepBackward() }, label: {
                    Image(systemName: "backward.frame.fill")
                        .font(.system(size: 14))
                        .foregroundColor(.white.opacity(0.8))
                })
                .buttonStyle(.plain)
                .hoverScale(1.15)
                .pressScale()
                .help(String(localized: "player.help.step_backward", defaultValue: "Previous frame (←)"))
                .accessibilityIdentifier("player.step_backward")

                // Play/Pause Button (main control)
                Button(
                    action: { playbackState.togglePlayPause() },
                    label: {
                        Image(systemName: playbackState.isPlaying ? "pause.fill" : "play.fill")
                            .font(.system(size: 20))
                            .foregroundColor(.white)
                            .frame(width: 36, height: 36)
                            .background(Color.white.opacity(0.1), in: Circle())
                    }
                )
                .buttonStyle(.plain)
                .hoverScale(1.2)
                .pressScale()
                .animation(.smoothUI, value: playbackState.isPlaying)
                .keyboardShortcut(.space, modifiers: [])
                .disabled(projectState.currentProject?.timeline.tracks.allSatisfy { $0.clips.isEmpty } ?? true)
                .help(String(localized: "player.help.play_pause", defaultValue: "Play/Pause (Space) • J/K/L for shuttle control"))
                .accessibilityIdentifier("player.toggle_play_pause")

                // Step forward button
                Button(action: { playbackState.stepForward() }, label: {
                    Image(systemName: "forward.frame.fill")
                        .font(.system(size: 14))
                        .foregroundColor(.white.opacity(0.8))
                })
                .buttonStyle(.plain)
                .hoverScale(1.15)
                .pressScale()
                .help(String(localized: "player.help.step_forward", defaultValue: "Next frame (→)"))
                .accessibilityIdentifier("player.step_forward")
            }

            Spacer()

            // Right: Balance the layout (same width as left timecode)
            HStack(spacing: 4) {
                Text(timecodeString(from: projectState.currentProject?.timeline.duration ?? .zero))
                    .foregroundColor(.clear) // Invisible but takes space
                Text("/")
                    .foregroundColor(.clear)
                Text(timecodeString(from: .zero))
                    .foregroundColor(.clear)
            }
            .font(.system(size: 11, design: .monospaced))
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .background(.ultraThinMaterial, in: Capsule())
        .padding(.bottom, 20)
        .padding(.horizontal, 24)
        .frame(maxWidth: .infinity) // Responsive width
    }

    // Helper for Visual Effect (since SwiftUI Material is limited on older macOS or specific looks)
    struct VisualEffectView: NSViewRepresentable {
        let material: NSVisualEffectView.Material
        let blendingMode: NSVisualEffectView.BlendingMode

        func makeNSView(context _: Context) -> NSVisualEffectView {
            let view = NSVisualEffectView()
            view.material = material
            view.blendingMode = blendingMode
            view.state = .active
            return view
        }

        func updateNSView(_ nsView: NSVisualEffectView, context _: Context) {
            nsView.material = material
            nsView.blendingMode = blendingMode
        }
    }

    private func timecodeString(from time: CMTime) -> String {
        let totalSeconds = Int(time.seconds)
        let hours = totalSeconds / 3600
        let minutes = (totalSeconds % 3600) / 60
        let seconds = totalSeconds % 60
        let frames = Int((time.seconds - Double(totalSeconds)) * 30) // Assuming 30fps
        return String(format: "%02d:%02d:%02d:%02d", hours, minutes, seconds, frames)
    }
}
