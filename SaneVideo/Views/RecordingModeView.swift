//
//  RecordingModeView.swift
//  SaneVideo
//
//  Created by SaneVideo Refactor
//

import AVFoundation
import SwiftUI

struct RecordingModeView: View {
    @Environment(AppState.self) var appState

    var body: some View {
        ZStack {
            // 1. Main Preview Area (Full Screen)
            Color.black.ignoresSafeArea()

            if appState.isScreenSharing {
                if let screenLayer = appState.screenPreviewLayer {
                    ScreenPreviewView(previewLayer: screenLayer)
                        .aspectRatio(16 / 9, contentMode: .fit)
                        .edgesIgnoringSafeArea(.all)
                } else {
                    VStack {
                        ProgressView()
                        Text("Initializing Screen Share...")
                            .foregroundColor(.white)
                            .padding(.top)
                    }
                }
            } else {
                // Camera Preview
                if appState.cameraEnabled && appState.cameraState.isActive, let session = appState.cameraState.session {
                    CameraPreviewView(session: session)
                        .aspectRatio(16 / 9, contentMode: .fit)
                        .edgesIgnoringSafeArea(.all)
                } else if appState.cameraEnabled {
                    // Camera Loading State (enabled but not yet active)
                    VStack(spacing: 16) {
                        ProgressView()
                            .scaleEffect(1.5)
                        Text("Camera Loading...")
                            .font(.title2)
                            .foregroundColor(.gray)
                    }
                } else {
                    // Camera Off State (user hasn't enabled it)
                    VStack(spacing: 20) {
                        Image(systemName: "video.slash")
                            .font(.system(size: 80))
                            .foregroundColor(.gray)
                        Text("Camera is Off")
                            .font(.title)
                            .foregroundColor(.gray)
                        Button("Turn On Camera") {
                            appState.cameraEnabled = true
                            appState.cameraState.startCamera()
                        }
                        .buttonStyle(.borderedProminent)
                        .controlSize(.large)
                        .accessibilityLabel("Turn on camera")
                        .accessibilityHint("Enables the camera for recording")
                        .help("Turn on the camera to start recording")
                    }
                }
            }

            // 2. Bottom Control Bar
            VStack {
                Spacer()

                ZStack {
                    // 1. Center: Recording Controls (Centered in Screen)
                    HStack(spacing: 30) {
                        // Mic Toggle
                        Button(action: {
                            ServiceContainer.shared.hapticsManager.selection()
                            appState.toggleMic()
                        }, label: {
                            ZStack {
                                // Audio visualizer ring - behind the button
                                if appState.isMicActive {
                                    AudioVisualizerView(audioLevelPublisher: appState.cameraState.audioLevelPublisher, size: 68)
                                }

                                // Icon
                                Image(systemName: appState.isMicActive ? "mic.fill" : "mic.slash.fill")
                            }
                        })
                        .buttonStyle(IconButtonStyle(size: .medium, isActive: appState.isMicActive, activeColor: appState.isMicActive ? Theme.Colors.action : Theme.Colors.destructive))
                        .accessibilityLabel(appState.isMicActive ? "Mute Microphone" : "Unmute Microphone")
                        .accessibilityIdentifier("MicToggle")
                        .help(appState.isMicActive ? "Mute Microphone" : "Unmute Microphone")

                        // Screen Share Toggle
                        Button(action: {
                            ServiceContainer.shared.hapticsManager.selection()
                            appState.toggleScreenShare()
                        }, label: {
                            Image(systemName: appState.isScreenSharing ? "camera.fill" : "display")
                        })
                        .buttonStyle(IconButtonStyle(size: .large, isActive: appState.isScreenSharing, activeColor: Theme.Colors.action))
                        .accessibilityLabel(appState.isScreenSharing ? "Switch to camera" : "Switch to screen recording")
                        .accessibilityIdentifier("ScreenShareToggle")
                        .help(appState.isScreenSharing ? "Switch back to camera mode" : "Record your screen")

                        // Device Selection Menu (Camera + Mic + Effects)
                        Menu {
                            // Camera Device Selection
                            Section("Camera") {
                                ForEach(appState.cameraState.availableCameras, id: \.uniqueID) { device in
                                    Button(action: {
                                        appState.cameraState.switchCamera(to: device)
                                    }, label: {
                                        HStack {
                                            Text(device.localizedName)
                                            if device.uniqueID == appState.cameraState.currentCameraID {
                                                Image(systemName: "checkmark")
                                            }
                                        }
                                    })
                                }

                                if appState.cameraState.availableCameras.isEmpty {
                                    Text("No cameras found")
                                        .foregroundColor(.secondary)
                                }
                            }
                            .onAppear {
                                // Lazy camera discovery - only query CMIO when user opens picker
                                appState.cameraState.ensureCamerasDiscovered()
                            }

                            Divider()

                            // Microphone Device Selection
                            Section("Microphone") {
                                ForEach(appState.audioService.availableMicrophones, id: \.uniqueID) { device in
                                    Button(action: {
                                        appState.audioService.switchMicrophone(to: device)
                                    }, label: {
                                        HStack {
                                            Text(device.localizedName)
                                            if device.uniqueID == appState.audioService.currentMicID {
                                                Image(systemName: "checkmark")
                                            }
                                        }
                                    })
                                }

                                if appState.audioService.availableMicrophones.isEmpty {
                                    Text("No microphones found")
                                        .foregroundColor(.secondary)
                                }
                            }
                            .onAppear {
                                // Lazy microphone discovery - only query when user opens picker
                                appState.audioService.ensureMicrophonesDiscovered()
                            }
                            .accessibilityIdentifier("MicrophoneSelectionMenu")

                            Divider()

                            // Tip about system camera effects
                            // Camera Effects Tip
                            if #available(macOS 12.0, *) {
                                Button(action: {}, label: {
                                    HStack {
                                        Text("Video Effects in Control Center")
                                        Image(systemName: "switch.2")
                                    }
                                })
                                .disabled(true)
                            } else {
                                Text("Use Control Center for Video Effects")
                                    .font(.caption)
                            }
                        } label: {
                            Image(systemName: "gearshape")
                        }
                        .menuStyle(.borderlessButton)
                        .frame(width: 44, height: 44)
                        .help("Camera & Microphone Selection")

                        // Main Record Button
                        UnifiedRecordButton(size: 72)
                            .accessibilityIdentifier("RecordButton")
                            .keyboardShortcut("r", modifiers: [.command])

                        // Pause Button (Visible when recording)
                        if appState.isRecording {
                            ToolButton(
                                icon: appState.isPaused ? "play.fill" : "pause.fill",
                                isSelected: false,
                                id: "PauseRecordingButton"
                            ) {
                                ServiceContainer.shared.hapticsManager.selection()
                                appState.togglePause()
                            }
                            .buttonStyle(IconButtonStyle(size: .large, isActive: true, activeColor: Theme.Colors.warning))
                            .accessibilityLabel(appState.isPaused ? "Resume recording" : "Pause recording")
                            .accessibilityIdentifier("PauseRecordingButton")
                            .help(KeyboardShortcutHelper.helpWithShortcut(appState.isPaused ? "Resume" : "Pause", key: " ", modifiers: []))
                        } else {
                            // Placeholder to keep layout balanced within the center group
                            Color.clear.frame(width: 75, height: 75)
                        }
                    }

                    // 2. Right: Gallery / Recent Clip
                    HStack {
                        Spacer()

                        if appState.recentlyAddedClip != nil {
                            Button(action: {
                                appState.switchToEditing()
                            }, label: {
                                VStack(spacing: 4) {
                                    Image(systemName: "photo.stack")
                                        .font(.system(size: 20))
                                    Text("Recent")
                                        .font(.caption)
                                        .fontWeight(.medium)
                                }
                                .foregroundColor(.white)
                                .frame(width: 60, height: 60)
                                .background(.ultraThinMaterial)
                                .clipShape(Circle())
                            })
                            .buttonStyle(.plain)
                            .buttonStyle(.plain)
                            .help("View Recent Clip")
                            .accessibilityIdentifier("RecentClipButton")
                            .padding(.trailing, 40)
                        }
                    }
                }
                .padding(.bottom, 40)
            }

            // 3. Top: Mode Switcher (Always Visible)
            VStack {
                ModeSwitcherView()
                    .padding(.top, 20)
                Spacer()
            }

            // Countdown Overlay
            if appState.recordingState.countdownValue > 0 {
                ZStack {
                    Color.black.opacity(0.4).ignoresSafeArea()
                    Text("\(appState.recordingState.countdownValue)")
                        .font(.system(size: 150, weight: .bold, design: .rounded))
                        .foregroundColor(.white)
                        .shadow(color: .black.opacity(0.5), radius: 10, x: 0, y: 5)
                }
            }
        }
        .onAppear {
            Task {
                print("🚀 RecordingModeView: onAppear")
                // Auto-start camera if not screen sharing
                if !appState.isScreenSharing && !appState.cameraState.isActive {
                    appState.cameraEnabled = true
                    appState.cameraState.startCamera()
                }
            }
        }
    }
}
