//
//  SmartToolsComponents.swift
//  SaneVideo
//
//  Created by SaneVideo Refactor
//

import SwiftUI

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
    VStack(alignment: .leading, spacing: Theme.Dimensions.spacingSM) {
      HStack(spacing: Theme.Dimensions.spacingMD) {
        Image(systemName: icon)
          .foregroundColor(.white)
          .font(.system(size: Theme.Typography.iconSizeSM, weight: .bold))
          .frame(width: 26, height: 26)
          .background(color.opacity(0.95), in: RoundedRectangle(cornerRadius: 6, style: .continuous))
          .overlay(
            RoundedRectangle(cornerRadius: 6, style: .continuous)
              .stroke(Color.white.opacity(0.28), lineWidth: 1)
          )
        Text(title.uppercased())
          .font(.system(size: Theme.Typography.fontSizeXS, weight: .bold))
          .foregroundColor(.white)
          .tracking(0)
        Spacer()
      }

      content
    }
    .padding(Theme.Dimensions.paddingMD)
    .background(
      RoundedRectangle(cornerRadius: Theme.Dimensions.cornerRadius, style: .continuous)
        .fill(Color.white.opacity(0.075))
    )
    .cornerRadius(Theme.Dimensions.cornerRadius)
    .overlay(
      RoundedRectangle(cornerRadius: Theme.Dimensions.cornerRadius)
        .stroke(Color.white.opacity(0.18), lineWidth: 1)
    )
    .smoothAppear()
    .frame(minWidth: 160, maxWidth: .infinity)
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
    HStack(alignment: .center, spacing: Theme.Dimensions.spacingSM) {
      Image(systemName: icon)
        .font(.system(size: Theme.Typography.iconSizeSM, weight: .semibold))
        .frame(width: 28, height: 28)
        .background(
          RoundedRectangle(cornerRadius: 8, style: .continuous)
            .fill(isOn ? color.opacity(0.95) : Color.white.opacity(0.13))
        )
        .foregroundColor(.white)
        .overlay(
          RoundedRectangle(cornerRadius: 8, style: .continuous)
            .stroke(isOn ? Color.white.opacity(0.32) : Color.white.opacity(0.18), lineWidth: 1)
        )
        .shadow(color: isOn ? color.opacity(0.25) : .clear, radius: 5, x: 0, y: 2)

      VStack(alignment: .leading, spacing: 2) {
        Text(title)
          .font(.system(size: Theme.Typography.fontSizeSM, weight: .semibold))
          .foregroundColor(.white)
          .lineLimit(1)
          .minimumScaleFactor(0.82)
          .allowsTightening(true)
          .multilineTextAlignment(.leading)
        Text(subtitle)
          .font(.system(size: Theme.Typography.fontSizeXS))
          .foregroundStyle(.white.opacity(0.92))
          .lineLimit(2)
          .multilineTextAlignment(.leading)
      }
      .layoutPriority(1)
      .frame(maxWidth: .infinity, alignment: .leading)

      Toggle("", isOn: $isOn)
        .labelsHidden()
        .toggleStyle(.switch)
        .tint(Theme.Colors.accent)
        .accessibilityLabel(title)
        .accessibilityIdentifier(identifier ?? "Toggle_\(title)")
        .controlSize(.small)
    }
    .frame(minWidth: 160, maxWidth: .infinity, alignment: .leading)
    .padding(.vertical, 6)
    .padding(.horizontal, 6)
    .background(
      RoundedRectangle(cornerRadius: 8, style: .continuous)
        .fill(isOn ? Color.white.opacity(0.055) : Color.white.opacity(0.035))
    )
    .overlay(
      RoundedRectangle(cornerRadius: 8, style: .continuous)
        .stroke(Color.white.opacity(isOn ? 0.14 : 0.08), lineWidth: 1)
    )
    .accessibilityIdentifier(
      identifier != nil
        ? "Row_\(identifier!.replacingOccurrences(of: "Toggle_", with: ""))" : "Row_\(title)")
  }
}
