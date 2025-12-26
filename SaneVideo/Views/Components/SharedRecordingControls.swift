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

    // Sizing
    var buttonSize: IconCircleButton.Size = .medium
    var recordButtonSize: CGFloat = 72

    // Dynamic Sizing Helper
    private var baseButtonDimension: CGFloat {
        buttonSize.diameter
    }

    private var effectiveRecordButtonSize: CGFloat {
        // If explicitly provided (different from default 72), use it.
        // Otherwise, scale based on icon button size.
        if recordButtonSize != 72 {
            return recordButtonSize
        }
        switch buttonSize {
        case .small: return 56
        case .medium: return 72
        case .custom(let val): return val * 1.5
        }
    }

    private var toolbarSpacing: CGFloat {
        switch buttonSize {
        case .small: return 8
        case .medium: return 12
        case .custom(let val): return val * 0.25
        }
    }

    var body: some View {
        HStack(spacing: toolbarSpacing) {
            // 1. Mic Toggle
            Button(action: {
                ServiceContainer.shared.hapticsManager.selection()
                appState.toggleMic()
            }, label: {
                ZStack {
                    if appState.isMicActive {
                        AudioVisualizerView(
                            audioLevelPublisher: appState.cameraState.audioLevelPublisher,
                            size: baseButtonDimension + 12
                        )
                        .allowsHitTesting(false)
                    }
                    Image(systemName: appState.isMicActive ? "mic.fill" : "mic.slash.fill")
                        .font(.system(size: buttonSize.iconSize, weight: .bold))
                        .foregroundColor(.white)
                }
                .frame(width: baseButtonDimension, height: baseButtonDimension)
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
                systemName: "display",
                isActive: appState.isScreenSharing,
                size: buttonSize,
                activeColor: Theme.Colors.accent,
                helpText: appState.isScreenSharing ? "Stop Screen Sharing" : "Share Screen",
                action: {
                    ServiceContainer.shared.hapticsManager.selection()
                    appState.toggleScreenShare()
                }
            )
            .accessibilityIdentifier(AccessibilityIdentifiers.screenShareToggle)

            // 3. PRIMARY ACTION (Record)
            UnifiedRecordButton(size: effectiveRecordButtonSize)
                .keyboardShortcut("r", modifiers: [.command])
                .animation(.spring(response: 0.35, dampingFraction: 0.7), value: appState.isRecording)

            // 4. SECONDARY ACTION (Pause)
            if appState.isRecording {
                IconCircleButton(
                    systemName: appState.isPaused ? "play.fill" : "pause.fill",
                    isActive: true,
                    size: buttonSize,
                    activeColor: Theme.Colors.warning,
                    helpText: appState.isPaused ? "Resume Recording" : "Pause Recording",
                    action: {
                        ServiceContainer.shared.hapticsManager.selection()
                        appState.togglePause()
                    }
                )
                .accessibilityIdentifier(AccessibilityIdentifiers.pauseRecordingButton)
                .transition(.scale.combined(with: .opacity))
            }

            // 5. STATUS (Timer / Pickers / Gallery)
            if showTimer {
                RecBadgeTimer(
                    isRecording: appState.isRecording,
                    timeString: formatDuration(appState.recordingDuration)
                )
                .transition(.move(edge: .trailing).combined(with: .opacity))
            }

            if showDevicePickers {
                DeviceSelectionMenu(size: buttonSize)
            }

            if showGalleryTarget {
                GalleryButton(size: buttonSize)
            }
        }
        .padding(.vertical, 8)
        .padding(.horizontal, 16)
        .background {
            if useGlassBackground {
                Capsule()
                    .fill(.ultraThinMaterial)
                    .overlay(
                        Capsule()
                            .stroke(Color.white.opacity(0.1), lineWidth: 1)
                    )
            }
        }
    }

    private func formatDuration(_ duration: TimeInterval) -> String {
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

// MARK: - Subcomponents

private struct DeviceSelectionMenu: View {
    @Environment(AppState.self) var appState
    var size: IconCircleButton.Size

    var body: some View {
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
                            if device.uniqueID == appState.audioService.currentMicID {
                                Image(systemName: "checkmark")
                            }
                        }
                    })
                }
            }
        } label: {
            Image(systemName: "gearshape.fill")
                .font(.system(size: size.iconSize, weight: .bold))
                .foregroundColor(.white)
        }
        .buttonStyle(IconCircleButtonStyle(size: size, isActive: false, activeColor: Theme.Colors.accent))
        .help("Camera & Microphone Selection")
    }
}

private struct GalleryButton: View {
    @Environment(AppState.self) var appState
    var size: IconCircleButton.Size

    var body: some View {
        if appState.recentlyAddedClip != nil {
            Button(action: {
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
