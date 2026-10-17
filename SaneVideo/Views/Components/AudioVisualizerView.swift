import Combine
import SwiftUI

/// Audio level indicator displayed as a subtle animated ring around the mic button
struct AudioVisualizerView: View {
    var audioLevelPublisher: AnyPublisher<Float, Never>
    var size: CGFloat = 70

    // VU meter colors: green is safe, yellow is loud, red is clipping.
    private var meteringColors: [Color] {
        if audioLevel > 0.85 {
            return [Color(red: 1.0, green: 0.2, blue: 0.2), Color(red: 0.9, green: 0.1, blue: 0.1)]
        } else if audioLevel > 0.6 {
            return [Color(red: 1.0, green: 0.8, blue: 0.0), Color(red: 1.0, green: 0.6, blue: 0.0)]
        } else {
            return [Color(red: 0.2, green: 0.9, blue: 0.3), Color(red: 0.1, green: 0.8, blue: 0.2)]
        }
    }

    @State private var audioLevel: Float = 0.0
    @State private var pulse: CGFloat = 1.0
    @State private var isActive = false
    @State private var cancellable: AnyCancellable?

    var body: some View {
        ZStack {
            Circle()
                .stroke(
                    AngularGradient(
                        gradient: Gradient(colors: meteringColors),
                        center: .center,
                        startAngle: .degrees(0),
                        endAngle: .degrees(360)
                    ),
                    lineWidth: 3 + CGFloat(audioLevel) * 4
                )
                .frame(width: size * pulse, height: size * pulse)
                .opacity(0.6 + Double(audioLevel) * 0.4)
                .blur(radius: 2)

            Circle()
                .stroke(
                    AngularGradient(
                        gradient: Gradient(colors: meteringColors),
                        center: .center,
                        startAngle: .degrees(0),
                        endAngle: .degrees(360)
                    ),
                    lineWidth: 2 + CGFloat(audioLevel) * 2
                )
                .frame(width: size, height: size)
                .opacity(0.8)
        }
        .animation(.linear(duration: 0.1), value: audioLevel)
        .animation(.easeInOut(duration: 0.1), value: pulse)
        .onAppear {
            isActive = true

            // Store the subscription so it can be cancelled on disappear.
            cancellable = audioLevelPublisher
                .receive(on: DispatchQueue.main)
                .sink { [self] level in
                    guard isActive else { return }
                    audioLevel = level
                    pulse = 1.0 + CGFloat(level) * 0.05
                }
        }
        .onDisappear {
            // Cancel the subscription before marking inactive so no pending callbacks fire.
            cancellable?.cancel()
            cancellable = nil
            isActive = false
        }
    }
}
