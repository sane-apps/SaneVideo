import SwiftUI

// MARK: - Unified Control Button System
// All recording controls use this single button style for visual consistency.
// Sizes are designed to work across PiP (compact) and Main Window (full) contexts.

public struct IconCircleButton: View {
    public enum Size: Equatable {
        /// Tiny size for very small PiP (28pt) - minimalist
        case mini
        /// Compact size for PiP overlay (40pt) - fits in small spaces
        case small
        /// Standard size for main window controls (52pt)
        case medium
        /// Large size for primary actions (64pt)
        case large
        /// Custom size with proportional icon scaling
        case custom(CGFloat)

        public var diameter: CGFloat {
            switch self {
            case .mini: return 28    // Very compact for tiny PiP
            case .small: return 40   // Compact for PiP
            case .medium: return 52  // Standard controls
            case .large: return 64   // Primary actions
            case .custom(let val): return val
            }
        }

        public var iconSize: CGFloat {
            switch self {
            case .mini: return 12
            case .small: return 16
            case .medium: return 20
            case .large: return 24
            case .custom(let val): return val * 0.4
            }
        }

        /// Spacing between buttons at this size
        public var spacing: CGFloat {
            switch self {
            case .mini: return Theme.Dimensions.spacingXS    // 4pt
            case .small: return Theme.Dimensions.spacingSM   // 8pt
            case .medium: return Theme.Dimensions.spacingMD  // 12pt
            case .large: return Theme.Dimensions.spacingLG   // 16pt
            case .custom(let val): return val * 0.2
            }
        }

        /// Returns appropriate size for a given PiP window width
        public static func forPiPWidth(_ width: CGFloat) -> Size {
            switch width {
            case ..<250: return .mini
            case 250..<400: return .small
            default: return .medium
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
        self.activeColor = activeColor ?? Theme.Colors.accent
    }

    private var dim: CGFloat { size.diameter }

    // Consistent opacity values across all button states
    private var fillOpacity: Double {
        isActive ? Theme.Opacity.heavy : Theme.Opacity.medium  // 0.5 : 0.2
    }

    private var borderOpacity: Double {
        isActive ? 0.7 : Theme.Opacity.strong  // 0.7 : 0.3
    }

    public func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .frame(width: dim, height: dim)
            .contentShape(Circle())
            .background(
                ZStack {
                    // Glass background
                    Circle()
                        .fill(activeColor.opacity(fillOpacity))

                    // Border ring
                    Circle()
                        .strokeBorder(
                            activeColor.opacity(borderOpacity),
                            lineWidth: isActive ? 2 : 1
                        )
                }
            )
            // Glow effect when active
            .shadow(color: isActive ? activeColor.opacity(0.5) : .clear, radius: 10, x: 0, y: 0)
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
