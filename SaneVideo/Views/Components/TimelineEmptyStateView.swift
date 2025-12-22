//
//  TimelineEmptyStateView.swift
//  SaneVideo
//
//  Created by SaneVideo Refactor
//

import SwiftUI

struct TimelineEmptyStateView: View {
    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: "square.app.dashed")
                .font(.system(size: 24))
                .foregroundColor(.secondary.opacity(0.5))
            
            Text("Drop media clips here to start your project")
                .font(.system(size: 13))
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(white: 0.08))
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Empty Timeline. Drop video clips here to start.")
        .accessibilityIdentifier("TimelineEmptyState")
    }
}

#Preview {
    TimelineEmptyStateView()
        .frame(width: 600, height: 300)
}
