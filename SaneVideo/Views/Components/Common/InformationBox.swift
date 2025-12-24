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
    var color: Color = .secondary
    var icon: String?

    var body: some View {
        HStack(spacing: 6) {
            if let icon = icon {
                Image(systemName: icon)
                    .font(.caption2)
                    .foregroundColor(color)
            }
            Text(text)
                .font(.caption2)
                .foregroundColor(.secondary)
        }
        .padding(6)
        .frame(maxWidth: .infinity, alignment: .leading)
        .subtleGlass(radius: 4) // Enhanced liquid glass
        .overlay(
            RoundedRectangle(cornerRadius: 4)
                .stroke(color.opacity(0.3), lineWidth: 0.5)
        )
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
        HStack {
            Label(label, systemImage: icon)
                .font(.caption)
            Spacer()
            Text(value)
                .font(.caption.weight(.medium))
                .foregroundStyle(color)
        }
        .padding(10)
        .subtleGlass(radius: 8) // Enhanced liquid glass
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(color.opacity(0.3), lineWidth: 1)
        )
        .shadow(color: color.opacity(0.1), radius: 4, x: 0, y: 2)
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
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
            }
            .padding(6)
            .frame(maxWidth: .infinity, alignment: .leading)
            .subtleGlass(radius: 4) // Enhanced liquid glass
        }
    }
}
