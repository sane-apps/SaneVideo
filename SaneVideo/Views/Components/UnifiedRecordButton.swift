import SwiftUI

struct UnifiedRecordButton: View {
  @Environment(AppState.self) var appState

  /// Size of the button itself.
  var size: CGFloat = 68  // Slightly larger to accommodate the details

  // Animation state for the pulse effect
  @State private var isPulsing: Bool = false

  var body: some View {
    Button(
      action: {
        ServiceContainer.shared.hapticsManager.impact()

        withAnimation(.spring(response: 0.4, dampingFraction: 0.7)) {
          if appState.isRecording {
            appState.stopRecording()
          } else {
            appState.startRecording()
          }
        }
      },
      label: {
        ZStack {
          // 1. Base Layer (The physical housing)
          // Dark gray gradient with subtle bezel effect
          Circle()
            .fill(
              LinearGradient(
                colors: [
                  Color(white: 0.35),  // Top light highlight
                  Color(white: 0.15),  // Bottom shadow
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
              )
            )
            .frame(width: size, height: size)
            .shadow(color: .black.opacity(0.4), radius: 4, x: 2, y: 4)  // Drop shadow for depth

          // 2. The Channel / Groove (Recessed darker area)
          Circle()
            .fill(
              LinearGradient(
                colors: [
                  Color(white: 0.10),
                  Color(white: 0.20),
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
              )
            )
            .frame(width: size * 0.82, height: size * 0.82)

          // 3. The "Light Ring" (Red Accent)
          // This lives inside the groove
          Circle()
            .stroke(
              LinearGradient(
                colors: [
                  Color(red: 1.0, green: 0.2, blue: 0.2),  // Bright Red
                  Color(red: 0.8, green: 0.0, blue: 0.0),  // Darker Red
                ],
                startPoint: .top,
                endPoint: .bottom
              ),
              lineWidth: size * 0.08
            )
            .frame(width: size * 0.72, height: size * 0.72)
            // Glow effect when recording
            .shadow(
              color: appState.isRecording ? Color.red.opacity(0.8) : Color.clear,
              radius: appState.isRecording ? 8 : 0
            )
            .opacity(appState.isRecording ? 1.0 : 0.6)  // Dimmer when idle
            .scaleEffect(appState.isRecording && isPulsing ? 1.05 : 1.0)

          // 4. The Center Button (Physical Actor)
          // Morphs from Circle (Record) to Square (Stop)
          RoundedRectangle(cornerRadius: appState.isRecording ? 6 : size * 0.25)
            .fill(
              LinearGradient(
                colors: [
                  Color(white: 0.30),
                  Color(white: 0.18),
                ],
                startPoint: .top,
                endPoint: .bottom
              )
            )
            .overlay(
              RoundedRectangle(cornerRadius: appState.isRecording ? 6 : size * 0.25)
                .stroke(Color.white.opacity(0.1), lineWidth: 1)
            )
            .frame(
              width: appState.isRecording ? size * 0.35 : size * 0.5,
              height: appState.isRecording ? size * 0.35 : size * 0.5
            )
            .shadow(color: .black.opacity(0.5), radius: 2, x: 0, y: 1)
        }
      }
    )
    .buttonStyle(PremiumRecordButtonStyle())
    .accessibilityLabel(
      appState.isRecording
        ? String(localized: "recording.stop", defaultValue: "Stop recording")
        : String(localized: "recording.start", defaultValue: "Start recording")
    )
    .accessibilityIdentifier("RecordButton")
    .help(
      KeyboardShortcutHelper.helpWithShortcut(
        appState.isRecording
          ? String(localized: "recording.stop", defaultValue: "Stop recording")
          : String(localized: "recording.start", defaultValue: "Start recording"), key: "r",
        modifiers: [.command])
    )
    .onAppear {
      // Setup continuous pulse animation loop
      withAnimation(.easeInOut(duration: 1.0).repeatForever(autoreverses: true)) {
        isPulsing = true
      }
    }
  }
}

// Premium interaction style (Press mechanics)
struct PremiumRecordButtonStyle: ButtonStyle {
  func makeBody(configuration: Configuration) -> some View {
    configuration.label
      .scaleEffect(configuration.isPressed ? 0.96 : 1.0)
      .brightness(configuration.isPressed ? -0.05 : 0)
      .animation(
        .interactiveSpring(response: 0.3, dampingFraction: 0.6), value: configuration.isPressed)
  }
}
