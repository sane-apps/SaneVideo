//
//  RecordingControlsView.swift
//  SaneVideo
//
//  Created by SaneVideo Refactor
//

import SwiftUI

struct RecordingControlsView: View {
    @Environment(AppState.self) var appState

    var body: some View {
        @Bindable var recordingState = appState.recordingState
        return HStack(spacing: 12) {
            // Record/Stop Button
            RecordButton(isRecording: $recordingState.isRecording) {
                appState.toggleRecording()
            }
            // Removed fixed width 60

            Divider()
                .frame(height: 40)

            // Pause/Resume Button
            IconCircleButton(
                systemName: appState.isPaused ? "play.fill" : "pause.fill",
                isActive: true,
                size: .small,
                helpText: appState.isPaused ? "Resume Recording" : "Pause Recording"
            ) {
                appState.togglePause()
            }
            .disabled(!appState.isRecording)
            .accessibilityIdentifier("PauseRecordingButton")

            Divider()
                .frame(height: 40)

            // Screen Share Toggle
            IconCircleButton(
                systemName: "rectangle.inset.filled",
                isActive: appState.isScreenSharing,
                size: .small,
                helpText: appState.isScreenSharing ? "Stop Screen Share" : "Share Screen"
            ) {
                appState.toggleScreenShare()
            }
            .accessibilityIdentifier("ScreenShareToggle")

            // Camera Toggle
            IconCircleButton(
                systemName: "video.fill",
                isActive: appState.cameraState.isActive,
                size: .small,
                helpText: appState.cameraState.isActive ? "Turn Camera Off" : "Turn Camera On"
            ) {
                appState.toggleCamera()
            }
            .accessibilityIdentifier("CameraToggle")

            // Mic Toggle
            IconCircleButton(
                systemName: appState.isMicActive ? "mic.fill" : "mic.slash.fill",
                isActive: appState.isMicActive,
                size: .small,
                helpText: appState.isMicActive ? "Mute Microphone" : "Unmute Microphone"
            ) {
                appState.toggleMic()
            }
            .accessibilityIdentifier("MicToggle")

            Divider()
                .frame(height: 40)

            // Timer + Live Indicator
            RecBadgeTimer(isRecording: appState.isRecording, timeString: timeString(from: appState.recordingDuration))
                .padding(.horizontal, 8)
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 16)
        .premiumGlass(radius: 16) // Enhanced liquid glass
    }

    private func timeString(from duration: TimeInterval) -> String {
        let hours = Int(duration) / 3600
        let minutes = (Int(duration) % 3600) / 60
        let seconds = Int(duration) % 60

        if hours > 0 {
            return String(format: "%d:%02d:%02d", hours, minutes, seconds)
        } else {
            return String(format: "%02d:%02d", minutes, seconds)
        }
    }
}
