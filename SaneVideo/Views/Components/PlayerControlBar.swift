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
    @Binding var displayMode: VideoDisplayMode
    var selectedClip: VideoClip? // For quick actions like rotate

    var body: some View {
        HStack {
            // Left: Timecode
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

            Spacer()

            // Center: Play/Pause with contextual hints
            HStack(spacing: 16) {
                // Step backward button
                Button(action: { playbackState.stepBackward() }, label: {
                    Image(systemName: "backward.frame.fill")
                        .font(.system(size: 14))
                        .foregroundColor(.accentColor)
                })
                .buttonStyle(.plain)
                .hoverScale(1.15)
                .pressScale()
                .help(String(localized: "player.help.step_backward", defaultValue: "Previous frame (←)"))
                .accessibilityIdentifier("player.step_backward")
                .accessibilityLabel("Previous frame")

                // Play/Pause Button (main control)
                Button(
                    action: { playbackState.togglePlayPause() },
                    label: {
                        Image(systemName: playbackState.isPlaying ? "pause.fill" : "play.fill")
                            .font(.system(size: 20))
                            .foregroundColor(.accentColor)
                            .frame(width: 36, height: 36)
                            .background(Color.accentColor.opacity(0.15), in: Circle())
                    }
                )
                .buttonStyle(.plain)
                .hoverScale(1.2)
                .pressScale()
                .animation(.smoothUI, value: playbackState.isPlaying)
                .keyboardShortcut(.space, modifiers: [])
                .disabled(projectState.currentProject?.timeline.tracks.allSatisfy(\.clips.isEmpty) ?? true)
                .help(String(localized: "player.help.play_pause", defaultValue: "Play/Pause (Space) • J/K/L for shuttle control"))
                .accessibilityIdentifier("player.toggle_play_pause")
                .accessibilityLabel(playbackState.isPlaying ? "Pause" : "Play")

                // Step forward button
                Button(action: { playbackState.stepForward() }, label: {
                    Image(systemName: "forward.frame.fill")
                        .font(.system(size: 14))
                        .foregroundColor(.accentColor)
                })
                .buttonStyle(.plain)
                .hoverScale(1.15)
                .pressScale()
                .help(String(localized: "player.help.step_forward", defaultValue: "Next frame (→)"))
                .accessibilityIdentifier("player.step_forward")
                .accessibilityLabel("Next frame")
            }

            Spacer()

            // Right: Quick actions + Video display mode picker
            HStack(spacing: 12) {
                // CRITICAL FIX: Add common video editing controls (rotate, speed, volume)
                // Rotate button (most common action)
                if let clip = selectedClip, !clip.isMissing {
                    Button(action: {
                        projectState.rotateClip(clip)
                        ServiceContainer.shared.hapticsManager.impact()
                    }, label: {
                        Image(systemName: "arrow.triangle.2.circlepath")
                            .font(.system(size: 14, weight: .medium))
                            .foregroundColor(.accentColor)
                            .frame(width: 28, height: 24)
                            .background(Color.accentColor.opacity(0.1))
                            .cornerRadius(4)
                    })
                    .buttonStyle(.plain)
                    .hoverScale(1.1)
                    .help("Rotate 90° clockwise (R)")
                    .keyboardShortcut("r", modifiers: [])
                    .accessibilityIdentifier("player.rotate")
                    .accessibilityLabel("Rotate clip 90 degrees")
                }

                // Divider between quick actions and display modes
                if selectedClip != nil {
                    Divider()
                        .frame(height: 16)
                }

                // Video display mode picker
                HStack(spacing: 2) {
                    ForEach(VideoDisplayMode.allCases, id: \.self) { mode in
                        Button(action: {
                            withAnimation(.easeInOut(duration: 0.15)) {
                                displayMode = mode
                            }
                        }, label: {
                            Image(systemName: mode.icon)
                                .font(.system(size: 12, weight: .medium))
                                .foregroundColor(displayMode == mode ? .white : .accentColor)
                                .frame(width: 28, height: 24)
                                .background(
                                    displayMode == mode
                                        ? Color.accentColor
                                        : Color.accentColor.opacity(0.1)
                                )
                                .cornerRadius(4)
                        })
                        .buttonStyle(.plain)
                        .help(mode.label)
                        .accessibilityIdentifier("player.displayMode.\(mode.rawValue)")
                        .accessibilityLabel("Display mode: \(mode.label)")
                    }
                }
                .padding(3)
                .background(Color.primary.opacity(0.05), in: RoundedRectangle(cornerRadius: 8))
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(.regularMaterial, in: Capsule())
        .shadow(color: .black.opacity(0.15), radius: 8, y: 2)
        .padding(.bottom, 16)
        .padding(.horizontal, 20)
        .frame(maxWidth: .infinity)
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

        // CRITICAL FIX: Proper cleanup to prevent use-after-free during autorelease
        static func dismantleNSView(_ nsView: NSVisualEffectView, coordinator _: ()) {
            nsView.state = .inactive
            nsView.removeFromSuperview()
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
