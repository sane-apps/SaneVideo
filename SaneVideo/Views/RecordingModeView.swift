import AVFoundation
import SaneUI
import SwiftUI

struct RecordingModeView: View {
    @Environment(AppState.self) var appState

    var body: some View {
        GeometryReader { geo in
            let buttonScale = min(max(geo.size.width / 1000, 0.6), 1.2)
            let scaledButtonSize: CGFloat = IconCircleButton.Size.medium.diameter * buttonScale
            let wantsCameraPreview = RecordingCameraPreviewPolicy.wantsCameraPreview(
                isScreenSharing: appState.isScreenSharing,
                cameraEnabled: appState.cameraEnabled
            )

            ZStack {
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
                    VStack(spacing: 16) {
                        Image(systemName: "display")
                            .font(.system(size: 64, weight: .light))
                            .foregroundStyle(Theme.Colors.accent)
                        Text(appState.recordingState.isRecording ? "Recording your screen" : "Ready to record your screen")
                            .font(.system(size: 28, weight: .bold))
                            .foregroundStyle(.white)
                        Text(appState.recordingState.isRecording
                            ? "This window stays out of the way. Stop with ⌥⌘R, pause with ⌥⌘P, or use the floating controls."
                            : "Press record. This window hides while you record; your camera bubble stays on screen.")
                            .font(Theme.Typography.body)
                            .foregroundStyle(.white)
                            .multilineTextAlignment(.center)
                            .frame(maxWidth: 520)
                    }
                } else {
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
                        VStack(spacing: 16) {
                            ProgressView().scaleEffect(1.5)
                            Text("Camera Loading...")
                                .font(.system(size: 22, weight: .semibold))
                                .foregroundColor(.white)
                        }
                    } else {
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

                VStack {
                    Spacer()
                    SharedRecordingControls(
                        showDevicePickers: true,
                        showGalleryTarget: false,
                        showTimer: false,
                        useGlassBackground: false,
                        buttonSize: .custom(scaledButtonSize)
                    )
                    .padding(.bottom, Theme.Dimensions.spacingXXL * buttonScale)
                }

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
