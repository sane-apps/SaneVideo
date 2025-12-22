//
//  TimelineEmptyStateView.swift
//  SaneVideo
//
//  Created by SaneVideo Refactor
//

import SwiftUI

struct TimelineEmptyStateView: View {
    var body: some View {
        VStack(spacing: 16) {
            ZStack {
                Circle()
                    .fill(Color.secondary.opacity(0.1))
                    .frame(width: 80, height: 80)
                
                Image(systemName: "plus")
                    .font(.system(size: 32, weight: .semibold))
                    .foregroundColor(.secondary)
            }
            .overlay(
                RoundedRectangle(cornerRadius: 16)
                    .stroke(style: StrokeStyle(lineWidth: 2, dash: [6]))
                    .foregroundColor(.secondary.opacity(0.3))
                    .frame(width: 120, height: 120)
            )

            VStack(spacing: 6) {
                Text("Start Your Project")
                    .font(.headline)
                    .foregroundColor(.primary)
                
                Text("Drop video clips here or press ⌘I to import")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(white: 0.1))
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Empty Timeline. Drop video clips here to start.")
        .accessibilityIdentifier("TimelineEmptyState")
    }
}

#Preview {
    TimelineEmptyStateView()
        .frame(width: 600, height: 300)
}
