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

    static func minimumBarWidth(
        buttonSize: IconCircleButton.Size = .medium,
        includePauseControl: Bool,
        showTimer: Bool,
        showGalleryTarget: Bool
    ) -> CGFloat {
        let standardButtonWidth = buttonSize.diameter
        let recordButtonWidth = standardButtonWidth * 1.2
        let spacing = buttonSize.spacing
        let horizontalPadding = Theme.Dimensions.paddingLG * 2
        let timerWidth = showTimer ? RecBadgeTimer.minimumReservedWidth + RecBadgeTimer.trailingInset : 0

        var itemWidths: [CGFloat] = [
            standardButtonWidth,  // Mic
            standardButtonWidth,  // Screen share
            recordButtonWidth,    // Record
            standardButtonWidth,  // Demo Studio
            standardButtonWidth   // Teleprompter
        ]

        if includePauseControl {
            itemWidths.insert(standardButtonWidth, at: 3)
        }

        if timerWidth > 0 {
            itemWidths.append(timerWidth)
        }

        if showGalleryTarget {
            itemWidths.append(standardButtonWidth)
        }

        let interItemSpacing = CGFloat(max(itemWidths.count - 1, 0)) * spacing
        return itemWidths.reduce(0, +) + interItemSpacing + horizontalPadding
    }

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

    private var permissionManager: PermissionManager {
        ServiceContainer.shared.permissionManager
    }

    private var permissionWarning: RecordingPermissionHint? {
        if permissionManager.microphoneStatus == .denied || permissionManager.microphoneStatus == .restricted {
            return RecordingPermissionHint(
                text: "Microphone access is off. Enable it in System Settings if you want narration in the recording.",
                icon: "mic.slash.fill",
                destination: .microphone
            )
        }

        if appState.isScreenSharing,
           permissionManager.screenRecordingStatus == .denied || permissionManager.screenRecordingStatus == .restricted {
            return RecordingPermissionHint(
                text: "Screen capture access is off. Re-enable Screen Recording in System Settings to use screen mode.",
                icon: "display.trianglebadge.exclamationmark",
                destination: .screenRecording
            )
        }

        if !appState.isScreenSharing,
           permissionManager.cameraStatus == .denied || permissionManager.cameraStatus == .restricted {
            return RecordingPermissionHint(
                text: "Camera access is off. Re-enable Camera in System Settings to record presenter mode.",
                icon: "video.slash.fill",
                destination: .camera
            )
        }

        return nil
    }

    var body: some View {
        let speakerNotes = appState.currentProject?.speakerNotes ?? .init()
        let teleprompterVisible = speakerNotes.isVisible
        let micGuide = RecordingControlGuide(
            title: appState.isMicActive ? "Microphone" : "Microphone muted",
            message: appState.isMicActive
                ? "Include mic audio in the take. Turn this off if you only want system sound or silent capture."
                : "Bring narration back into the take. If you leave this muted, SaneVideo records without your mic."
        )
        let screenGuide = RecordingControlGuide(
            title: appState.isScreenSharing ? "Stop screen capture" : "Share screen",
            message: appState.isScreenSharing
                ? "Switch back from screen mode when you want camera-only capture again."
                : "Pick a window or display to record the product walkthrough instead of only the camera feed."
        )
        let recordGuide = RecordingControlGuide(
            title: appState.isRecording ? "Stop recording" : "Start recording",
            message: appState.isRecording
                ? "Finish the current take and save it into the local project."
                : "Begin a new local recording with the current camera, screen, mic, and notes setup.",
            shortcut: "⌘R"
        )
        let pauseGuide = RecordingControlGuide(
            title: appState.isPaused ? "Resume recording" : "Pause recording",
            message: appState.isPaused
                ? "Continue the active take without creating a new clip."
                : "Temporarily stop the take without closing it."
        )
        let demoGuide = RecordingControlGuide(
            title: "Demo Studio",
            message: "Write speaker notes, manage chapters, choose templates, and set local export defaults for this recording."
        )
        let teleprompterGuide = RecordingControlGuide(
            title: teleprompterVisible ? "Hide teleprompter" : "Show teleprompter",
            message: teleprompterVisible
                ? "Hide the teleprompter overlay. The overlay is excluded from capture."
                : "Show the teleprompter overlay using the notes saved in Demo Studio. It stays local and is excluded from capture."
        )
        let deviceGuide = RecordingControlGuide(
            title: "Device menu",
            message: "Choose a different camera or microphone for the next take."
        )

        ZStack(alignment: .bottomLeading) {
            VStack(alignment: .leading, spacing: permissionWarning == nil ? 0 : 8) {
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
                    .recordingGuide(micGuide)
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
                    .recordingGuide(screenGuide)
                    .accessibilityIdentifier(AccessibilityIdentifiers.screenShareToggle)

                    // 3. Record Button - slightly larger, same unified style
                    UnifiedRecordButton(size: recordButtonSize)
                        .keyboardShortcut("r", modifiers: [.command])
                        .animation(.spring(response: 0.35, dampingFraction: 0.7), value: appState.isRecording)
                        .recordingGuide(recordGuide)

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
                        .recordingGuide(pauseGuide)
                        .accessibilityIdentifier(AccessibilityIdentifiers.pauseRecordingButton)
                        .transition(.scale.combined(with: .opacity))
                    }

                    IconCircleButton(
                        systemName: "note.text",
                        isActive: false,
                        size: buttonSize,
                        activeColor: Theme.Colors.accent,
                        helpText: "Open Demo Studio",
                        action: {
                            ServiceContainer.shared.hapticsManager.selection()
                            appState.openDemoStudio()
                        }
                    )
                    .recordingGuide(demoGuide)

                    IconCircleButton(
                        systemName: "text.alignleft",
                        isActive: teleprompterVisible,
                        size: buttonSize,
                        activeColor: Theme.Colors.warning,
                        helpText: teleprompterVisible ? "Hide Teleprompter" : "Show Teleprompter",
                        action: {
                            ServiceContainer.shared.hapticsManager.selection()
                            appState.toggleTeleprompter()
                        }
                    )
                    .recordingGuide(teleprompterGuide)

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
                            .recordingGuide(
                                RecordingControlGuide(
                                    title: "Open recent clip",
                                    message: "Jump into editing with the clip you just recorded."
                                )
                            )
                    }
                }
                .padding(.vertical, Theme.Dimensions.paddingSM)
                .padding(.horizontal, Theme.Dimensions.paddingLG)
                .modifier(ConditionalCapsuleGlass(isEnabled: useGlassBackground))

                if let permissionWarning {
                    RecordingPermissionChip(hint: permissionWarning)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                }
            }

            // Gear icon - subtle, bottom-left, outside main bar
            if showDevicePickers {
                DeviceSelectionMenu(size: buttonSize)
                    .recordingGuide(deviceGuide)
                    .offset(x: -uniformButtonSize - toolbarSpacing, y: 0)
            }
        }
    }

    private func formatDuration(_ duration: TimeInterval) -> String {
        TimeUtils.formatDuration(duration)
    }
}

private struct RecordingControlGuide: Equatable {
    let title: String
    let message: String
    var shortcut: String?

    var tooltipText: String {
        if let shortcut {
            return "\(title). \(message) (\(shortcut))"
        }
        return "\(title). \(message)"
    }
}

private struct RecordingPermissionHint {
    let text: String
    let icon: String
    let destination: RecordingPermissionDestination
}

private enum RecordingPermissionDestination {
    case camera
    case microphone
    case screenRecording
}

private struct RecordingPermissionChip: View {
    let hint: RecordingPermissionHint

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: hint.icon)
                .font(.system(size: Theme.Typography.iconSizeSM, weight: .semibold))
                .foregroundStyle(Theme.Colors.warning)

            Text(hint.text)
                .saneReadableSupportText()
                .lineLimit(2)

            Spacer(minLength: 0)

            Button("Open Settings") {
                switch hint.destination {
                case .camera:
                    ServiceContainer.shared.permissionManager.openSystemSettings()
                case .microphone:
                    guard
                        let url = URL(
                            string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Microphone"
                        )
                    else { return }
                    NSWorkspace.shared.open(url)
                case .screenRecording:
                    ServiceContainer.shared.permissionManager.openScreenRecordingSettings()
                }
            }
            .buttonStyle(.borderless)
            .font(.system(size: 12, weight: .semibold))
            .foregroundStyle(Theme.Colors.accent)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .frame(maxWidth: 420, alignment: .leading)
        .sanePanel(radius: 14, emphasized: true, accent: Theme.Colors.warning)
    }
}

private struct RecordingGuideModifier: ViewModifier {
    let guide: RecordingControlGuide

    func body(content: Content) -> some View {
        content
            .help(guide.tooltipText)
            .instantTooltip(guide.tooltipText)
    }
}

private extension View {
    func recordingGuide(_ guide: RecordingControlGuide) -> some View {
        modifier(RecordingGuideModifier(guide: guide))
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
                .foregroundColor(.white.opacity(0.9))
                .frame(width: size.diameter * 0.7, height: size.diameter * 0.7)
                .background(
                    Circle()
                        .fill(Color.white.opacity(0.18))
                )
        }
        .menuStyle(.borderlessButton)
        .help("Camera & Microphone Selection")
        .onAppear {
            appState.cameraState.ensureCamerasDiscovered()
            appState.audioService.ensureMicrophonesDiscovered()
        }
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

// MARK: - PiP Controls with Countdown Overlay

/// Wrapper that shows countdown overlay over PiP controls when recording starts
struct PiPControlsWithCountdown: View {
    @Environment(AppState.self) var appState
    var buttonSize: IconCircleButton.Size

    var body: some View {
        ZStack {
            // Controls at bottom
            VStack {
                Spacer()
                SharedRecordingControls(
                    showDevicePickers: false,
                    showGalleryTarget: false,
                    showTimer: false,
                    useGlassBackground: true,
                    buttonSize: buttonSize
                )
            }

            // Countdown overlay (fills entire PiP window)
            if appState.recordingState.countdownValue > 0 {
                ZStack {
                    // Semi-transparent background
                    Color.black.opacity(0.5)

                    // Large countdown number
                    Text("\(appState.recordingState.countdownValue)")
                        .font(.system(size: 80, weight: .bold, design: .rounded))
                        .foregroundColor(.white)
                        .shadow(color: .black.opacity(0.5), radius: 8, x: 0, y: 4)
                }
                .transition(.opacity)
                .animation(.easeInOut(duration: 0.2), value: appState.recordingState.countdownValue)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
