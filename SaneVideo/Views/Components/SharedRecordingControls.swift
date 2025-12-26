//
//  SharedRecordingControls.swift
//  SaneVideo
//
//  Created by Antigravity on 2025-12-25.
//  Consolidated recording controls for consistent UX across Main Window, PiP, and Floating Controls.
//

import SwiftUI
import AVFoundation

struct SharedRecordingControls: View {
    @Environment(AppState.self) var appState

    // MARK: - Configuration
    var showDevicePickers: Bool = false
    var showGalleryTarget: Bool = false
    var showTimer: Bool = true
    var useGlassBackground: Bool = false

    // Sizing - uses unified IconCircleButton.Size system
    var buttonSize: IconCircleButton.Size = .medium

    // Button sizes - record button slightly larger for prominence
    private var uniformButtonSize: CGFloat {
        buttonSize.diameter
    }

    // Record button is 1.2x larger for visual hierarchy
    private var recordButtonSize: CGFloat {
        buttonSize.diameter * 1.2
    }

    /// Spacing from the unified size system
    private var toolbarSpacing: CGFloat {
        buttonSize.spacing
    }

    var body: some View {
        ZStack(alignment: .bottomLeading) {
            // Main controls bar
            HStack(spacing: toolbarSpacing) {
                // 1. Mic Toggle
                Button(action: {
                    ServiceContainer.shared.hapticsManager.impact()
                    appState.toggleMic()
                }, label: {
                    ZStack {
                        if appState.isMicActive {
                            AudioVisualizerView(
                                audioLevelPublisher: appState.cameraState.audioLevelPublisher,
                                size: uniformButtonSize + 12
                            )
                            .allowsHitTesting(false)
                        }
                        Image(systemName: appState.isMicActive ? "mic.fill" : "mic.slash.fill")
                            .font(.system(size: buttonSize.iconSize, weight: .bold))
                            .foregroundColor(.white)
                    }
                    .frame(width: uniformButtonSize, height: uniformButtonSize)
                })
                .buttonStyle(IconCircleButtonStyle(
                    size: buttonSize,
                    isActive: appState.isMicActive,
                    activeColor: Theme.Colors.accent
                ))
                .help(appState.isMicActive ? "Mute Microphone" : "Unmute Microphone")
                .accessibilityIdentifier(AccessibilityIdentifiers.micToggle)

                // 2. Screen Share Toggle
                IconCircleButton(
                    systemName: appState.isScreenSharing ? "rectangle.on.rectangle.slash.fill" : "rectangle.on.rectangle.fill",
                    isActive: appState.isScreenSharing,
                    size: buttonSize,
                    activeColor: Theme.Colors.accent,
                    helpText: appState.isScreenSharing ? "Stop Screen Sharing" : "Share Screen",
                    action: {
                        ServiceContainer.shared.hapticsManager.impact()
                        appState.toggleScreenShare()
                    }
                )
                .accessibilityIdentifier(AccessibilityIdentifiers.screenShareToggle)

                // 3. Record Button - slightly larger, same unified style
                UnifiedRecordButton(size: recordButtonSize)
                    .keyboardShortcut("r", modifiers: [.command])
                    .animation(.spring(response: 0.35, dampingFraction: 0.7), value: appState.isRecording)

                // 4. Pause Button (only when recording)
                if appState.isRecording {
                    IconCircleButton(
                        systemName: appState.isPaused ? "play.fill" : "pause.fill",
                        isActive: appState.isPaused,
                        size: buttonSize,
                        activeColor: Theme.Colors.warning,
                        helpText: appState.isPaused ? "Resume Recording" : "Pause Recording",
                        action: {
                            ServiceContainer.shared.hapticsManager.impact()
                            appState.togglePause()
                        }
                    )
                    .accessibilityIdentifier(AccessibilityIdentifiers.pauseRecordingButton)
                    .transition(.scale.combined(with: .opacity))
                }

                // 5. Timer badge
                if showTimer && appState.isRecording {
                    RecBadgeTimer(
                        isRecording: appState.isRecording,
                        timeString: formatDuration(appState.recordingDuration)
                    )
                    .transition(.move(edge: .trailing).combined(with: .opacity))
                }

                // Gallery button (in main bar)
                if showGalleryTarget {
                    GalleryButton(size: buttonSize)
                }
            }
            .padding(.vertical, Theme.Dimensions.paddingSM)
            .padding(.horizontal, Theme.Dimensions.paddingLG)
            .background {
                if useGlassBackground {
                    Capsule()
                        .fill(.ultraThinMaterial)
                        .overlay(
                            Capsule()
                                .stroke(Color.white.opacity(Theme.Opacity.light), lineWidth: 1)
                        )
                        .shadow(color: .black.opacity(0.3), radius: 8, x: 0, y: 2)
                }
            }

            // Gear icon - subtle, bottom-left, outside main bar
            if showDevicePickers {
                DeviceSelectionMenu(size: buttonSize)
                    .offset(x: -uniformButtonSize - toolbarSpacing, y: 0)
            }
        }
    }

    private func formatDuration(_ duration: TimeInterval) -> String {
        TimeUtils.formatDuration(duration)
    }
}

// MARK: - Subcomponents

private struct DeviceSelectionMenu: View {
    @Environment(AppState.self) var appState
    var size: IconCircleButton.Size

    var body: some View {
        Menu {
            Section("Camera") {
                ForEach(appState.cameraState.availableCameras, id: \.uniqueID) { device in
                    Button(action: {
                        ServiceContainer.shared.hapticsManager.impact()
                        appState.cameraState.switchCamera(to: device)
                    }, label: {
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
                    Button(action: {
                        ServiceContainer.shared.hapticsManager.impact()
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
            }
        } label: {
            Image(systemName: "gearshape")
                .font(.system(size: size.iconSize * 0.8, weight: .medium))
                .foregroundColor(.white.opacity(0.6))
                .frame(width: size.diameter * 0.7, height: size.diameter * 0.7)
                .background(
                    Circle()
                        .fill(Color.white.opacity(0.1))
                )
        }
        .menuStyle(.borderlessButton)
        .help("Camera & Microphone Selection")
    }
}

private struct GalleryButton: View {
    @Environment(AppState.self) var appState
    var size: IconCircleButton.Size

    var body: some View {
        if appState.recentlyAddedClip != nil {
            Button(action: {
                ServiceContainer.shared.hapticsManager.impact()
                appState.switchToEditing()
            }, label: {
                Image(systemName: "photo.stack.fill")
                    .font(.system(size: size.iconSize, weight: .bold))
                    .foregroundColor(.white)
            })
            .buttonStyle(IconCircleButtonStyle(size: size, isActive: false, activeColor: Theme.Colors.accent))
            .accessibilityIdentifier(AccessibilityIdentifiers.recentClipButton)
        }
    }
}
