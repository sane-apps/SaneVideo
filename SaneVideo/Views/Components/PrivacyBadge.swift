//
//  PrivacyBadge.swift
//  SaneVideo
//
//  Visual indicator showing privacy status (on-device vs optional cloud AI)
//

import SwiftUI

/// Badge showing privacy status of AI processing - always 100% on-device
struct PrivacyBadge: View {
    var body: some View {
        // ACCESSIBILITY FIX: Improved contrast for light mode visibility
        HStack(spacing: 6) {
            Image(systemName: "lock.shield.fill")
                .font(.caption2)
                .foregroundColor(.green)

            Text("100% On-Device")
                .font(.caption2)
                .fontWeight(.semibold)
                .foregroundColor(.green)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(
            RoundedRectangle(cornerRadius: 6)
                .fill(Color.green.opacity(0.15))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 6)
                .stroke(Color.green.opacity(0.5), lineWidth: 1)
        )
    }
}

/// Compact privacy indicator for settings
struct CompactPrivacyBadge: View {
    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: "lock.shield.fill")
                .font(.caption2)
                .foregroundColor(.green)
            Text("On-Device")
                .font(.caption2)
                .foregroundColor(.secondary)
        }
    }
}
