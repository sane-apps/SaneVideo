//
//  RecordingModeView.swift
//  SaneVideo
//
//  Created by SaneVideo Refactor
//

import AVFoundation
import SaneUI
import SwiftUI

struct RecordingModeView: View {
    @Environment(AppState.self) var appState

    var body: some View {
        GeometryReader { geo in
            // Dynamic Size Calculations - uses unified IconCircleButton.Size system
            let buttonScale = min(max(geo.size.width / 1000, 0.6), 1.2)
            // Use .medium as base (52pt) and scale from there
            let scaledButtonSize: CGFloat = IconCircleButton.Size.medium.diameter * buttonScale
            let wantsCameraPreview = RecordingCameraPreviewPolicy.wantsCameraPreview(
                isScreenSharing: appState.isScreenSharing,
                cameraEnabled: appState.cameraEnabled
            )

            ZStack {
                // 1. Main Preview Area (Full Screen)
                ZStack {
                    SaneVideoAmbientBackground()
                    LinearGradient(
                        colors: [
                            Color.black.opacity(0.24),
                            Color.black.opacity(0.36)
                        ],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                }
                .ignoresSafeArea()

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
                                    .font(Theme.Typography.body)
                                    .foregroundColor(Theme.Colors.textSecondary)
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
                    if appState.cameraState.shouldMountLivePreview, let session = appState.cameraState.session {
                        ZStack {
                            CameraPreviewView(
                                session: session,
                                sampleBufferPublisher: appState.cameraState.videoSampleBufferPublisher,
                                isMirrored: ServiceContainer.shared.userPreferences.mirrorCameraPreview
                            )
                                .aspectRatio(16 / 9, contentMode: .fit)
                                .opacity(
                                    appState.cameraState.isPreviewWarmingUp || !appState.cameraState.shouldShowLivePreview
                                        ? 0.001
                                        : 1
                                )
                                .edgesIgnoringSafeArea(.all)

                            if appState.cameraState.isPreviewWarmingUp || !appState.cameraState.shouldShowLivePreview {
                                ZStack {
                                    SaneVideoAmbientBackground()
                                    VStack(spacing: 16) {
                                        ProgressView().scaleEffect(1.5)
                                        Text("Camera Loading...")
                                            .font(.system(size: 22, weight: .semibold))
                                            .foregroundColor(.white)
                                    }
                                }
                                .edgesIgnoringSafeArea(.all)
                                .transition(.opacity)
                            }
                        }
                    } else if wantsCameraPreview {
                        // Camera Loading State
                        VStack(spacing: 16) {
                            ProgressView().scaleEffect(1.5)
                            Text("Camera Loading...")
                                .font(.system(size: 22, weight: .semibold))
                                .foregroundColor(.white)
                        }
                    } else {
                        // Camera Off State
                        VStack(spacing: 20) {
                            Image(systemName: "video.slash")
                                .font(.system(size: 80 * buttonScale))
                                .foregroundColor(Theme.Colors.textSecondary)
                            Text("Camera is Off")
                                .font(.system(size: 28 * buttonScale))
                                .foregroundColor(Theme.Colors.textPrimary)
                            Button("Turn On Camera") {
                                appState.toggleCamera()
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
                        showGalleryTarget: false, // Gallery button removed - not needed here
                        showTimer: false, // Timer moved to top-left
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
            AppLogger.uiLog.debug("RecordingModeView: onAppear")
            guard !TestEnvironment.isTesting || TestEnvironment.allowsHardwareIntegration else { return }
            appState.prepareCameraPreviewIfNeeded()
        }
    }

    private func formatDuration(_ duration: TimeInterval) -> String {
        TimeUtils.formatDuration(duration)
    }
}
