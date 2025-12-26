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
          NSLog("🔴 UnifiedRecordButton: CLICKED! Current isRecording = \(appState.isRecording)")
          ServiceContainer.shared.hapticsManager.snap()

          withAnimation(.spring(response: 0.4, dampingFraction: 0.7)) {
            if appState.isRecording {
              NSLog("🔴 UnifiedRecordButton: Calling stopRecording...")
              appState.stopRecording()
            } else {
              NSLog("🔴 UnifiedRecordButton: Calling startRecording...")
              appState.startRecording()
            }
          }
        },
        label: {
          ZStack {
            // RECORDING GLOW: Subtle outer pulsing glow when recording
            if appState.isRecording {
              Circle()
                .fill(Color.red.opacity(0.15))
                .frame(width: size * 1.2, height: size * 1.2)
                .scaleEffect(isPulsing ? 1.1 : 1.0)
                .opacity(isPulsing ? 0.0 : 0.4)
            }

            // 1. Base Layer (The physical housing)
            // Dark gray gradient with subtle bezel effect
            Circle()
              .fill(
                LinearGradient(
                  colors: [
                    Color(white: 0.35),  // Top light highlight
                    Color(white: 0.15)  // Bottom shadow
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
                    Color(white: 0.20)
                  ],
                  startPoint: .topLeading,
                  endPoint: .bottomTrailing
                )
              )
              .frame(width: size * 0.82, height: size * 0.82)

            // 3. The "Light Ring" (Red Accent)
            // This lives inside the groove - subtly brighter when recording
            Circle()
              .stroke(
                LinearGradient(
                  colors: appState.isRecording ? [
                    Color(red: 0.95, green: 0.25, blue: 0.25),  // Recording red
                    Color(red: 0.85, green: 0.1, blue: 0.1)
                  ] : [
                    Color(red: 0.9, green: 0.15, blue: 0.15),  // Idle red
                    Color(red: 0.7, green: 0.0, blue: 0.0)
                  ],
                  startPoint: .top,
                  endPoint: .bottom
                ),
                lineWidth: size * 0.08
              )
              .frame(width: size * 0.72, height: size * 0.72)
              // Subtle glow effect when recording
              .shadow(
                color: appState.isRecording ? Color.red.opacity(0.5) : Color.clear,
                radius: appState.isRecording ? 8 : 0
              )
              .opacity(appState.isRecording ? 1.0 : 0.7)  // Slightly dimmer when idle
              .scaleEffect(appState.isRecording && isPulsing ? 1.02 : 1.0)

            // 4. The Center Button (Physical Actor)
            // Morphs from Circle (Record) to RED Square (Stop)
            RoundedRectangle(cornerRadius: appState.isRecording ? 6 : size * 0.25)
              .fill(
                appState.isRecording ?
                  LinearGradient(
                    colors: [
                      Color(red: 0.9, green: 0.2, blue: 0.2),  // Red stop button
                      Color(red: 0.7, green: 0.1, blue: 0.1)
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                  ) :
                  LinearGradient(
                    colors: [
                      Color(white: 0.30),
                      Color(white: 0.18)
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
          .frame(width: size * 1.2, height: size * 1.2) // Constant frame to prevent layout shifts
        }
      )
      .buttonStyle(PremiumRecordButtonStyle())
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
          : String(localized: "recording.start", defaultValue: "Start recording"), key: "r",
        modifiers: [.command])
    )
    .onAppear {
      NSLog("🔴 UnifiedRecordButton: onAppear, isRecording = \(appState.isRecording)")
      // Setup continuous pulse animation loop
      withAnimation(.easeInOut(duration: 1.2).repeatForever(autoreverses: true)) {
        isPulsing = true
      }
    }
    .onChange(of: appState.isRecording) { _, isRecording in
      NSLog("🔴 UnifiedRecordButton: isRecording changed to \(isRecording)")
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
