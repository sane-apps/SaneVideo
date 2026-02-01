//
//  RecordingBenchmarkTests.swift
//  SaneVideoTests
//
//  Tests for recording quality benchmark metrics and grading
//

import CoreMedia
import Testing

@testable import SaneVideo

struct RecordingBenchmarkTests {

    // MARK: - Helpers

    private func makePTS(_ seconds: Double) -> CMTime {
        CMTime(seconds: seconds, preferredTimescale: 600)
    }

    // MARK: - FPS Tracking

    @Test("FPS within tolerance passes")
    @MainActor
    func fpsWithinTolerancePasses() {
        let benchmark = RecordingBenchmark()
        benchmark.recordingDidStart()

        // Simulate 30fps for 2 seconds (60 frames)
        for i in 0 ..< 60 {
            benchmark.frameWritten(
                presentationTime: makePTS(Double(i) / 30.0),
                targetFPS: 30.0
            )
        }

        let result = benchmark.finalize()
        // FPS should be close to 30
        let fpsFailure = result.failures.first { $0.hasPrefix("FPS:") }
        #expect(fpsFailure == nil)
    }

    @Test("FPS outside tolerance fails")
    @MainActor
    func fpsOutsideToleranceFails() {
        let targets = RecordingBenchmark.Targets(
            fpsTolerance: 1.0,
            maxJitterMs: 15.0,
            maxDroppedPercent: 2.0,
            maxAVSyncMs: 50.0,
            maxStartupLatencyMs: 500.0
        )
        let benchmark = RecordingBenchmark(targets: targets)
        benchmark.recordingDidStart()

        // Simulate 20fps (well below 30fps target with ±1 tolerance)
        for i in 0 ..< 40 {
            benchmark.frameWritten(
                presentationTime: makePTS(Double(i) / 20.0),
                targetFPS: 30.0
            )
        }

        let result = benchmark.finalize()
        #expect(!result.passed)
        #expect(result.failures.contains { $0.hasPrefix("FPS:") })
    }

    // MARK: - Jitter

    @Test("Low jitter passes")
    @MainActor
    func lowJitterPasses() {
        let benchmark = RecordingBenchmark()
        benchmark.recordingDidStart()

        // Perfect 30fps timing
        for i in 0 ..< 60 {
            benchmark.frameWritten(
                presentationTime: makePTS(Double(i) / 30.0),
                targetFPS: 30.0
            )
        }

        let result = benchmark.finalize()
        let jitterFailure = result.failures.first { $0.hasPrefix("Jitter:") }
        #expect(jitterFailure == nil)
    }

    // MARK: - Dropped Frames

    @Test("Low drop rate passes")
    @MainActor
    func lowDropRatePasses() {
        let benchmark = RecordingBenchmark()
        benchmark.recordingDidStart()

        // 100 frames, 1 dropped = 1% (below 2% threshold)
        for i in 0 ..< 100 {
            benchmark.frameWritten(
                presentationTime: makePTS(Double(i) / 30.0),
                targetFPS: 30.0
            )
        }
        benchmark.frameDropped()

        let result = benchmark.finalize()
        let dropFailure = result.failures.first { $0.hasPrefix("Drops:") }
        #expect(dropFailure == nil)
    }

    @Test("High drop rate fails")
    @MainActor
    func highDropRateFails() {
        let benchmark = RecordingBenchmark()
        benchmark.recordingDidStart()

        // 10 frames written, 5 dropped = 33% (way above 2% threshold)
        for i in 0 ..< 10 {
            benchmark.frameWritten(
                presentationTime: makePTS(Double(i) / 30.0),
                targetFPS: 30.0
            )
        }
        for _ in 0 ..< 5 {
            benchmark.frameDropped()
        }

        let result = benchmark.finalize()
        #expect(!result.passed)
        #expect(result.failures.contains { $0.hasPrefix("Drops:") })
    }

    // MARK: - A/V Sync

    @Test("Good A/V sync passes")
    @MainActor
    func goodAVSyncPasses() {
        let benchmark = RecordingBenchmark()
        benchmark.recordingDidStart()
        benchmark.updateAVDrift(0.020)  // 20ms — well below 50ms threshold

        for i in 0 ..< 30 {
            benchmark.frameWritten(
                presentationTime: makePTS(Double(i) / 30.0),
                targetFPS: 30.0
            )
        }

        let result = benchmark.finalize()
        let syncFailure = result.failures.first { $0.hasPrefix("A/V sync:") }
        #expect(syncFailure == nil)
    }

    @Test("Bad A/V sync fails")
    @MainActor
    func badAVSyncFails() {
        let benchmark = RecordingBenchmark()
        benchmark.recordingDidStart()
        benchmark.updateAVDrift(0.100)  // 100ms — above 50ms threshold

        for i in 0 ..< 30 {
            benchmark.frameWritten(
                presentationTime: makePTS(Double(i) / 30.0),
                targetFPS: 30.0
            )
        }

        let result = benchmark.finalize()
        #expect(!result.passed)
        #expect(result.failures.contains { $0.hasPrefix("A/V sync:") })
    }

    // MARK: - Perfect Recording

    @Test("Perfect recording passes all checks")
    @MainActor
    func perfectRecordingPasses() {
        let benchmark = RecordingBenchmark()
        benchmark.recordingDidStart()
        benchmark.updateAVDrift(0.010)

        // Simulate ideal 30fps for 3 seconds
        for i in 0 ..< 90 {
            benchmark.frameWritten(
                presentationTime: makePTS(Double(i) / 30.0),
                targetFPS: 30.0
            )
        }

        let result = benchmark.finalize()
        #expect(result.passed)
        #expect(result.failures.isEmpty)
    }
}
