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
        if audioLevel > 0.7 { // Lowered threshold for better responsiveness
            return [.red, Color(red: 1.0, green: 0.3, blue: 0.3)] // Red (Clipping)
        } else if audioLevel > 0.4 {
            return [.yellow, .orange] // Yellow (Loud)
        } else {
            // Include Green for "Ideal" level feedback
            return [Color.green, Color(red: 0.4, green: 0.9, blue: 0.5)] 
        }
    }

    @State private var audioLevel: Float = 0.0
    @State private var rotation: Double = 0
    @State private var pulse: CGFloat = 1.0

    var body: some View {
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
                .animation(.linear(duration: 0.1), value: audioLevel) // Smooth color transition

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
                .animation(.linear(duration: 0.1), value: audioLevel) // Smooth color transition
        }
        .onAppear {
            // Slow rotation animation
            withAnimation(.linear(duration: 4).repeatForever(autoreverses: false)) {
                rotation = 360
            }
        }
        .onReceive(audioLevelPublisher.receive(on: DispatchQueue.main)) { level in
            // Smoothly animate the level update
            withAnimation(.linear(duration: 0.1)) {
                self.audioLevel = level
            }
        }
        .onReceive(Timer.publish(every: 0.1, on: .main, in: .common).autoconnect()) { _ in
            // Pulse based on audio level
            withAnimation(.easeInOut(duration: 0.1)) {
                pulse = 1.0 + CGFloat(audioLevel) * 0.05
            }
        }
    }
}
