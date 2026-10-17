import SwiftUI

/// A titled group inside an inspector section; no border, so sections never nest boxes.
struct ToolCard<Content: View>: View {
  let title: String
  let icon: String
  let color: Color
  let content: Content

  init(title: String, icon: String, color: Color, @ViewBuilder content: () -> Content) {
    self.title = title
    self.icon = icon
    self.color = color
    self.content = content()
  }

  var body: some View {
    VStack(alignment: .leading, spacing: 8) {
      Text(title)
        .font(.system(size: 13, weight: .semibold))
        .foregroundStyle(Theme.Colors.textPrimary.opacity(0.85))
      content
    }
    .frame(minWidth: 160, maxWidth: .infinity, alignment: .leading)
  }
}

struct InspectorToggle: View {
  let title: String
  let subtitle: String
  @Binding var isOn: Bool
  let icon: String
  var color: Color = Theme.Colors.accent
  var identifier: String?

  var body: some View {
    HStack(alignment: .center, spacing: 10) {
      Image(systemName: icon)
        .font(.system(size: 14, weight: .medium))
        .foregroundStyle(isOn ? Theme.Colors.accent : Theme.Colors.textPrimary.opacity(0.7))
        .frame(width: 20)

      VStack(alignment: .leading, spacing: 1) {
        Text(title)
          .font(.system(size: 14, weight: .medium))
          .foregroundStyle(Theme.Colors.textPrimary)
          .lineLimit(1)
        Text(subtitle)
          .font(.system(size: 13))
          .foregroundStyle(Theme.Colors.textPrimary.opacity(0.8))
          .lineLimit(2)
      }
      .layoutPriority(1)
      .frame(maxWidth: .infinity, alignment: .leading)

      Toggle("", isOn: $isOn)
        .labelsHidden()
        .toggleStyle(.switch)
        .accessibilityLabel(title)
        .accessibilityIdentifier(identifier ?? "Toggle_\(title)")
        .controlSize(.small)
    }
    .frame(minWidth: 160, maxWidth: .infinity, alignment: .leading)
    .padding(.vertical, 6)
    .accessibilityIdentifier(
      identifier.map { "Row_\($0.replacingOccurrences(of: "Toggle_", with: ""))" } ?? "Row_\(title)")
  }
}
