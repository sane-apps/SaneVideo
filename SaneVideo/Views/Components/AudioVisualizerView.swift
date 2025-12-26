import Combine
import SwiftUI

/// Audio level indicator displayed as a subtle animated ring around the mic button
struct AudioVisualizerView: View {
    var audioLevelPublisher: AnyPublisher<Float, Never>
    var size: CGFloat = 70
    var colors: [Color] = [
        Color(red: 0.4, green: 0.9, blue: 1.0), // Cyan
        Color(red: 0.3, green: 0.7, blue: 1.0), // Light blue
        Color(red: 0.5, green: 0.8, blue: 0.9) // Aqua
    ]

    // Dynamic color based on audio level (VU Meter Logic)
    private var meteringColors: [Color] {
        if audioLevel > 0.9 { // Higher threshold for peak clipping
            return [.red, Color(red: 1.0, green: 0.3, blue: 0.3)] // Red (Clipping)
        } else if audioLevel > 0.7 { // Higher threshold for yellow (loud)
            return [.yellow, .orange] // Yellow (Loud)
        } else {
            // Reverted to green for "Ideal" level feedback as per user request
            return [.green, Color.green.opacity(0.8)]
        }
    }

    @State private var audioLevel: Float = 0.0
    @State private var rotation: Double = 0
    @State private var pulse: CGFloat = 1.0
    @State private var isActive = false

    var body: some View {
        // CRASH FIX: Using TimelineView to avoid Timer.publish() lifecycle issues.
        // The previous implementation used Timer.publish().autoconnect() which
        // caused SIGSEGV crashes when the view was removed while the timer was active.
        // The timer's subscription could outlive the view, leading to accessing
        // deallocated memory during MainActor isolation checks.
        TimelineView(.periodic(from: .now, by: 0.1)) { _ in
            ZStack {
                // Outer glow based on audio level
                Circle()
                    .stroke(
                        AngularGradient(
                            gradient: Gradient(colors: meteringColors),
                            center: .center,
                            startAngle: .degrees(rotation),
                            endAngle: .degrees(rotation + 360)
                        ),
                        lineWidth: 3 + CGFloat(audioLevel) * 4
                    )
                    .frame(width: size * pulse, height: size * pulse)
                    .opacity(0.6 + Double(audioLevel) * 0.4)
                    .blur(radius: 2)

                // Sharp ring
                Circle()
                    .stroke(
                        AngularGradient(
                            gradient: Gradient(colors: meteringColors),
                            center: .center,
                            startAngle: .degrees(rotation),
                            endAngle: .degrees(rotation + 360)
                        ),
                        lineWidth: 2 + CGFloat(audioLevel) * 2
                    )
                    .frame(width: size, height: size)
                    .opacity(0.8)
            }
            .animation(.linear(duration: 0.1), value: audioLevel)
            .animation(.easeInOut(duration: 0.1), value: pulse)
        }
        .onAppear {
            isActive = true
            // Slow rotation animation
            withAnimation(.linear(duration: 4).repeatForever(autoreverses: false)) {
                rotation = 360
            }
        }
        .onDisappear {
            isActive = false
        }
        .onReceive(audioLevelPublisher.receive(on: DispatchQueue.main)) { level in
            guard isActive else { return }
            audioLevel = level
            pulse = 1.0 + CGFloat(level) * 0.05
        }
    }
}
