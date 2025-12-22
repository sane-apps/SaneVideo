//
//  TimecodeFormatter.swift
//  SaneVideo
//
//  Utility for formatting time values for display

import AVFoundation
import Foundation

/// Formats time values for consistent display across the app
enum TimecodeFormatter {
    /// Format CMTime as timecode string (HH:MM:SS)
    /// - Parameter time: CMTime to format
    /// - Returns: Formatted string like "00:12:34"
    static func format(_ time: CMTime) -> String {
        let seconds = time.seconds
        return format(seconds)
    }

    /// Format TimeInterval as timecode string (HH:MM:SS)
    /// - Parameter interval: TimeInterval to format
    /// - Returns: Formatted string like "00:12:34"
    static func format(_ interval: TimeInterval) -> String {
        guard interval.isFinite, !interval.isNaN else {
            return "00:00:00"
        }

        let totalSeconds = Int(interval)
        let hours = totalSeconds / 3600
        let minutes = (totalSeconds % 3600) / 60
        let seconds = totalSeconds % 60

        return String(format: "%02d:%02d:%02d", hours, minutes, seconds)
    }

    /// Format CMTime as short timecode (MM:SS) for durations under 1 hour
    /// - Parameter time: CMTime to format
    /// - Returns: Formatted string like "12:34"
    static func formatShort(_ time: CMTime) -> String {
        let seconds = time.seconds
        return formatShort(seconds)
    }

    /// Format TimeInterval as short timecode (MM:SS)
    /// - Parameter interval: TimeInterval to format
    /// - Returns: Formatted string like "12:34"
    static func formatShort(_ interval: TimeInterval) -> String {
        guard interval.isFinite, !interval.isNaN else {
            return "00:00"
        }

        let totalSeconds = Int(interval)
        let minutes = totalSeconds / 60
        let seconds = totalSeconds % 60

        return String(format: "%02d:%02d", minutes, seconds)
    }

    /// Parse timecode string into TimeInterval
    /// - Parameter timecode: String in format "HH:MM:SS" or "MM:SS"
    /// - Returns: TimeInterval or nil if invalid format
    static func parse(_ timecode: String) -> TimeInterval? {
        let components = timecode.split(separator: ":").compactMap { Int($0) }

        switch components.count {
        case 2: // MM:SS
            return TimeInterval(components[0] * 60 + components[1])
        case 3: // HH:MM:SS
            return TimeInterval(components[0] * 3600 + components[1] * 60 + components[2])
        default:
            return nil
        }
    }
}
