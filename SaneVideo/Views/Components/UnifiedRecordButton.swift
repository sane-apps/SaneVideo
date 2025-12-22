import SwiftUI

struct UnifiedRecordButton: View {
    @Environment(AppState.self) var appState

    /// Size of the button itself (icon/circle).
    /// The visualizer ring will be calculated relative to this, or can be managed internally.
    var size: CGFloat = 64

    /// Scale factor for the visualizer ring relative to the button size
    private let visualizerScale: CGFloat = 1.3

    var body: some View {
        // visualizerSize removed

        ZStack {
            // Unified Animation Style (Red Audio Visualizer)
            // Only visible when recording
            // Visualizer removed per user feedback (overkill)

            Button(action: {
                // Shared interaction logic
                ServiceContainer.shared.hapticsManager.impact()
                if appState.isRecording {
                    appState.stopRecording()
                } else {
                    appState.startRecording()
                }
            }, label: {
                ZStack {
                    // 1. Outer Ring (Always visible)
                    Circle()
                        .strokeBorder(Color.white, lineWidth: 4)
                        .frame(width: size, height: size)

                    // 2. Inner Indicator (Red Circle -> Red Square)
                    // Scales down and changes shape when recording
                    RoundedRectangle(cornerRadius: appState.isRecording ? 4 : size / 2)
                        .fill(Color.red)
                        .frame(
                            width: appState.isRecording ? size * 0.45 : size - 12,
                            height: appState.isRecording ? size * 0.45 : size - 12
                        )
                        .animation(.spring(response: 0.3, dampingFraction: 0.6), value: appState.isRecording)
                }
            })
            .buttonStyle(.plain)
            .accessibilityLabel(appState.isRecording ? String(localized: "recording.stop", defaultValue: "Stop recording") : String(localized: "recording.start", defaultValue: "Start recording"))
            .accessibilityIdentifier("RecordButton")
        }
        .help(KeyboardShortcutHelper.helpWithShortcut(appState.isRecording ? String(localized: "recording.stop", defaultValue: "Stop recording") : String(localized: "recording.start", defaultValue: "Start recording"), key: "r", modifiers: [.command]))
        .featureTooltip("record_button", message: String(localized: "recording.tooltip", defaultValue: "Press to start recording. Use ⌘R for quick access!"))
    }
}
