//
//  PiPControlsView.swift
//  SaneVideo
//
//  Overlay controls for the PiP camera window
//  Styled to match main window RecordingControlsView for consistency

import SwiftUI

struct PiPControlsView: View {
    @Environment(AppState.self) var appState
    @State private var isHovering = false

    var body: some View {
        HStack(spacing: 12) {
            // Mic Toggle (Always visible)
            // Note: AudioVisualizerView removed to match main window styling
            // Main window doesn't show audio visualizer ring, so PiP shouldn't either
            IconCircleButton(
                systemName: appState.isMicActive ? "mic.fill" : "mic.slash.fill",
                isActive: appState.isMicActive,
                size: .small,
                helpText: appState.isMicActive ? String(localized: "pip.help.mic.mute", defaultValue: "Mute Microphone") : String(localized: "pip.help.mic.unmute", defaultValue: "Unmute Microphone")
            ) {
                appState.toggleMic()
            }
            .accessibilityIdentifier("MicToggle")

            // Pause/Resume (Only visible when recording)
            if appState.isRecording {
                IconCircleButton(
                    systemName: appState.isPaused ? "play.fill" : "pause.fill",
                    isActive: true,
                    size: .small,
                    helpText: appState.isPaused ? String(localized: "pip.help.resume", defaultValue: "Resume") : String(localized: "pip.help.pause", defaultValue: "Pause")
                ) {
                    appState.togglePause()
                }
                .accessibilityIdentifier("PauseRecordingButton")
            }

            // Main Action Button (Record / Stop)
            // Using UnifiedRecordButton for premium feel, but at smaller size for PiP
            UnifiedRecordButton(size: 44) // Smaller than main window (68) but still prominent
                .help(appState.isRecording ? String(localized: "pip.help.recording.stop", defaultValue: "Stop Recording") : String(localized: "pip.help.recording.start", defaultValue: "Start Recording"))

            // Return to App (Exit screen share mode)
            IconCircleButton(
                systemName: "arrow.uturn.backward.circle.fill",
                isActive: true,
                size: .small,
                helpText: String(localized: "pip.help.return", defaultValue: "Stop Sharing & Return to App")
            ) {
                appState.toggleScreenShare()
            }
            .accessibilityIdentifier("ScreenShareToggle")
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 16)
        .premiumGlass(radius: 16) // Enhanced liquid glass to match main window
        // Keep hover opacity effect for PiP (nice UX touch)
        .opacity(isHovering ? 1.0 : 0.85)
        .onHover { hovering in
            withAnimation(.easeInOut(duration: 0.2)) {
                isHovering = hovering
            }
        }
    }
}
