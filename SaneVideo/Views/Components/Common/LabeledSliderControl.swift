//
//  LabeledSliderControl.swift
//  SaneVideo
//
//  Reusable slider control with label, value display, and range hints
//

import SwiftUI

/// A slider with header label, current value display, and optional range hints
struct LabeledSliderControl: View {
    let label: String
    @Binding var value: Double
    let range: ClosedRange<Double>
    let step: Double
    let valueFormatter: (Double) -> String
    var minLabel: String?
    var maxLabel: String?
    let accessibilityID: String

    init(
        label: String,
        value: Binding<Double>,
        range: ClosedRange<Double>,
        step: Double = 0.1,
        valueFormatter: @escaping (Double) -> String,
        minLabel: String? = nil,
        maxLabel: String? = nil,
        accessibilityID: String
    ) {
        self.label = label
        self._value = value
        self.range = range
        self.step = step
        self.valueFormatter = valueFormatter
        self.minLabel = minLabel
        self.maxLabel = maxLabel
        self.accessibilityID = accessibilityID
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(label)
                    .font(.caption)
                Spacer()
                Text(valueFormatter(value))
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(Color.stone)
            }

            Slider(value: $value, in: range, step: step)
                .accessibilityIdentifier(accessibilityID)

            if minLabel != nil || maxLabel != nil {
                HStack {
                    if let minLabel = minLabel {
                        Text(minLabel)
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                    }
                    Spacer()
                    if let maxLabel = maxLabel {
                        Text(maxLabel)
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                    }
                }
            }
        }
    }
}

/// Integer version of LabeledSliderControl
struct LabeledIntSliderControl: View {
    let label: String
    @Binding var value: Int
    let range: ClosedRange<Int>
    let valueFormatter: (Int) -> String
    var minLabel: String?
    var maxLabel: String?
    let accessibilityID: String

    @State private var doubleValue: Double = 0

    init(
        label: String,
        value: Binding<Int>,
        range: ClosedRange<Int>,
        valueFormatter: @escaping (Int) -> String = { "\($0)" },
        minLabel: String? = nil,
        maxLabel: String? = nil,
        accessibilityID: String
    ) {
        self.label = label
        self._value = value
        self.range = range
        self.valueFormatter = valueFormatter
        self.minLabel = minLabel
        self.maxLabel = maxLabel
        self.accessibilityID = accessibilityID
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(label)
                    .font(.caption)
                Spacer()
                Text(valueFormatter(value))
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(Color.stone)
            }

            Slider(
                value: Binding(
                    get: { Double(value) },
                    set: { value = Int($0) }
                ),
                in: Double(range.lowerBound)...Double(range.upperBound),
                step: 1
            )
            .accessibilityIdentifier(accessibilityID)

            if minLabel != nil || maxLabel != nil {
                HStack {
                    if let minLabel = minLabel {
                        Text(minLabel)
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                    }
                    Spacer()
                    if let maxLabel = maxLabel {
                        Text(maxLabel)
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                    }
                }
            }
        }
    }
}
