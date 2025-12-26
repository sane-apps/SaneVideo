import SwiftUI

// Note: RecordButton was removed - all code now uses UnifiedRecordButton
// See: PIP_CONTROLS_CONSOLIDATION.md for details

public struct IconCircleButton: View {
    public enum Size: Equatable {
        case small, medium, custom(CGFloat)

        public var diameter: CGFloat {
            switch self {
            case .small: return 44
            case .medium: return 64
            case .custom(let val): return val
            }
        }

        public var iconSize: CGFloat {
            switch self {
            case .small: return 18
            case .medium: return 24
            case .custom(let val): return val * 0.375
            }
        }
    }

    let systemName: String
    let isActive: Bool
    let size: Size
    let helpText: String?
    let activeColor: Color?
    public var action: () -> Void

    private var isSmall: Bool {
        if case .small = size { return true }
        return false
    }

    @State private var isHovering = false

    public init(
        systemName: String,
        isActive: Bool,
        size: Size = .medium,
        activeColor: Color? = nil,
        helpText: String? = nil,
        action: @escaping () -> Void
    ) {
        self.systemName = systemName
        self.isActive = isActive
        self.size = size
        self.activeColor = activeColor
        self.helpText = helpText
        self.action = action
    }

    public var body: some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: size.iconSize, weight: .bold))
                .foregroundColor(.white)
        }
        .buttonStyle(IconCircleButtonStyle(size: size, isActive: isActive, activeColor: activeColor))
        .help(helpText ?? "")
        .accessibilityIdentifier("control.\(systemName)")
    }
}

/// Unified button style for icon buttons with consistent haptics and glass styling
public struct IconCircleButtonStyle: ButtonStyle {
    let size: IconCircleButton.Size
    let isActive: Bool
    let activeColor: Color

    @State private var isHovering = false

    public init(size: IconCircleButton.Size, isActive: Bool, activeColor: Color? = nil) {
        self.size = size
        self.isActive = isActive
        self.activeColor = activeColor ?? .accentColor
    }

    private var dim: CGFloat { size.diameter }

    public func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .frame(width: dim, height: dim)
            .contentShape(Circle())
            .background(
                ZStack {
                    if isActive {
                        Circle()
                            .fill(activeColor.opacity(0.5))
                    } else {
                        Circle()
                            .fill(activeColor.opacity(0.25)) // Increased from 0.15 to make it look "yellow" not "grey"
                    }

                    Circle()
                        .strokeBorder(
                            isActive ? activeColor.opacity(0.6) : activeColor.opacity(0.3),
                            lineWidth: isActive ? 2 : 1
                        )
                }
            )
            .shadow(color: isActive ? activeColor.opacity(0.4) : Color.clear, radius: 8, x: 0, y: 0)
            .scaleEffect(isHovering ? (configuration.isPressed ? 1.0 : 1.1) : (configuration.isPressed ? 0.95 : 1.0))
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

public struct RecBadgeTimer: View {
    let isRecording: Bool
    let timeString: String

    // Blinking animation state
    @State private var isBlinking: Bool = false

    public init(isRecording: Bool, timeString: String) {
        self.isRecording = isRecording
        self.timeString = timeString
    }

    public var body: some View {
        VStack(spacing: 6) {
            HStack(spacing: 6) {
                if isRecording {
                    // Blinking red dot with glow
                    Circle()
                        .fill(Color.red)
                        .frame(width: 10, height: 10)
                        .shadow(color: .red.opacity(0.8), radius: isBlinking ? 6 : 2)
                        .opacity(isBlinking ? 1.0 : 0.4)

                    Text("REC")
                        .font(.caption.weight(.bold))
                        .foregroundColor(.red)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(Color.red.opacity(0.15))
                        .clipShape(Capsule())
                }
            }
            .transition(.opacity.combined(with: .scale))

            Text(timeString)
                .font(.system(.title3, design: .monospaced).weight(.medium))
                .foregroundColor(isRecording ? .red : .primary)
                .accessibilityIdentifier("record.timer")
        }
        .onChange(of: isRecording) { _, recording in
            if recording {
                withAnimation(.easeInOut(duration: 0.6).repeatForever(autoreverses: true)) {
                    isBlinking = true
                }
            } else {
                withAnimation(.easeOut(duration: 0.2)) {
                    isBlinking = false
                }
            }
        }
        .onAppear {
            if isRecording {
                withAnimation(.easeInOut(duration: 0.6).repeatForever(autoreverses: true)) {
                    isBlinking = true
                }
            }
        }
    }
}
