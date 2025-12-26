import Combine
import SwiftUI

/// Audio level indicator displayed as a subtle animated ring around the mic button
/// Uses Theme colors for visual consistency across the app
struct AudioVisualizerView: View {
    var audioLevelPublisher: AnyPublisher<Float, Never>
    var size: CGFloat = 70

    // Industry standard VU meter colors:
    // Green = normal/safe, Yellow = loud/hot, Red = clipping
    private var meteringColors: [Color] {
        if audioLevel > 0.85 {
            // RED: Clipping / Too loud - danger zone
            return [Color(red: 1.0, green: 0.2, blue: 0.2), Color(red: 0.9, green: 0.1, blue: 0.1)]
        } else if audioLevel > 0.6 {
            // YELLOW/ORANGE: Getting loud - caution
            return [Color(red: 1.0, green: 0.8, blue: 0.0), Color(red: 1.0, green: 0.6, blue: 0.0)]
        } else {
            // GREEN: Normal level - safe
            return [Color(red: 0.2, green: 0.9, blue: 0.3), Color(red: 0.1, green: 0.8, blue: 0.2)]
        }
    }

    @State private var audioLevel: Float = 0.0
    @State private var rotation: Double = 0
    @State private var pulse: CGFloat = 1.0
    @State private var isActive = false
    @State private var cancellable: AnyCancellable?

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

            // CRASH FIX: Store cancellable explicitly so we can cancel on disappear
            // Using weak self pattern to prevent retain cycles
            cancellable = audioLevelPublisher
                .receive(on: DispatchQueue.main)
                .sink { [self] level in
                    guard isActive else { return }
                    audioLevel = level
                    pulse = 1.0 + CGFloat(level) * 0.05
                }
        }
        .onDisappear {
            // CRASH FIX: Cancel subscription BEFORE marking inactive
            // This prevents any pending callbacks from firing
            cancellable?.cancel()
            cancellable = nil
            isActive = false
        }
    }
}
