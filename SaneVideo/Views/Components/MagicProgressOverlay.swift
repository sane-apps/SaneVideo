//
//  MagicProgressOverlay.swift
//  SaneVideo
//
//  Created by SaneVideo Refactor
//

import SwiftUI

struct MagicProgressOverlay: View {
  let isProcessing: Bool
  let status: String?
  let progress: Double

  // Smooth animation namespace
  @Namespace private var namespace

  var body: some View {
    Group {
      if isProcessing {
        HStack(spacing: 16) {
          // 1. Animated Icon
          ZStack {
            Circle()
              .fill(Theme.Colors.accent.opacity(0.2))
              .frame(width: 32, height: 32)

            Image(systemName: "sparkles")
              .font(.system(size: Theme.Typography.iconSizeSM, weight: .semibold))
              .foregroundStyle(Theme.Colors.accent)
              .symbolEffect(.bounce.up.byLayer, options: .repeating)
          }

          VStack(alignment: .leading, spacing: Theme.Dimensions.spacingXS) {
            // 2. Status Text (Animated transition)
            Text(status ?? "Processing...")
              .font(.system(size: Theme.Typography.fontSizeMD, weight: .medium))
              .foregroundStyle(.primary)
              .contentTransition(.numericText(value: 0))
              .animation(.snappy, value: status)
              .lineLimit(1)

            // 3. Progress Bar
            GeometryReader { geo in
              ZStack(alignment: .leading) {
                Capsule()
                  .fill(Color.primary.opacity(Theme.Opacity.light))
                  .frame(height: 4)

                Capsule()
                  .fill(Theme.Colors.accentGradient)
                  .frame(width: geo.size.width * CGFloat(progress), height: 4)
                  .animation(.smooth(duration: 0.4), value: progress)
              }
            }
            .frame(height: 4)
          }
          .frame(maxWidth: .infinity, alignment: .leading)

          // 4. Percentage text
          Text("\(Int(progress * 100))%")
            .font(.system(size: Theme.Typography.fontSizeSM, weight: .bold))
            .foregroundStyle(.secondary)
            .monospacedDigit()
            .contentTransition(.numericText())
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .frame(width: 320)
        .background(.ultraThinMaterial)
        .background(
          RoundedRectangle(cornerRadius: 30)
            .fill(Color(nsColor: .windowBackgroundColor).opacity(0.5))
        )
        .clipShape(RoundedRectangle(cornerRadius: 30))
        .overlay(
          RoundedRectangle(cornerRadius: 30)
            .stroke(Theme.Colors.accent.opacity(0.3), lineWidth: 1)
        )
        .shadow(color: Color.black.opacity(0.2), radius: 20, x: 0, y: 10)
        // Use a standard transition instead of asymmetric which might be causing type-check issues if too complex
        .transition(.move(edge: .top).combined(with: .opacity))
      }
    }
    .animation(.spring(response: 0.5, dampingFraction: 0.7), value: isProcessing)
    .padding(.top, 40)  // Position nicely below toolbar
    .accessibilityIdentifier(AccessibilityIdentifiers.magicProgressOverlay)
  }
}
