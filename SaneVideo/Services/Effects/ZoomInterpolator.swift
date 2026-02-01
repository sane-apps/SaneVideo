//
//  ZoomInterpolator.swift
//  SaneVideo
//
//  Spring-physics zoom transitions with cursor-following viewport.
//  Replaces linear easing with natural spring motion inspired by Cap's PR #1504.
//
//  Flow:
//  1. Click → spring zoom from 1.0 to zoomScale
//  2. During hold → viewport spring-follows cursor within safe zone
//  3. Zoom out → spring back to 1.0, viewport returns to center
//  4. All keyframes pre-baked at clip frame rate
//

import CoreMedia
import Foundation

/// Generates spring-physics zoom animations from click and cursor data
struct ZoomInterpolator: Sendable {

    // MARK: - Configuration

    struct Config: Sendable {
        /// How much to zoom in (1.5 = 50% zoom)
        var zoomScale: Double = 1.5

        /// Minimum time between zoom triggers (seconds)
        var minTimeBetweenZooms: TimeInterval = 0.3

        /// How long to hold zoom after click (seconds)
        var holdDuration: TimeInterval = 1.0

        /// Safe zone margin — cursor stays within this % of viewport before panning
        var safeZoneMargin: Double = 0.15

        /// Whether to snap viewport to edges instead of showing outside content
        var edgeSnap: Bool = true

        /// Frame rate for pre-baked keyframes
        var keyframeRate: Double = 30.0

        /// Anticipation time before click (seconds)
        var anticipation: TimeInterval = 0.1

        static let `default` = Config()
    }

    let config: Config

    init(config: Config = .default) {
        self.config = config
    }

    // MARK: - Animation Generation

    /// Generate a spring-physics zoom animation from click and cursor data.
    ///
    /// - Parameters:
    ///   - clicks: Click events that trigger zoom
    ///   - cursorPath: Continuous cursor samples for viewport following
    ///   - clipDuration: Total clip duration
    /// - Returns: KeyframeAnimation with pre-baked spring-physics keyframes
    func generateZoomAnimation(
        clicks: [ClickSample],
        cursorPath: [CursorSample],
        clipDuration: CMTime
    ) -> KeyframeAnimation {
        var animation = KeyframeAnimation()
        guard !clicks.isEmpty else { return animation }

        let sortedClicks = clicks.sorted { $0.timestamp < $1.timestamp }
        let duration = clipDuration.seconds
        let frameDt = 1.0 / config.keyframeRate
        let timescale: CMTimeScale = 600

        // Build zoom regions (when we're zoomed in)
        let zoomRegions = buildZoomRegions(from: sortedClicks, clipDuration: duration)

        // Spring simulations for scale and viewport position
        var scaleSim = SpringMassDamperSimulation(value: 1.0, target: 1.0, profile: .zoom)
        var posXSim = SpringMassDamperSimulation(value: 0.0, target: 0.0, profile: .zoom)
        var posYSim = SpringMassDamperSimulation(value: 0.0, target: 0.0, profile: .zoom)

        var time: Double = 0

        while time <= duration {
            let cmTime = CMTime(seconds: time, preferredTimescale: timescale)

            // Determine current zoom state
            let zoomState = currentZoomState(at: time, regions: zoomRegions)

            // Set scale target
            let targetScale: Double
            switch zoomState {
            case .idle:
                targetScale = 1.0
            case .zoomingIn(let region), .holding(let region), .zoomingOut(let region):
                targetScale = zoomState == .zoomingOut(region) ? 1.0 : config.zoomScale
            }

            scaleSim.step(toward: targetScale, dt: frameDt)

            // Set position target based on zoom state
            let targetPosX: Double
            let targetPosY: Double

            switch zoomState {
            case .idle:
                targetPosX = 0
                targetPosY = 0
            case .zoomingIn(let region):
                targetPosX = offsetForClick(region.click.x, scale: scaleSim.value)
                targetPosY = offsetForClick(region.click.y, scale: scaleSim.value)
            case .holding(let region):
                // Follow cursor within safe zone during hold
                let cursorPos = cursorPosition(at: time, path: cursorPath)
                let followPos = viewportFollowPosition(
                    cursor: cursorPos,
                    clickCenter: (region.click.x, region.click.y),
                    currentScale: scaleSim.value
                )
                targetPosX = followPos.x
                targetPosY = followPos.y
            case .zoomingOut:
                targetPosX = 0
                targetPosY = 0
            }

            posXSim.step(toward: targetPosX, dt: frameDt)
            posYSim.step(toward: targetPosY, dt: frameDt)

            // Clamp viewport to content bounds
            let clampedX = clampToContentBounds(posXSim.value, scale: scaleSim.value)
            let clampedY = clampToContentBounds(posYSim.value, scale: scaleSim.value)

            // Write keyframes
            animation.setKeyframe(
                property: .scale, at: cmTime,
                value: scaleSim.value, easing: .springPhysics
            )
            animation.setKeyframe(
                property: .positionX, at: cmTime,
                value: clampedX, easing: .springPhysics
            )
            animation.setKeyframe(
                property: .positionY, at: cmTime,
                value: clampedY, easing: .springPhysics
            )

            time += frameDt
        }

        return animation
    }

    // MARK: - Zoom Regions

    /// A time region where the camera is zoomed in
    private struct ZoomRegion {
        let click: ClickSample
        let zoomInStart: Double
        let zoomInEnd: Double
        let holdEnd: Double
        let zoomOutEnd: Double
    }

    private enum ZoomState: Equatable {
        case idle
        case zoomingIn(ZoomRegion)
        case holding(ZoomRegion)
        case zoomingOut(ZoomRegion)

        static func == (lhs: ZoomState, rhs: ZoomState) -> Bool {
            switch (lhs, rhs) {
            case (.idle, .idle): return true
            case (.zoomingIn(let a), .zoomingIn(let b)): return a.zoomInStart == b.zoomInStart
            case (.holding(let a), .holding(let b)): return a.zoomInStart == b.zoomInStart
            case (.zoomingOut(let a), .zoomingOut(let b)): return a.zoomInStart == b.zoomInStart
            default: return false
            }
        }
    }

    private func buildZoomRegions(from clicks: [ClickSample], clipDuration: Double) -> [ZoomRegion] {
        var regions: [ZoomRegion] = []
        var lastZoomEnd: Double = 0

        for click in clicks {
            guard click.timestamp < clipDuration else { continue }
            guard click.timestamp >= lastZoomEnd + config.minTimeBetweenZooms else { continue }

            let zoomInStart = max(0, click.timestamp - config.anticipation)
            // Zoom-in takes ~0.5s with spring physics (settled time depends on profile)
            let zoomInEnd = click.timestamp + 0.3
            let holdEnd = zoomInEnd + config.holdDuration
            let zoomOutEnd = holdEnd + 0.5

            guard zoomOutEnd <= clipDuration else { continue }

            let region = ZoomRegion(
                click: click,
                zoomInStart: zoomInStart,
                zoomInEnd: zoomInEnd,
                holdEnd: holdEnd,
                zoomOutEnd: zoomOutEnd
            )
            regions.append(region)
            lastZoomEnd = zoomOutEnd
        }

        return regions
    }

    private func currentZoomState(at time: Double, regions: [ZoomRegion]) -> ZoomState {
        for region in regions {
            if time >= region.zoomInStart && time < region.zoomInEnd {
                return .zoomingIn(region)
            }
            if time >= region.zoomInEnd && time < region.holdEnd {
                return .holding(region)
            }
            if time >= region.holdEnd && time < region.zoomOutEnd {
                return .zoomingOut(region)
            }
        }
        return .idle
    }

    // MARK: - Position Calculation

    /// Calculate position offset to center a click location at a given zoom scale.
    ///
    /// Click coords are normalized 0-1, center is 0.5.
    /// Offset = (click - center) * scale
    private func offsetForClick(_ coord: Double, scale: Double) -> Double {
        return (coord - 0.5) * scale
    }

    /// Cursor-following viewport: pans to keep cursor within safe zone.
    private func viewportFollowPosition(
        cursor: (x: Double, y: Double),
        clickCenter: (x: Double, y: Double),
        currentScale: Double
    ) -> (x: Double, y: Double) {
        // Base position centered on click
        let baseX = offsetForClick(clickCenter.x, scale: currentScale)
        let baseY = offsetForClick(clickCenter.y, scale: currentScale)

        // Cursor position relative to viewport center (in normalized coords)
        let cursorRelX = cursor.x - clickCenter.x
        let cursorRelY = cursor.y - clickCenter.y

        // Viewport visible size at current zoom (fraction of full frame)
        let viewportSize = 1.0 / currentScale

        // Safe zone bounds (cursor can move this far from center before viewport pans)
        let safeHalf = viewportSize * (0.5 - config.safeZoneMargin)

        // If cursor is outside safe zone, offset viewport to bring cursor back in
        var adjustX = 0.0
        var adjustY = 0.0

        if cursorRelX > safeHalf {
            adjustX = (cursorRelX - safeHalf) * currentScale
        } else if cursorRelX < -safeHalf {
            adjustX = (cursorRelX + safeHalf) * currentScale
        }

        if cursorRelY > safeHalf {
            adjustY = (cursorRelY - safeHalf) * currentScale
        } else if cursorRelY < -safeHalf {
            adjustY = (cursorRelY + safeHalf) * currentScale
        }

        return (baseX + adjustX, baseY + adjustY)
    }

    /// Interpolate cursor position at a given time from the cursor path
    private func cursorPosition(at time: Double, path: [CursorSample]) -> (x: Double, y: Double) {
        guard !path.isEmpty else { return (0.5, 0.5) }

        // Find surrounding samples
        if let last = path.last, time >= last.timestamp {
            return (last.x, last.y)
        }
        if let first = path.first, time <= first.timestamp {
            return (first.x, first.y)
        }

        // Binary search for bracketing samples
        var lo = 0, hi = path.count - 1
        while lo < hi - 1 {
            let mid = (lo + hi) / 2
            if path[mid].timestamp <= time {
                lo = mid
            } else {
                hi = mid
            }
        }

        let a = path[lo]
        let b = path[hi]
        let dt = b.timestamp - a.timestamp
        guard dt > 0 else { return (a.x, a.y) }

        let t = (time - a.timestamp) / dt
        return (a.x + (b.x - a.x) * t, a.y + (b.y - a.y) * t)
    }

    /// Prevent viewport from showing outside content bounds
    private func clampToContentBounds(_ offset: Double, scale: Double) -> Double {
        guard config.edgeSnap && scale > 1.0 else { return offset }

        // At zoom scale S, the visible portion is 1/S of the frame.
        // The maximum offset before edge is visible: (1 - 1/S) * S / 2
        let maxOffset = (scale - 1.0) / 2.0
        return min(max(offset, -maxOffset), maxOffset)
    }
}
