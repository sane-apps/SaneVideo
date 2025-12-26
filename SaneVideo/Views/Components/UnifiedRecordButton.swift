import SwiftUI

/// Record button with same unified style as other control buttons
/// Slightly larger with red accent color
struct UnifiedRecordButton: View {
    @Environment(AppState.self) var appState

    /// Size of the button
    var size: CGFloat = 52

    var body: some View {
        Button(action: {
            NSLog("🔴 UnifiedRecordButton: CLICKED! Current isRecording = \(appState.isRecording)")
            ServiceContainer.shared.hapticsManager.impact()

            withAnimation(.spring(response: 0.4, dampingFraction: 0.7)) {
                if appState.isRecording {
                    NSLog("🔴 UnifiedRecordButton: Calling stopRecording...")
                    appState.stopRecording()
                } else {
                    NSLog("🔴 UnifiedRecordButton: Calling startRecording...")
                    appState.startRecording()
                }
            }
        }, label: {
            ZStack {
                // Icon: circle when idle, square when recording
                if appState.isRecording {
                    RoundedRectangle(cornerRadius: 4)
                        .fill(Color.white)
                        .frame(width: size * 0.35, height: size * 0.35)
                } else {
                    Circle()
                        .fill(Color.white)
                        .frame(width: size * 0.4, height: size * 0.4)
                }
            }
            .frame(width: size, height: size)
        })
        .buttonStyle(RecordButtonStyle(size: size, isRecording: appState.isRecording))
        .accessibilityLabel(
            appState.isRecording
                ? String(localized: "recording.stop", defaultValue: "Stop recording")
                : String(localized: "recording.start", defaultValue: "Start recording")
        )
        .accessibilityIdentifier(AccessibilityIdentifiers.recordButton)
        .help(
            KeyboardShortcutHelper.helpWithShortcut(
                appState.isRecording
                    ? String(localized: "recording.stop", defaultValue: "Stop recording")
                    : String(localized: "recording.start", defaultValue: "Start recording"),
                key: "r",
                modifiers: [.command]
            )
        )
        .onChange(of: appState.isRecording) { _, isRecording in
            NSLog("🔴 UnifiedRecordButton: isRecording changed to \(isRecording)")
        }
    }
}

/// Button style matching IconCircleButtonStyle but with red color
struct RecordButtonStyle: ButtonStyle {
    let size: CGFloat
    let isRecording: Bool

    @State private var isHovering = false

    // Recording uses bright red, idle uses darker red
    private var buttonColor: Color {
        isRecording ? Color.red : Color(red: 0.8, green: 0.15, blue: 0.15)
    }

    private var fillOpacity: Double {
        isRecording ? 0.9 : Theme.Opacity.heavy  // Brighter when recording
    }

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .frame(width: size, height: size)
            .contentShape(Circle())
            .background(
                ZStack {
                    // Glass background with red tint
                    Circle()
                        .fill(buttonColor.opacity(fillOpacity))

                    // Border ring
                    Circle()
                        .strokeBorder(
                            buttonColor.opacity(isRecording ? 0.9 : 0.5),
                            lineWidth: isRecording ? 3 : 2
                        )
                }
            )
            // Glow effect when recording
            .shadow(color: isRecording ? Color.red.opacity(0.6) : .clear, radius: 12, x: 0, y: 0)
            // Subtle drop shadow for depth
            .shadow(color: .black.opacity(0.2), radius: 2, x: 0, y: 1)
            // Hover and press animations
            .scaleEffect(isHovering ? (configuration.isPressed ? 1.0 : 1.08) : (configuration.isPressed ? 0.94 : 1.0))
            .animation(.easeOut(duration: 0.15), value: isHovering)
            .animation(.easeOut(duration: 0.1), value: configuration.isPressed)
            .onHover { hovering in
                isHovering = hovering
                if hovering {
                    ServiceContainer.shared.hapticsManager.selection()
                }
            }
            .onChange(of: configuration.isPressed) { _, pressed in
                if pressed {
                    ServiceContainer.shared.hapticsManager.impact()
                }
            }
    }
}
