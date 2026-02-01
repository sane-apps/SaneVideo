//
//  ZoomInterpolatorTests.swift
//  SaneVideoTests
//
//  Tests for spring-physics zoom with cursor-following viewport
//

import CoreMedia
import Testing

@testable import SaneVideo

struct ZoomInterpolatorTests {

    // MARK: - Helpers

    private let timescale: CMTimeScale = 600

    private func makeClick(t: TimeInterval, x: Double, y: Double) -> ClickSample {
        ClickSample(timestamp: t, x: x, y: y, button: 0)
    }

    private func makeCursorPath(duration: Double, rate: Double = 60) -> [CursorSample] {
        let count = Int(duration * rate)
        return (0 ..< count).map { i in
            let t = Double(i) / rate
            return CursorSample(timestamp: t, x: 0.5, y: 0.5, isDown: false, button: 0)
        }
    }

    // MARK: - Basic Generation

    @Test("Empty clicks produce empty animation")
    func emptyClicksEmptyAnimation() {
        let interpolator = ZoomInterpolator()
        let result = interpolator.generateZoomAnimation(
            clicks: [],
            cursorPath: makeCursorPath(duration: 5),
            clipDuration: CMTime(seconds: 5, preferredTimescale: timescale)
        )
        #expect(result.isEmpty)
    }

    @Test("Single click produces zoom animation with keyframes")
    func singleClickProducesKeyframes() {
        let interpolator = ZoomInterpolator()
        let click = makeClick(t: 2.0, x: 0.5, y: 0.5)

        let result = interpolator.generateZoomAnimation(
            clicks: [click],
            cursorPath: makeCursorPath(duration: 10),
            clipDuration: CMTime(seconds: 10, preferredTimescale: timescale)
        )

        #expect(!result.isEmpty)
        // Should have scale, positionX, positionY tracks
        #expect(result[.scale] != nil)
        #expect(result[.positionX] != nil)
        #expect(result[.positionY] != nil)
    }

    // MARK: - Spring Physics

    @Test("Scale transitions use spring physics easing")
    func scaleUsesSpringPhysics() {
        let interpolator = ZoomInterpolator()
        let click = makeClick(t: 1.0, x: 0.5, y: 0.5)

        let result = interpolator.generateZoomAnimation(
            clicks: [click],
            cursorPath: makeCursorPath(duration: 5),
            clipDuration: CMTime(seconds: 5, preferredTimescale: timescale)
        )

        guard let scaleTrack = result[.scale] else {
            Issue.record("Missing scale track")
            return
        }

        // All keyframes should use springPhysics easing
        for kf in scaleTrack.keyframes {
            #expect(kf.easing == .springPhysics)
        }
    }

    @Test("Scale reaches zoom level during hold period")
    func scaleReachesZoomDuringHold() {
        let config = ZoomInterpolator.Config(zoomScale: 1.5, holdDuration: 1.0)
        let interpolator = ZoomInterpolator(config: config)
        let click = makeClick(t: 1.0, x: 0.5, y: 0.5)

        let result = interpolator.generateZoomAnimation(
            clicks: [click],
            cursorPath: makeCursorPath(duration: 5),
            clipDuration: CMTime(seconds: 5, preferredTimescale: timescale)
        )

        // During hold (roughly t=1.3 to t=2.3), scale should be near 1.5
        let holdTime = CMTime(seconds: 1.8, preferredTimescale: timescale)
        let scaleAtHold = result.value(for: .scale, at: holdTime)
        #expect(scaleAtHold > 1.3)  // Should be close to 1.5
    }

    @Test("Scale returns to 1.0 after zoom out")
    func scaleReturnsToOne() {
        let interpolator = ZoomInterpolator()
        let click = makeClick(t: 1.0, x: 0.5, y: 0.5)

        let result = interpolator.generateZoomAnimation(
            clicks: [click],
            cursorPath: makeCursorPath(duration: 10),
            clipDuration: CMTime(seconds: 10, preferredTimescale: timescale)
        )

        // Well after zoom out (t=4.0), scale should be back to 1.0
        let lateTime = CMTime(seconds: 5.0, preferredTimescale: timescale)
        let scaleAtLate = result.value(for: .scale, at: lateTime)
        #expect(abs(scaleAtLate - 1.0) < 0.05)
    }

    // MARK: - Viewport Following

    @Test("Position offsets center on click location")
    func positionCentersOnClick() {
        let config = ZoomInterpolator.Config(zoomScale: 2.0)
        let interpolator = ZoomInterpolator(config: config)

        // Click at top-right quadrant
        let click = makeClick(t: 1.0, x: 0.75, y: 0.25)

        let result = interpolator.generateZoomAnimation(
            clicks: [click],
            cursorPath: makeCursorPath(duration: 5),
            clipDuration: CMTime(seconds: 5, preferredTimescale: timescale)
        )

        // During hold, positionX should be positive (right of center)
        let holdTime = CMTime(seconds: 1.8, preferredTimescale: timescale)
        let posX = result.value(for: .positionX, at: holdTime)
        #expect(posX > 0)  // Offset toward click (right of center)
    }

    // MARK: - Edge Clamping

    @Test("Viewport is clamped to prevent showing outside content")
    func viewportClamped() {
        let config = ZoomInterpolator.Config(zoomScale: 2.0, edgeSnap: true)
        let interpolator = ZoomInterpolator(config: config)

        // Click at extreme edge
        let click = makeClick(t: 1.0, x: 0.99, y: 0.01)

        let result = interpolator.generateZoomAnimation(
            clicks: [click],
            cursorPath: makeCursorPath(duration: 5),
            clipDuration: CMTime(seconds: 5, preferredTimescale: timescale)
        )

        // At 2.0x zoom, max offset = (2.0 - 1.0) / 2.0 = 0.5
        let holdTime = CMTime(seconds: 1.8, preferredTimescale: timescale)
        let posX = result.value(for: .positionX, at: holdTime)
        let posY = result.value(for: .positionY, at: holdTime)
        #expect(abs(posX) <= 0.55)  // Allow small spring overshoot
        #expect(abs(posY) <= 0.55)
    }

    // MARK: - Rapid-Fire Prevention

    @Test("Rapid clicks are filtered by minTimeBetweenZooms")
    func rapidClicksFiltered() {
        let config = ZoomInterpolator.Config(minTimeBetweenZooms: 3.0)
        let interpolator = ZoomInterpolator(config: config)

        let clicks = [
            makeClick(t: 1.0, x: 0.5, y: 0.5),
            makeClick(t: 1.5, x: 0.7, y: 0.3),  // Should be filtered (too close)
            makeClick(t: 2.0, x: 0.3, y: 0.7),   // Should be filtered (too close)
        ]

        let result = interpolator.generateZoomAnimation(
            clicks: clicks,
            cursorPath: makeCursorPath(duration: 15),
            clipDuration: CMTime(seconds: 15, preferredTimescale: timescale)
        )

        // Only one zoom should occur — check that scale is ~1.0 at t=8
        // (well after the first zoom completes and before any second could start)
        let lateTime = CMTime(seconds: 8.0, preferredTimescale: timescale)
        let scaleAtLate = result.value(for: .scale, at: lateTime)
        #expect(abs(scaleAtLate - 1.0) < 0.05)
    }

    // MARK: - Clip Duration Safety

    @Test("Clicks near end of clip that would overflow are skipped")
    func clicksNearEndSkipped() {
        let interpolator = ZoomInterpolator()

        // Click at 4.5s in a 5s clip — zoom-out would exceed duration
        let click = makeClick(t: 4.5, x: 0.5, y: 0.5)

        let result = interpolator.generateZoomAnimation(
            clicks: [click],
            cursorPath: makeCursorPath(duration: 5),
            clipDuration: CMTime(seconds: 5, preferredTimescale: timescale)
        )

        // The click should be skipped since the full zoom cycle can't fit.
        // The animation may still have keyframes (idle state at scale=1.0),
        // but scale should never exceed 1.0 — no zoom should occur.
        if let scaleTrack = result[.scale] {
            for kf in scaleTrack.keyframes {
                #expect(abs(kf.value - 1.0) < 0.01)
            }
        }
    }
}
