//
//  PiPControlsView.swift
//  SaneVideo
//
//  Overlay controls for the PiP camera window

import SwiftUI

struct PiPControlsView: View {
    @Environment(AppState.self) var appState
    @State private var isHovering = false

    var body: some View {
        HStack(spacing: 12) {
            // Mic Toggle (Always visible)
            ZStack {
                // Audio Visualizer Ring (Mirrors main UI)
                AudioVisualizerView(
                    audioLevelPublisher: appState.audioService.audioLevelSubject.eraseToAnyPublisher(),
                    size: 38 // Larger than button (28) to form a ring around it
                )
                
                Button(action: { appState.toggleMic() }, label: {
                    Image(systemName: appState.isMicActive ? "mic.fill" : "mic.slash.fill")
                        .foregroundColor(appState.isMicActive ? .white : .red)
                        .frame(width: 28, height: 28)
                        .background(Color.black.opacity(0.5))
                        .clipShape(Circle())
                })
                .buttonStyle(.plain)
                .help(appState.isMicActive ? String(localized: "pip.help.mic.mute", defaultValue: "Mute Microphone") : String(localized: "pip.help.mic.unmute", defaultValue: "Unmute Microphone"))
                .accessibilityIdentifier("MicToggle")
            }

            // Pause/Resume (Only visible when ACTIVE)
            if appState.isRecording {
                Button(action: { appState.togglePause() }, label: {
                    Image(systemName: appState.isPaused ? "play.fill" : "pause.fill")
                        .foregroundColor(.white)
                        .frame(width: 28, height: 28)
                        .background(Color.orange)
                        .clipShape(Circle())
                })
                .buttonStyle(.plain)
                .help(appState.isPaused ? String(localized: "pip.help.resume", defaultValue: "Resume") : String(localized: "pip.help.pause", defaultValue: "Pause"))
                .accessibilityIdentifier("PauseRecordingButton")
            }

            // Main Action Button (Record / Stop)
            UnifiedRecordButton(size: 32)
                .help(appState.isRecording ? String(localized: "pip.help.recording.stop", defaultValue: "Stop Recording") : String(localized: "pip.help.recording.start", defaultValue: "Start Recording"))

            // Return to App (Exit screen share mode)
            Button(action: {
                // Toggle screen share OFF - this will hide PiP and show app
                appState.toggleScreenShare()
            }, label: {
                Image(systemName: "arrow.uturn.backward.circle.fill")
                    .foregroundColor(.white)
                    .frame(width: 28, height: 28)
                    .background(Color.blue)
                    .clipShape(Circle())
            })
            .buttonStyle(.plain)
            .help(String(localized: "pip.help.return", defaultValue: "Stop Sharing & Return to App"))
            .accessibilityIdentifier("ScreenShareToggle")
        }
        .padding(Theme.Dimensions.padding)
        .background(Material.regular) // Glass background
        .cornerRadius(20) // Keep 20 for pill shape? Or standardize? Pill shape is usually height/2.
        // If height is dynamic, hard 20 is okay for pill, but Theme.Dimensions.cornerRadius (8) is too small.
        // Let's keep 20 for PiP Controller as it's a pill.
        // Wait, I should standardize if possible.
        // If I change it to 8, it looks like a box.
        // I'll LEAVE PiP as 20 (Special Case) or add `Theme.Dimensions.pillRadius`?
        // Let's add `Theme.Dimensions.pillRadius` later if needed. For now I will SKIP PiP to avoid breaking design intent (Pill).
        // Actually, I will Skip PiP 20 replacement.
        .opacity(isHovering ? 1.0 : 0.8)
        .onHover { hovering in
            withAnimation(.easeInOut(duration: 0.2)) {
                isHovering = hovering
            }
        }
    }
}
