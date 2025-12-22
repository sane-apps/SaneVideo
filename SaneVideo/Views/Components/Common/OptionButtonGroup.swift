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
                .tint(selected == option ? tintColor : .secondary)
                .accessibilityIdentifier("\(accessibilityPrefix).\(option)")
            }
        }
    }
}

/// Integer-specific option button group
struct IntOptionButtonGroup: View {
    let options: [Int]
    @Binding var selected: Int
    let labelFormatter: (Int) -> String
    let accessibilityPrefix: String
    var tintColor: Color = .blue

    init(
        options: [Int],
        selected: Binding<Int>,
        labelFormatter: @escaping (Int) -> String = { "\($0)" },
        accessibilityPrefix: String,
        tintColor: Color = .blue
    ) {
        self.options = options
        self._selected = selected
        self.labelFormatter = labelFormatter
        self.accessibilityPrefix = accessibilityPrefix
        self.tintColor = tintColor
    }

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
                .tint(selected == option ? tintColor : .secondary)
                .accessibilityIdentifier("\(accessibilityPrefix).\(option)")
            }
        }
    }
}

/// Double-specific option button group for speed presets, etc.
struct DoubleOptionButtonGroup: View {
    let options: [Double]
    @Binding var selected: Double
    let labelFormatter: (Double) -> String
    let accessibilityPrefix: String
    var tintColor: Color = .blue

    init(
        options: [Double],
        selected: Binding<Double>,
        labelFormatter: @escaping (Double) -> String = { String(format: "%.1fx", $0) },
        accessibilityPrefix: String,
        tintColor: Color = .blue
    ) {
        self.options = options
        self._selected = selected
        self.labelFormatter = labelFormatter
        self.accessibilityPrefix = accessibilityPrefix
        self.tintColor = tintColor
    }

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
                .tint(abs(selected - option) < 0.01 ? tintColor : .secondary)
                .accessibilityIdentifier("\(accessibilityPrefix).\(option)")
            }
        }
    }
}
