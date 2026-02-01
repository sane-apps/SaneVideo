//
//  RecordingBenchmark.swift
//  SaneVideo
//
//  Recording quality benchmark with Cap-inspired targets.
//  Tracks live metrics during recording and grades pass/fail on finalize.
//
//  Targets:
//  - FPS: ±2 of target (e.g., 28-32 for 30fps)
//  - Jitter: <15ms average inter-frame deviation
//  - Dropped frames: <2% of total
//  - A/V sync: <50ms drift
//  - Startup latency: <500ms to first frame
//

import CoreMedia
import Foundation
import QuartzCore

/// Recording quality benchmark with live metrics and pass/fail grading
@Observable
@MainActor
final class RecordingBenchmark {

    // MARK: - Targets

    struct Targets: Sendable {
        let fpsTolerance: Double          // ±fps from target
        let maxJitterMs: Double           // Max average jitter in ms
        let maxDroppedPercent: Double     // Max % dropped frames
        let maxAVSyncMs: Double           // Max A/V drift in ms
        let maxStartupLatencyMs: Double   // Max time to first frame in ms

        static let `default` = Targets(
            fpsTolerance: 2.0,
            maxJitterMs: 15.0,
            maxDroppedPercent: 2.0,
            maxAVSyncMs: 50.0,
            maxStartupLatencyMs: 500.0
        )
    }

    // MARK: - Live Metrics

    struct LiveMetrics: Sendable {
        var targetFPS: Double = 30.0
        var actualFPS: Double = 0
        var averageJitterMs: Double = 0
        var totalFrames: Int = 0
        var droppedFrames: Int = 0
        var droppedPercent: Double = 0
        var avDriftMs: Double = 0
        var startupLatencyMs: Double = 0
    }

    // MARK: - Result

    struct BenchmarkResult: Sendable {
        let metrics: LiveMetrics
        let passed: Bool
        let failures: [String]
    }

    // MARK: - State

    private(set) var liveMetrics = LiveMetrics()
    let targets: Targets

    // Internal tracking (nonisolated access via sendable wrapper)
    private var frameTimestamps: [Double] = []
    private var startWallTime: Double?
    private var firstFrameWallTime: Double?

    init(targets: Targets = .default) {
        self.targets = targets
    }

    // MARK: - Recording Events

    /// Call when recording starts
    func recordingDidStart() {
        startWallTime = CACurrentMediaTime()
        frameTimestamps = []
        firstFrameWallTime = nil
        liveMetrics = LiveMetrics()
    }

    /// Call for each video frame written
    func frameWritten(presentationTime: CMTime, targetFPS: Double) {
        let now = CACurrentMediaTime()

        if firstFrameWallTime == nil {
            firstFrameWallTime = now
            if let start = startWallTime {
                liveMetrics.startupLatencyMs = (now - start) * 1000.0
            }
        }

        let pts = presentationTime.seconds
        frameTimestamps.append(pts)

        // Keep a sliding window of 120 frames for FPS/jitter calculation
        if frameTimestamps.count > 120 {
            frameTimestamps.removeFirst()
        }

        liveMetrics.targetFPS = targetFPS
        liveMetrics.totalFrames += 1

        // Calculate current FPS from window
        if frameTimestamps.count >= 2 {
            let first = frameTimestamps.first!
            let last = frameTimestamps.last!
            let duration = last - first
            if duration > 0 {
                liveMetrics.actualFPS = Double(frameTimestamps.count - 1) / duration
            }
        }

        // Calculate jitter (average deviation from expected frame interval)
        if frameTimestamps.count >= 3 {
            let expectedInterval = 1.0 / targetFPS
            var totalJitter = 0.0
            for i in 1 ..< frameTimestamps.count {
                let actualInterval = frameTimestamps[i] - frameTimestamps[i - 1]
                totalJitter += abs(actualInterval - expectedInterval)
            }
            liveMetrics.averageJitterMs = (totalJitter / Double(frameTimestamps.count - 1)) * 1000.0
        }
    }

    /// Call when a frame is dropped
    func frameDropped() {
        liveMetrics.droppedFrames += 1
        if liveMetrics.totalFrames > 0 {
            liveMetrics.droppedPercent = Double(liveMetrics.droppedFrames) / Double(liveMetrics.totalFrames + liveMetrics.droppedFrames) * 100.0
        }
    }

    /// Update A/V drift measurement
    func updateAVDrift(_ driftSeconds: TimeInterval) {
        liveMetrics.avDriftMs = abs(driftSeconds) * 1000.0
    }

    // MARK: - Finalization

    /// Finalize benchmark and produce pass/fail result
    func finalize() -> BenchmarkResult {
        var failures: [String] = []

        // Check FPS
        let fpsOff = abs(liveMetrics.actualFPS - liveMetrics.targetFPS)
        if fpsOff > targets.fpsTolerance {
            failures.append("FPS: \(String(format: "%.1f", liveMetrics.actualFPS)) (target \(String(format: "%.0f", liveMetrics.targetFPS))±\(String(format: "%.0f", targets.fpsTolerance)))")
        }

        // Check jitter
        if liveMetrics.averageJitterMs > targets.maxJitterMs {
            failures.append("Jitter: \(String(format: "%.1f", liveMetrics.averageJitterMs))ms (max \(String(format: "%.0f", targets.maxJitterMs))ms)")
        }

        // Check dropped frames
        if liveMetrics.droppedPercent > targets.maxDroppedPercent {
            failures.append("Drops: \(String(format: "%.1f", liveMetrics.droppedPercent))% (max \(String(format: "%.1f", targets.maxDroppedPercent))%)")
        }

        // Check A/V sync
        if liveMetrics.avDriftMs > targets.maxAVSyncMs {
            failures.append("A/V sync: \(String(format: "%.1f", liveMetrics.avDriftMs))ms (max \(String(format: "%.0f", targets.maxAVSyncMs))ms)")
        }

        // Check startup latency
        if liveMetrics.startupLatencyMs > targets.maxStartupLatencyMs {
            failures.append("Startup: \(String(format: "%.0f", liveMetrics.startupLatencyMs))ms (max \(String(format: "%.0f", targets.maxStartupLatencyMs))ms)")
        }

        return BenchmarkResult(
            metrics: liveMetrics,
            passed: failures.isEmpty,
            failures: failures
        )
    }
}
