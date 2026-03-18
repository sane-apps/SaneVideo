//
//  InformationBox.swift
//  SaneVideo
//
//  Reusable information/result display box with colored background
//

import SwiftUI

/// A styled box for displaying analysis results, status messages, etc.
struct InformationBox: View {
    let text: String
    var color: Color = Color.stone
    var icon: String?

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            if let icon = icon {
                Image(systemName: icon)
                    .font(.system(size: Theme.Typography.iconSizeSM, weight: .semibold))
                    .foregroundStyle(color)
                    .padding(.top, 1)
            }
            Text(text)
                .saneReadableSupportText()
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .sanePanel(radius: 10, accent: color)
        .smoothAppear()
    }
}

/// A styled box for displaying estimated values (e.g., file size)
struct EstimateBox: View {
    let label: String
    let value: String
    var icon: String = "doc.fill"
    var color: Color = .orange

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Label(label, systemImage: icon)
                    .saneReadableLabel()
                Spacer()
                Text(value)
                    .saneReadableMeta(monospaced: true)
                    .foregroundStyle(color)
            }

            HelperText(
                text: "Use this estimate to sanity-check file size before you export.",
                icon: "externaldrive.fill.badge.checkmark",
                color: color
            )
        }
        .padding(12)
        .sanePanel(radius: 12, accent: color)
        .smoothAppear()
    }
}

/// A list of detected items (e.g., OCR results)
struct DetectedItemsList: View {
    let items: [String]
    var maxItems: Int = 3
    var color: Color = .blue

    var body: some View {
        if !items.isEmpty {
            VStack(alignment: .leading, spacing: 2) {
                ForEach(items.prefix(maxItems), id: \.self) { item in
                    Text("• \(item)")
                        .saneReadableSupportText()
                }
            }
            .padding(10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .sanePanel(radius: 10, accent: color)
        }
    }
}
