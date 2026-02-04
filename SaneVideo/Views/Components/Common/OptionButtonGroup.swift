//
//  OptionButtonGroup.swift
//  SaneVideo
//
//  Reusable horizontal button group for selecting from preset options
//

import SwiftUI

/// A horizontal row of option buttons for selecting presets (e.g., FPS, width, speed)
struct OptionButtonGroup<T: Hashable>: View {
    let options: [T]
    @Binding var selected: T
    let labelFormatter: (T) -> String
    let accessibilityPrefix: String
    var tintColor: Color = .blue

    var body: some View {
        HStack(spacing: 8) {
            ForEach(options, id: \.self) { option in
                Button {
                    selected = option
                } label: {
                    Text(labelFormatter(option))
                        .font(.caption)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 6)
                }
                .buttonStyle(.bordered)
                .tint(selected == option ? tintColor : Color.stone)
                .accessibilityIdentifier("\(accessibilityPrefix).\(option)")
            }
        }
    }
}

// Note: IntOptionButtonGroup and DoubleOptionButtonGroup were removed
// as they were unused. The generic OptionButtonGroup<T: Hashable> handles all cases.
