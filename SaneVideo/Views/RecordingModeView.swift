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
        GeometryReader { geo in
            // Dynamic Size Calculations
            let buttonScale = min(max(geo.size.width / 1000, 0.6), 1.2)
            let baseButtonSize: CGFloat = 48 * buttonScale
            let recordButtonSize: CGFloat = 72 * buttonScale
            
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
                        // Camera Loading State
                        VStack(spacing: 16) {
                            ProgressView().scaleEffect(1.5)
                            Text("Camera Loading...").font(.title2).foregroundColor(.gray)
                        }
                    } else {
                        // Camera Off State
                        VStack(spacing: 20) {
                            Image(systemName: "video.slash")
                                .font(.system(size: 80 * buttonScale))
                                .foregroundColor(.gray)
                            Text("Camera is Off")
                                .font(.system(size: 28 * buttonScale))
                                .foregroundColor(.gray)
                            Button("Turn On Camera") {
                                appState.cameraEnabled = true
                                appState.cameraState.startCamera()
                            }
                            .buttonStyle(.borderedProminent)
                            .controlSize(.large)
                            .hoverScale(1.05)
                            .smoothAppear()
                        }
                    }
                }

                // bottom gradients
                VStack {
                    Spacer()
                    LinearGradient(
                        colors: [.clear, .black.opacity(0.6)],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                    .frame(height: 150 * buttonScale)
                    .allowsHitTesting(false)
                }

                // 2. Bottom Control Bar
                VStack {
                    Spacer()

                    ZStack {
                        // 1. Center: Recording Controls (Centered in Screen)
                        HStack(spacing: 30 * buttonScale) {
                            // Mic Toggle
                            Button(action: {
                                ServiceContainer.shared.hapticsManager.selection()
                                appState.toggleMic()
                            }, label: {
                                ZStack {
                                    if appState.isMicActive {
                                        AudioVisualizerView(audioLevelPublisher: appState.cameraState.audioLevelPublisher, size: baseButtonSize + 20)
                                    }
                                    Image(systemName: appState.isMicActive ? "mic.fill" : "mic.slash.fill")
                                }
                            })
                            .buttonStyle(IconButtonStyle(size: .custom(baseButtonSize), isActive: appState.isMicActive, activeColor: Color.white.opacity(0.2)))
                            .help(appState.isMicActive ? "Mute Microphone" : "Unmute Microphone")

                            // Screen Share Toggle
                            Button(action: {
                                ServiceContainer.shared.hapticsManager.selection()
                                appState.toggleScreenShare()
                            }, label: {
                                Image(systemName: appState.isScreenSharing ? "camera.fill" : "display")
                            })
                            .buttonStyle(IconButtonStyle(size: .custom(baseButtonSize * 1.3), isActive: appState.isScreenSharing, activeColor: Theme.Colors.action)) // Slightly larger
                            .help(appState.isScreenSharing ? "Switch back to camera mode" : "Record your screen")

                            // Main Record Button
                            UnifiedRecordButton(size: recordButtonSize)
                                .keyboardShortcut("r", modifiers: [.command])

                            // Pause Button (or Placeholder)
                            if appState.isRecording {
                                ToolButton(
                                    icon: appState.isPaused ? "play.fill" : "pause.fill",
                                    isSelected: false,
                                    id: "PauseRecordingButton"
                                ) {
                                    ServiceContainer.shared.hapticsManager.selection()
                                    appState.togglePause()
                                }
                                .buttonStyle(IconButtonStyle(size: .custom(baseButtonSize * 1.3), isActive: true, activeColor: Theme.Colors.warning))
                                .help("Pause/Resume")
                            } else {
                                // Dynamic Placeholder
                                Color.clear.frame(width: baseButtonSize * 1.3, height: baseButtonSize * 1.3)
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
                                            .font(.system(size: 20 * buttonScale))
                                        Text("Recent")
                                            .font(.system(size: 10 * buttonScale))
                                            .fontWeight(.medium)
                                    }
                                    .foregroundColor(.white)
                                    .frame(width: 60 * buttonScale, height: 60 * buttonScale)
                                    .background(.ultraThinMaterial)
                                    .clipShape(Circle())
                                })
                                .buttonStyle(.plain)
                                .padding(.trailing, 40)
                            }
                        }
                        
                        // 3. Left: Device Selection (Moved from Center)
                        HStack {
                            // Device Selection Menu
                            Menu {
                                Section("Camera") {
                                    ForEach(appState.cameraState.availableCameras, id: \.uniqueID) { device in
                                        Button(action: { appState.cameraState.switchCamera(to: device) }, label: {
                                            HStack {
                                                Text(device.localizedName)
                                                if device.uniqueID == appState.cameraState.currentCameraID { Image(systemName: "checkmark") }
                                            }
                                        })
                                    }
                                }
                                Divider()
                                Section("Microphone") {
                                    ForEach(appState.audioService.availableMicrophones, id: \.uniqueID) { device in
                                        Button(action: { appState.audioService.switchMicrophone(to: device) }, label: {
                                            HStack {
                                                Text(device.localizedName)
                                                // Strict ID Match (Verified by AudioService)
                                                if device.uniqueID == appState.audioService.currentMicID { 
                                                    Image(systemName: "checkmark") 
                                                }
                                            }
                                        })
                                    }
                                }
                            } label: {
                                Image(systemName: "gearshape")
                                    .font(.system(size: baseButtonSize * 0.4)) // Scale icon
                            }
                            .menuStyle(.borderlessButton)
                            .frame(width: baseButtonSize, height: baseButtonSize)
                            .background(Circle().fill(Color.white.opacity(0.1)))
                            .help("Camera & Microphone Selection")
                            .padding(.leading, 40)
                            
                            Spacer()
                        }
                    }
                    .padding(.bottom, 40 * buttonScale)
                }

                // Countdown Overlay
                if appState.recordingState.countdownValue > 0 {
                    ZStack {
                        Color.black.opacity(0.4).ignoresSafeArea()
                        Text("\(appState.recordingState.countdownValue)")
                            .font(.system(size: 150 * buttonScale, weight: .bold, design: .rounded))
                            .foregroundColor(.white)
                            .shadow(color: .black.opacity(0.5), radius: 10, x: 0, y: 5)
                    }
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
