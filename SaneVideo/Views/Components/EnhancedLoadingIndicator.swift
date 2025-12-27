//
//  EnhancedLoadingIndicator.swift
//  SaneVideo
//
//  Enhanced loading indicator with speed and time remaining
//

import SwiftUI

struct EnhancedLoadingIndicator: View {
    let message: String
    let progress: Double
    var speedMBps: Double?
    var timeRemaining: TimeInterval?
    var currentOperation: String?
    
    var body: some View {
        VStack(spacing: 12) {
            // Progress bar
            ProgressView(value: progress)
                .progressViewStyle(.linear)
                .frame(width: 300)
            
            // Message and details
            VStack(spacing: 4) {
                Text(message)
                    .font(.headline)
                
                if let operation = currentOperation {
                    Text(operation)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                
                // Speed and time remaining
                HStack(spacing: 16) {
                    if let speed = speedMBps, speed > 0 {
                        Label("\(String(format: "%.1f", speed)) MB/s", systemImage: "speedometer")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    
                    if let remaining = timeRemaining, remaining > 0 {
                        Label(formatTime(remaining), systemImage: "clock")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
        .padding()
        .background(.ultraThinMaterial)
        .cornerRadius(12)
        .shadow(radius: 8)
    }
    
    private func formatTime(_ seconds: TimeInterval) -> String {
        if seconds < 60 {
            return String(format: "%.0fs", seconds)
        } else if seconds < 3600 {
            let minutes = Int(seconds) / 60
            let secs = Int(seconds) % 60
            return "\(minutes)m \(secs)s"
        } else {
            let hours = Int(seconds) / 3600
            let minutes = (Int(seconds) % 3600) / 60
            return "\(hours)h \(minutes)m"
        }
    }
}
