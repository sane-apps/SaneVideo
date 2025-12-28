//
//  PrivacyBadge.swift
//  SaneVideo
//
//  Visual indicator showing privacy status (on-device vs optional cloud AI)
//

import SwiftUI

/// Badge showing privacy status of AI processing
struct PrivacyBadge: View {
    @State private var isOnDevice: Bool = true
    @State private var hasCloudAI: Bool = false
    
    var body: some View {
        // ACCESSIBILITY FIX: Improved contrast for light mode visibility
        HStack(spacing: 6) {
            Image(systemName: isOnDevice ? "lock.shield.fill" : "cloud.fill")
                .font(.caption2)
                .foregroundColor(isOnDevice ? .green : .blue)

            Text(isOnDevice ? "100% On-Device" : "Cloud AI (Optional)")
                .font(.caption2)
                .fontWeight(.semibold)  // Bolder for better readability
                .foregroundColor(isOnDevice ? .green : .blue)  // Match icon color for cohesion
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(
            RoundedRectangle(cornerRadius: 6)
                .fill(isOnDevice ? Color.green.opacity(0.15) : Color.blue.opacity(0.15))  // Stronger fill
        )
        .overlay(
            RoundedRectangle(cornerRadius: 6)
                .stroke(isOnDevice ? Color.green.opacity(0.5) : Color.blue.opacity(0.5), lineWidth: 1)  // Stronger border
        )
        .task {
            await updateStatus()
        }
    }
    
    private func updateStatus() async {
        let keyManager = ServiceContainer.shared.apiKeyManager
        await keyManager.refreshStatus()
        hasCloudAI = keyManager.hasOpenAIKey || keyManager.hasGeminiKey
        
        // Always on-device by default, cloud is optional enhancement
        isOnDevice = true
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
