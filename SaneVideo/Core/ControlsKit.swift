import SwiftUI

// Note: RecordButton was removed - all code now uses UnifiedRecordButton
// See: PIP_CONTROLS_CONSOLIDATION.md for details

public struct IconCircleButton: View {
    public enum Size { case small, medium }
    let systemName: String
    let isActive: Bool
    let size: Size
    let helpText: String?
    public var action: () -> Void

    @State private var isHovering = false

    public init(systemName: String, isActive: Bool, size: Size = .medium, helpText: String? = nil, action: @escaping () -> Void) {
        self.systemName = systemName
        self.isActive = isActive
        self.size = size
        self.helpText = helpText
        self.action = action
    }

    public var body: some View {
        let dim: CGFloat = (size == .small) ? 44 : 64
        let iconSize: CGFloat = (size == .small) ? 18 : 24

        // Choose color based on icon type and state
        let activeColor: Color = {
            if systemName.contains("mic") { return .green }
            if systemName.contains("video") { return .blue }
            if systemName.contains("display") { return .orange }
            if systemName.contains("pause") || systemName.contains("play") { return .yellow }
            return .accentColor
        }()

        return Button(action: action) {
            ZStack {
                Circle()
                    .fill(isActive ? activeColor.opacity(0.25) : Color.black.opacity(0.2))
                    .frame(width: dim, height: dim)
                    .overlay(
                        Group {
                            if isActive {
                                Circle()
                                    .strokeBorder(activeColor.opacity(0.6), lineWidth: 2)
                            } else {
                                Circle()
                                    .strokeBorder(
                                        LinearGradient(
                                            colors: [
                                                .white.opacity(isHovering ? 0.3 : 0.1),
                                                .white.opacity(isHovering ? 0.1 : 0.05)
                                            ],
                                            startPoint: .topLeading,
                                            endPoint: .bottomTrailing
                                        ),
                                        lineWidth: 1
                                    )
                            }
                        }
                    )
                    .shadow(color: isActive ? activeColor.opacity(0.4) : Color.clear, radius: 8, x: 0, y: 0)

                Image(systemName: systemName)
                    .font(.system(size: iconSize, weight: .semibold))
                    .foregroundColor(isActive ? .white : .secondary)
                    .scaleEffect(isHovering ? 1.1 : 1.0)
                    .animation(.spring(response: 0.3, dampingFraction: 0.7), value: isHovering)
            }
        }
        .buttonStyle(.plain)
        .pressScale() // Enhanced press animation
        .onHover { hovering in
            withAnimation(.smoothUI) {
                isHovering = hovering
            }
            if hovering {
                ServiceContainer.shared.hapticsManager.selection()
            }
        }
        .simultaneousGesture(
            TapGesture().onEnded {
                ServiceContainer.shared.hapticsManager.impact()
            }
        )
        .help(helpText ?? "")
        .accessibilityIdentifier("control.\(systemName)")
    }
}

public struct RecBadgeTimer: View {
    let isRecording: Bool
    let timeString: String
    public init(isRecording: Bool, timeString: String) {
        self.isRecording = isRecording
        self.timeString = timeString
    }

    public var body: some View {
        VStack(spacing: 6) {
            HStack(spacing: 6) {
                if isRecording {
                    Circle()
                        .fill(Color.red)
                        .frame(width: 8, height: 8)
                    Text("REC")
                        .font(.caption2.weight(.semibold))
                        .foregroundColor(.secondary)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Color.red.opacity(0.12))
                        .clipShape(Capsule())
                }
            }
            Text(timeString)
                .font(.system(.body, design: .monospaced))
                .foregroundColor(.primary)
                .accessibilityIdentifier("record.timer")
        }
    }
}
