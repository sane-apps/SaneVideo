// Consolidated recording controls for consistent UX across Main Window, PiP, and Floating Controls.

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

    var buttonSize: IconCircleButton.Size = .medium

    private var uniformButtonSize: CGFloat {
        buttonSize.diameter
    }

    private var recordButtonSize: CGFloat {
        buttonSize.diameter * 1.2
    }

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
            VStack(alignment: .center, spacing: permissionWarning == nil ? 0 : 8) {
                HStack(alignment: .center, spacing: toolbarSpacing) {
                    if showDevicePickers {
                        captureModePicker
                            .frame(height: recordButtonSize)
                            .padding(.trailing, 6)
                            .padding(.bottom, 22)
                    }

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
                    .barLabel("Mic", isShown: showDevicePickers, height: recordButtonSize)

                    if showDevicePickers {
                        IconCircleButton(
                            systemName: appState.cameraEnabled || appState.cameraState.isActive ? "video.fill" : "video.slash.fill",
                            isActive: appState.cameraEnabled || appState.cameraState.isActive,
                            size: buttonSize,
                            activeColor: Theme.Colors.accent,
                            helpText: appState.isScreenSharing ? "Show or hide your camera bubble" : "Turn the camera on or off",
                            action: {
                                ServiceContainer.shared.hapticsManager.impact()
                                appState.toggleCamera()
                            }
                        )
                        .barLabel("Camera", isShown: true, height: recordButtonSize)
                        .accessibilityIdentifier("recording.cameraToggle")
                    } else {
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
                    }

                    UnifiedRecordButton(size: recordButtonSize)
                        .keyboardShortcut("r", modifiers: [.command])
                        .animation(.spring(response: 0.35, dampingFraction: 0.7), value: appState.isRecording)
                        .recordingGuide(recordGuide)
                    .barLabel(appState.isRecording ? "Stop" : "Record", isShown: showDevicePickers, height: recordButtonSize)

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
                    .barLabel(appState.isPaused ? "Resume" : "Pause", isShown: showDevicePickers, height: recordButtonSize)
                        .transition(.scale.combined(with: .opacity))
                    }

                    IconCircleButton(
                        systemName: "note.text",
                        isActive: false,
                        size: buttonSize,
                        activeColor: Theme.Colors.accent,
                        helpText: "Teleprompter Script",
                        action: {
                            ServiceContainer.shared.hapticsManager.selection()
                            appState.openTeleprompterScript()
                        }
                    )
                    .recordingGuide(demoGuide)
                    .barLabel("Script", isShown: showDevicePickers, height: recordButtonSize)

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
                    .barLabel("Prompter", isShown: showDevicePickers, height: recordButtonSize)

                    if showTimer && appState.isRecording {
                        RecBadgeTimer(
                            isRecording: appState.isRecording,
                            timeString: formatDuration(appState.recordingDuration)
                        )
                        .transition(.move(edge: .trailing).combined(with: .opacity))
                    }

                    if showDevicePickers {
                        DeviceSelectionMenu(size: buttonSize)
                            .frame(width: uniformButtonSize, height: uniformButtonSize)
                            .recordingGuide(deviceGuide)
                            .barLabel("Devices", isShown: true, height: recordButtonSize)
                    }

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
                .padding(.vertical, showDevicePickers ? 12 : Theme.Dimensions.paddingSM)
                .padding(.horizontal, showDevicePickers ? 20 : Theme.Dimensions.paddingLG)
                .modifier(ConditionalCapsuleGlass(isEnabled: useGlassBackground))
                .background {
                    if showDevicePickers {
                        RoundedRectangle(cornerRadius: 28, style: .continuous)
                            .fill(.ultraThinMaterial)
                            .overlay(
                                RoundedRectangle(cornerRadius: 28, style: .continuous)
                                    .strokeBorder(Color.white.opacity(0.12), lineWidth: 1)
                            )
                    }
                }

                if let permissionWarning {
                    RecordingPermissionChip(hint: permissionWarning)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                }
            }
        }
    }

    /// Camera records just you; Screen records a window or display with your camera bubble on top.
    private var captureModePicker: some View {
        Picker("What to record", selection: Binding(
            get: { appState.isScreenSharing },
            set: { wantsScreen in
                guard wantsScreen != appState.isScreenSharing else { return }
                ServiceContainer.shared.hapticsManager.impact()
                appState.toggleScreenShare()
            }
        )) {
            Label("Camera", systemImage: "person.crop.square").tag(false)
            Label("Screen", systemImage: "display").tag(true)
        }
        .pickerStyle(.segmented)
        .labelsHidden()
        .labelStyle(.titleAndIcon)
        .controlSize(.large)
        .fixedSize()
        .help("Camera records just you. Screen records a window or display with your camera bubble on top. You can switch while recording.")
        .accessibilityIdentifier(AccessibilityIdentifiers.screenShareToggle)
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
            Image(systemName: "gearshape.fill")
                .font(.system(size: size.iconSize, weight: .medium))
                .foregroundColor(.white.opacity(0.9))
                .frame(width: size.diameter * 0.7, height: size.diameter * 0.7)
                .background(
                    Circle()
                        .fill(Color.white.opacity(0.18))
                )
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .help("Choose a camera and microphone")
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

            if appState.recordingState.countdownValue > 0 {
                ZStack {
                    Color.black.opacity(0.5)

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

private extension View {
    /// A caption under a recorder button, shown only in the main window where there is room.
    @ViewBuilder
    func barLabel(_ text: String, isShown: Bool, height: CGFloat) -> some View {
        if isShown {
            VStack(spacing: 6) {
                self.frame(height: height)
                Text(text)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(.white)
                    .lineLimit(1)
                    .fixedSize()
            }
        } else {
            self
        }
    }
}
