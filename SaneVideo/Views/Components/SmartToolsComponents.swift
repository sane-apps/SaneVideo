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
    VStack(alignment: .leading, spacing: Theme.Dimensions.spacingMD) {
      HStack(spacing: Theme.Dimensions.spacingSM) {
        Image(systemName: icon)
          .foregroundColor(color)
          .font(.system(size: Theme.Typography.iconSizeXS, weight: .semibold))
        Text(title.uppercased())
          .font(.system(size: Theme.Typography.fontSizeXS, weight: .bold))
          .foregroundColor(Color.stone)
          .tracking(0.5)
        Spacer()
      }

      content
    }
    .padding(Theme.Dimensions.paddingMD)
    .background(Color.stone.opacity(Theme.Opacity.subtle))
    .cornerRadius(Theme.Dimensions.cornerRadius)
    .overlay(
      RoundedRectangle(cornerRadius: Theme.Dimensions.cornerRadius)
        .stroke(Color.stone.opacity(Theme.Opacity.light), lineWidth: 0.5)
    )
    .enhancedLiquidGlass(radius: Theme.Dimensions.cornerRadius, opacity: Theme.Opacity.strong)
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
    HStack(alignment: .center, spacing: Theme.Dimensions.spacingMD) {
      // Icon - UX FIX: Better sizing and visual feedback
      Image(systemName: icon)
        .font(.system(size: Theme.Typography.iconSizeSM))
        .frame(width: 28, height: 28)
        .background(
          isOn ? color.opacity(Theme.Opacity.light) : Color.gray.opacity(Theme.Opacity.light)
        )
        .foregroundColor(isOn ? color : Color.stone)
        .cornerRadius(Theme.Dimensions.smallCornerRadius)

      // Text content - UX FIX: Improved typography and spacing
      VStack(alignment: .leading, spacing: Theme.Dimensions.spacingXS) {
        Text(title)
          .font(.system(size: Theme.Typography.fontSizeMD, weight: .semibold))
          .foregroundColor(.primary)
          .lineLimit(2)
          .multilineTextAlignment(.leading)
        Text(subtitle)
          .font(.system(size: Theme.Typography.fontSizeSM))
          .foregroundStyle(Color.stone)  // ACCESSIBILITY FIX: Use foregroundStyle for better adaptive contrast
          .opacity(0.8)  // Slightly stronger than default secondary
          .lineLimit(2)
          .multilineTextAlignment(.leading)
      }
      .frame(minWidth: 100, maxWidth: .infinity, alignment: .leading)

      // Spacer with minimum length
      Spacer(minLength: Theme.Dimensions.spacingXS)

      Toggle("", isOn: $isOn)
        .labelsHidden()
        .toggleStyle(.switch)
        .tint(Theme.Colors.accent)
        .accessibilityLabel(title)
        .accessibilityIdentifier(identifier ?? "Toggle_\(title)")
        .controlSize(.small)
    }
    .frame(minWidth: 160, maxWidth: .infinity, alignment: .leading)
    .padding(.vertical, Theme.Dimensions.spacingXS)
    .accessibilityIdentifier(
      identifier != nil
        ? "Row_\(identifier!.replacingOccurrences(of: "Toggle_", with: ""))" : "Row_\(title)")
  }
}
