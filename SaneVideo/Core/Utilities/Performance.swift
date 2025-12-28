//
//  Performance.swift
//  SaneVideo
//
//  Performance monitoring with os_signpost for Apple Silicon optimization
//  Use with Instruments -> Points of Interest

import Foundation
import os.signpost

/// Centralized performance monitoring for Apple Silicon optimization
enum PerformanceMonitor {
    // MARK: - Signpost Loggers

    /// Export operations signpost logger
    static let exportLog = OSLog(subsystem: "com.sanevideo.app", category: "Export")

    /// Capture operations signpost logger
    static let captureLog = OSLog(subsystem: "com.sanevideo.app", category: "Capture")

    /// Playback operations signpost logger
    static let playbackLog = OSLog(subsystem: "com.sanevideo.app", category: "Playback")

    /// Filter operations signpost logger
    static let filterLog = OSLog(subsystem: "com.sanevideo.app", category: "Filter")

    /// Timeline operations signpost logger
    static let timelineLog = OSLog(subsystem: "com.sanevideo.app", category: "Timeline")

    // MARK: - Signpost IDs

    /// Create a unique signpost ID
    static func makeSignpostID(log: OSLog) -> OSSignpostID {
        OSSignpostID(log: log)
    }

    // MARK: - Convenience Methods

    /// Begin an export operation interval
    static func beginExport(name: String) -> OSSignpostID {
        let id = makeSignpostID(log: exportLog)
        os_signpost(.begin, log: exportLog, name: "Export", signpostID: id, "%{public}s", name)
        return id
    }

    /// End an export operation interval
    static func endExport(id: OSSignpostID, status: String = "Complete") {
        os_signpost(.end, log: exportLog, name: "Export", signpostID: id, "%{public}s", status)
    }

    /// Begin a capture operation interval
    static func beginCapture(source: String) -> OSSignpostID {
        let id = makeSignpostID(log: captureLog)
        os_signpost(.begin, log: captureLog, name: "Capture", signpostID: id, "%{public}s", source)
        return id
    }

    /// End a capture operation interval
    static func endCapture(id: OSSignpostID) {
        os_signpost(.end, log: captureLog, name: "Capture", signpostID: id)
    }

    /// Mark a filter application event
    static func markFilterApplication(filter: String, duration: TimeInterval) {
        os_signpost(.event, log: filterLog, name: "ApplyFilter",
                    "Filter: %{public}s Duration: %.3fms", filter, duration * 1000)
    }

    /// Mark a timeline scrub event
    static func markTimelineScrub(frame: Int) {
        os_signpost(.event, log: timelineLog, name: "Scrub", "Frame: %d", frame)
    }

    /// Begin a playback interval
    static func beginPlayback() -> OSSignpostID {
        let id = makeSignpostID(log: playbackLog)
        os_signpost(.begin, log: playbackLog, name: "Playback", signpostID: id)
        return id
    }

    /// End a playback interval
    static func endPlayback(id: OSSignpostID) {
        os_signpost(.end, log: playbackLog, name: "Playback", signpostID: id)
    }
}

/// Extension for timing code blocks
extension PerformanceMonitor {
    /// Measure execution time of a closure
    @discardableResult
    static func measure<T>(
        _ name: String,
        log: OSLog,
        operation: () throws -> T
    ) rethrows -> T {
        let id = makeSignpostID(log: log)
        os_signpost(.begin, log: log, name: "Measure", signpostID: id, "%{public}s", name)

        defer {
            os_signpost(.end, log: log, name: "Measure", signpostID: id)
        }

        return try operation()
    }

    /// Measure execution time of an async closure
    @discardableResult
    static func measureAsync<T>(
        _ name: String,
        log: OSLog,
        operation: () async throws -> T
    ) async rethrows -> T {
        let id = makeSignpostID(log: log)
        os_signpost(.begin, log: log, name: "MeasureAsync", signpostID: id, "%{public}s", name)

        defer {
            os_signpost(.end, log: log, name: "MeasureAsync", signpostID: id)
        }

        return try await operation()
    }
}

// MARK: - Usage Examples

/*

 // Export Performance Tracking:
 let exportID = PerformanceMonitor.beginExport(name: "4K HEVC")
 try await performExport()
 PerformanceMonitor.endExport(id: exportID, status: "Success")

 // Capture Performance Tracking:
 let captureID = PerformanceMonitor.beginCapture(source: "Screen")
 try await startCapture()
 PerformanceMonitor.endCapture(id: captureID)

 // Filter Application Tracking:
 let start = Date()
 applyFilter()
 let duration = Date().timeIntervalSince(start)
 PerformanceMonitor.markFilterApplication(filter: "Cinematic", duration: duration)

 // Timeline Scrub Tracking:
 PerformanceMonitor.markTimelineScrub(frame: currentFrame)

 // Measure a specific operation:
 let result = PerformanceMonitor.measure("Load Asset", log: .exportLog) {
     try AVURLAsset(url: videoURL).load(.duration)
 }

 // View in Instruments:
 // 1. Product → Profile (⌘I)
 // 2. Select "Points of Interest" template
 // 3. Record while using the app
 // 4. See all signpost intervals and events

 */
