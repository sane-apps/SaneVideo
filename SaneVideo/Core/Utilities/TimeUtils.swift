//
//  TimeUtils.swift
//  SaneVideo
//
//  Created by Antigravity
//

import Foundation
import CoreMedia

struct TimeUtils {
    /// Formats a duration in seconds into a string (e.g., "0:12" or "1:02:34")
    static func formatDuration(_ duration: TimeInterval) -> String {
        let hours = Int(duration) / 3600
        let minutes = (Int(duration) % 3600) / 60
        let seconds = Int(duration) % 60
        if hours > 0 {
            return String(format: "%d:%02d:%02d", hours, minutes, seconds)
        } else {
            return String(format: "%02d:%02d", minutes, seconds)
        }
    }

    /// Formats a CMTime into a string (e.g., "0:12")
    static func formatDuration(_ time: CMTime) -> String {
        let seconds = CMTimeGetSeconds(time)
        guard !seconds.isNaN && !seconds.isInfinite else { return "0:00" }
        return formatDuration(seconds)
    }

    /// Formats a duration for performance insights (e.g., "1.2s" or "3m 45s")
    static func formatInsightDuration(_ duration: TimeInterval) -> String {
        if duration < 60 {
            return String(format: "%.1fs", duration)
        } else {
            let minutes = Int(duration) / 60
            let seconds = Int(duration) % 60
            return "\(minutes)m \(seconds)s"
        }
    }
}
