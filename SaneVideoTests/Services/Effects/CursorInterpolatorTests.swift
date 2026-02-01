//
//  CursorInterpolatorTests.swift
//  SaneVideoTests
//
//  Tests for the cursor interpolation pipeline:
//  shake filtering, gap densification, spring smoothing
//

import Foundation
import Testing

@testable import SaneVideo

struct CursorInterpolatorTests {

    // MARK: - Helpers

    private func makeSample(
        t: TimeInterval, x: Double, y: Double,
        isDown: Bool = false, button: Int = 0
    ) -> CursorSample {
        CursorSample(timestamp: t, x: x, y: y, isDown: isDown, button: button)
    }

    private func makeClick(t: TimeInterval, x: Double, y: Double) -> ClickSample {
        ClickSample(timestamp: t, x: x, y: y, button: 0)
    }

    // MARK: - Shake Filter

    @Test("Shake filter removes jittery micro-movements")
    func shakeFilterRemovesJitter() {
        let interpolator = CursorInterpolator()

        // Cursor goes right, reverses left (tiny movement), then continues right
        let samples = [
            makeSample(t: 0.00, x: 0.5, y: 0.5),
            makeSample(t: 0.02, x: 0.505, y: 0.5),  // Tiny right
            makeSample(t: 0.04, x: 0.502, y: 0.5),   // Reversal (shake)
            makeSample(t: 0.06, x: 0.510, y: 0.5),    // Continues right
            makeSample(t: 0.08, x: 0.520, y: 0.5),
        ]

        let result = interpolator.filterShake(samples)

        // The reversal sample at 0.04 should be removed
        #expect(result.count < samples.count)
        // First and last always kept
        #expect(result.first?.timestamp == 0.0)
        #expect(result.last?.timestamp == 0.08)
    }

    @Test("Shake filter preserves legitimate large movements")
    func shakeFilterPreservesLargeMovements() {
        let interpolator = CursorInterpolator()

        // Large deliberate direction change (not shake)
        let samples = [
            makeSample(t: 0.00, x: 0.1, y: 0.5),
            makeSample(t: 0.03, x: 0.5, y: 0.5),   // Large right move
            makeSample(t: 0.06, x: 0.3, y: 0.5),    // Large left move (deliberate)
            makeSample(t: 0.09, x: 0.7, y: 0.5),
        ]

        let result = interpolator.filterShake(samples)

        // All samples should be kept — movements are well above threshold
        #expect(result.count == samples.count)
    }

    @Test("Shake filter handles fewer than 3 samples")
    func shakeFilterHandlesMinimalInput() {
        let interpolator = CursorInterpolator()

        let two = [makeSample(t: 0, x: 0.5, y: 0.5), makeSample(t: 0.1, x: 0.6, y: 0.5)]
        #expect(interpolator.filterShake(two).count == 2)

        let one = [makeSample(t: 0, x: 0.5, y: 0.5)]
        #expect(interpolator.filterShake(one).count == 1)

        #expect(interpolator.filterShake([]).isEmpty)
    }

    // MARK: - Gap Densification

    @Test("Gap densification fills large temporal gaps")
    func gapDensificationFillsGaps() {
        let interpolator = CursorInterpolator()

        // 500ms gap — well above 67ms threshold
        let samples = [
            makeSample(t: 0.0, x: 0.1, y: 0.1),
            makeSample(t: 0.5, x: 0.9, y: 0.9),
        ]

        let result = interpolator.densifyGaps(samples)

        // Should have many more samples between the two originals
        #expect(result.count > 2)
        // First and last originals should be present
        #expect(result.first?.x == 0.1)
        #expect(result.last?.x == 0.9)
        // Interpolated points should be between originals
        let midSample = result[result.count / 2]
        #expect(midSample.x > 0.1 && midSample.x < 0.9)
        #expect(midSample.y > 0.1 && midSample.y < 0.9)
    }

    @Test("Gap densification leaves small gaps untouched")
    func gapDensificationLeavesSmallGaps() {
        let interpolator = CursorInterpolator()

        // 10ms gaps — well below 67ms threshold
        let samples = [
            makeSample(t: 0.00, x: 0.5, y: 0.5),
            makeSample(t: 0.01, x: 0.51, y: 0.5),
            makeSample(t: 0.02, x: 0.52, y: 0.5),
        ]

        let result = interpolator.densifyGaps(samples)
        #expect(result.count == samples.count)
    }

    // MARK: - Spring Smoothing

    @Test("Spring smoothing produces output for all input samples")
    func springSmoothingPreservesCount() {
        let interpolator = CursorInterpolator()

        let samples = (0 ..< 30).map { i in
            makeSample(t: Double(i) * 0.016, x: Double(i) * 0.01, y: 0.5)
        }

        let result = interpolator.applySpringSmoothing(samples)
        #expect(result.count == samples.count)
    }

    @Test("Spring smoothing uses snappy profile near clicks")
    func springSmoothingSnappyNearClicks() {
        let interpolator = CursorInterpolator()

        // Gradual ramp: cursor moves steadily, with a click at t=0.5
        // Snappy profile has higher stiffness/lower mass = different smoothed path
        let sampleCount = 60
        let samples = (0 ..< sampleCount).map { i in
            let t = Double(i) * 0.016
            let x = 0.3 + Double(i) * 0.005  // Slow ramp from 0.3 to ~0.6
            return makeSample(t: t, x: x, y: 0.5)
        }

        let click = makeClick(t: 0.5, x: 0.5, y: 0.5)

        let withClick = interpolator.applySpringSmoothing(samples, clicks: [click])
        let withoutClick = interpolator.applySpringSmoothing(samples, clicks: [])

        // The profiles should produce different smoothed paths near the click
        // Check that the two paths diverge in the vicinity of the click (around sample 31)
        var anyDifference = false
        for i in 28 ..< min(40, sampleCount) {
            if abs(withClick[i].x - withoutClick[i].x) > 0.001 {
                anyDifference = true
                break
            }
        }
        #expect(anyDifference)
    }

    @Test("Spring smoothing uses drag profile when button is held")
    func springSmoothingDragWhenHeld() {
        let interpolator = CursorInterpolator()

        let dragSamples = (0 ..< 30).map { i in
            makeSample(t: Double(i) * 0.016, x: Double(i) * 0.02, y: 0.5, isDown: true)
        }
        let freeSamples = (0 ..< 30).map { i in
            makeSample(t: Double(i) * 0.016, x: Double(i) * 0.02, y: 0.5, isDown: false)
        }

        let dragResult = interpolator.applySpringSmoothing(dragSamples)
        let freeResult = interpolator.applySpringSmoothing(freeSamples)

        // Drag should be heavier/slower to follow — at the end, drag should be more behind
        let lastDrag = dragResult.last!.x
        let lastFree = freeResult.last!.x
        let target = freeSamples.last!.x
        #expect(abs(lastDrag - target) >= abs(lastFree - target))
    }

    // MARK: - Full Pipeline

    @Test("Full pipeline produces valid output")
    func fullPipelineWorks() {
        let interpolator = CursorInterpolator()

        let samples = (0 ..< 60).map { i in
            let t = Double(i) * 0.016
            let x = 0.5 + 0.3 * sin(t * 2.0)
            let y = 0.5 + 0.2 * cos(t * 2.0)
            return makeSample(t: t, x: x, y: y)
        }

        let result = interpolator.process(samples: samples)

        // Should have output
        #expect(!result.isEmpty)
        // All timestamps should be ordered
        for i in 1 ..< result.count {
            #expect(result[i].timestamp >= result[i - 1].timestamp)
        }
        // All positions should be in reasonable range
        for s in result {
            #expect(s.x >= -0.5 && s.x <= 1.5)
            #expect(s.y >= -0.5 && s.y <= 1.5)
        }
    }
}
