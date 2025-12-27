//
//  ExportProgressView.swift
//  SaneVideo
//
//  Enhanced export progress display with speed metrics and thermal status
//

import SwiftUI

/// Enhanced export progress view with performance metrics
struct ExportProgressView: View {
    let progress: Double
    let isExporting: Bool
    let speedTracker: ExportSpeedTracker?
    
    var body: some View {
        VStack(spacing: 12) {
            // Progress bar
            ProgressView(value: progress)
                .progressViewStyle(.linear)
            
            // Performance metrics
            if let metrics = speedTracker?.currentMetrics, isExporting {
                HStack(spacing: 16) {
                    // Export speed
                    HStack(spacing: 4) {
                        Image(systemName: "speedometer")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                        Text(speedTracker?.formatSpeed(metrics.averageSpeedMBps) ?? "Calculating...")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    
                    // Time remaining
                    if metrics.estimatedTimeRemaining > 0 {
                        HStack(spacing: 4) {
                            Image(systemName: "clock")
                                .font(.caption2)
                                .foregroundColor(.secondary)
                            Text(speedTracker?.formatTimeRemaining(metrics.estimatedTimeRemaining) ?? "")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }
                    
                    Spacer()
                    
                    // Thermal indicator (compact)
                    CompactThermalIndicator()
                }
            }
            
            // Progress percentage
            Text("\(Int(progress * 100))%")
                .font(.caption)
                .foregroundColor(.secondary)
        }
    }
}
