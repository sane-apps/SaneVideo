//
//  ExportSpeedTracker.swift
//  SaneVideo
//
//  Tracks export speed and estimates time remaining
//

import Foundation

@MainActor
@Observable
class ExportSpeedTracker {
    
    struct SpeedMetrics: Sendable {
        let currentSpeedMBps: Double
        let averageSpeedMBps: Double
        let estimatedTimeRemaining: TimeInterval
        let bytesProcessed: Int64
        let totalBytes: Int64
    }
    
    private var startTime: Date?
    private var lastUpdateTime: Date?
    private var lastBytesProcessed: Int64 = 0
    private var speedHistory: [Double] = []
    private let maxHistorySize = 10
    
    private(set) var currentMetrics: SpeedMetrics?
    
    func startTracking(totalBytes: Int64) {
        startTime = Date()
        lastUpdateTime = Date()
        lastBytesProcessed = 0
        speedHistory.removeAll()
    }
    
    func update(bytesProcessed: Int64, totalBytes: Int64) {
        guard let lastUpdate = lastUpdateTime else { return }
        
        let now = Date()
        let timeDelta = now.timeIntervalSince(lastUpdate)
        
        guard timeDelta > 0.1 else { return } // Update at most every 100ms
        
        let bytesDelta = bytesProcessed - lastBytesProcessed
        let currentSpeedMBps = Double(bytesDelta) / timeDelta / 1_000_000.0
        
        // Add to history
        speedHistory.append(currentSpeedMBps)
        if speedHistory.count > maxHistorySize {
            speedHistory.removeFirst()
        }
        
        // Calculate average
        let averageSpeedMBps = speedHistory.reduce(0, +) / Double(speedHistory.count)
        
        // Estimate time remaining
        let remainingBytes = totalBytes - bytesProcessed
        let estimatedTimeRemaining = averageSpeedMBps > 0 
            ? Double(remainingBytes) / 1_000_000.0 / averageSpeedMBps
            : 0
        
        currentMetrics = SpeedMetrics(
            currentSpeedMBps: currentSpeedMBps,
            averageSpeedMBps: averageSpeedMBps,
            estimatedTimeRemaining: estimatedTimeRemaining,
            bytesProcessed: bytesProcessed,
            totalBytes: totalBytes
        )
        
        lastUpdateTime = now
        lastBytesProcessed = bytesProcessed
    }
    
    func reset() {
        startTime = nil
        lastUpdateTime = nil
        lastBytesProcessed = 0
        speedHistory.removeAll()
        currentMetrics = nil
    }
    
    func formatTimeRemaining(_ seconds: TimeInterval) -> String {
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
    
    func formatSpeed(_ mbps: Double) -> String {
        if mbps < 1.0 {
            return String(format: "%.1f MB/s", mbps)
        } else {
            return String(format: "%.0f MB/s", mbps)
        }
    }
}

