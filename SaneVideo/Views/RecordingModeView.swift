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
            // Dynamic Size Calculations - uses unified IconCircleButton.Size system
            let buttonScale = min(max(geo.size.width / 1000, 0.6), 1.2)
            // Use .medium as base (52pt) and scale from there
            let scaledButtonSize: CGFloat = IconCircleButton.Size.medium.diameter * buttonScale

            ZStack {
                // 1. Main Preview Area (Full Screen)
                Color.black.ignoresSafeArea()

                if appState.isScreenSharing {
                    if appState.screenPreviewLayer != nil {
                        // CRITICAL FIX: Prevent infinite visual feedback loop
                        // Instead of showing the live screen (which recursively captures itself),
                        // show a static "Recording in Progress" placeholder.
                        ZStack {
                            Color.black.opacity(0.8)
                            VStack(spacing: 20) {
                                Image(systemName: "display.2")
                                    .font(.system(size: 80))
                                    .foregroundStyle(Theme.Colors.accent)
                                    .symbolEffect(.pulse.byLayer, options: .repeating)

                                Text("Recording Screen")
                                    .font(.system(size: 32, weight: .bold))
                                    .foregroundColor(.white)

                                Text("Window minimized to prevent visual feedback")
                                    .font(.subheadline)
                                    .foregroundColor(.gray)
                            }
                        }
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
                                // cameraEnabled didSet automatically starts camera
                                appState.cameraEnabled = true
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

                // REC Timer Badge - Top Left (out of the way)
                if appState.isRecording {
                    VStack {
                        HStack {
                            RecBadgeTimer(
                                isRecording: appState.isRecording,
                                timeString: formatDuration(appState.recordingDuration)
                            )
                            .padding(.leading, Theme.Dimensions.paddingLG)
                            .padding(.top, Theme.Dimensions.paddingLG)
                            Spacer()
                        }
                        Spacer()
                    }
                }

                // 2. Bottom Control Bar (no timer - moved to top)
                VStack {
                    Spacer()
                    SharedRecordingControls(
                        showDevicePickers: true,
                        showGalleryTarget: false,  // Gallery button removed - not needed here
                        showTimer: false,  // Timer moved to top-left
                        useGlassBackground: false,
                        buttonSize: .custom(scaledButtonSize)
                    )
                    .padding(.bottom, Theme.Dimensions.spacingXXL * buttonScale)
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
                AppLogger.uiLog.debug("RecordingModeView: onAppear")
                // Auto-start camera if not screen sharing
                // cameraEnabled didSet automatically starts camera
                if !appState.isScreenSharing && !appState.cameraState.isActive {
                    appState.cameraEnabled = true
                }
            }
        }
    }

    private func formatDuration(_ duration: TimeInterval) -> String {
        TimeUtils.formatDuration(duration)
    }
}
