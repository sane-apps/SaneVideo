//
//  CursorInterpolator.swift
//  SaneVideo
//
//  Processes raw cursor samples through a 3-stage pipeline:
//  1. Shake filter — removes jittery micro-movements
//  2. Gap densify — fills temporal gaps with interpolated points
//  3. Spring smooth — applies physics-based smoothing with context-aware profiles
//
//  Inspired by Cap's cursor interpolation (PR #1504).
//

import Foundation

/// Processes raw cursor movement into smooth, camera-ready paths
struct CursorInterpolator: Sendable {

    // MARK: - Configuration

    struct Config: Sendable {
        /// Window size for shake detection (seconds)
        var shakeWindowDuration: TimeInterval = 0.1

        /// Minimum displacement (UV) to keep a sample — below this is "shake"
        var shakeDisplacementThreshold: Double = 0.015

        /// Maximum gap between samples before densification (seconds)
        var maxGapDuration: TimeInterval = 1.0 / 15.0  // 67ms ≈ 15fps minimum

        /// Target sample rate for densified output (Hz)
        var densifyTargetRate: Double = 60.0

        /// Maximum interpolated points to insert per gap
        var maxDensifyPoints: Int = 120

        /// Minimum interpolated points per gap
        var minDensifyPoints: Int = 2

        /// Spring simulation step for smoothing (seconds)
        var smoothingStepDt: Double = 1.0 / 60.0

        static let `default` = Config()
    }

    let config: Config

    init(config: Config = .default) {
        self.config = config
    }

    // MARK: - Full Pipeline

    /// Run the complete interpolation pipeline on raw cursor samples.
    ///
    /// - Parameters:
    ///   - samples: Raw cursor samples from recording
    ///   - clicks: Click events for context-aware profile switching
    /// - Returns: Smoothed cursor path ready for zoom interpolation
    func process(samples: [CursorSample], clicks: [ClickSample] = []) -> [CursorSample] {
        guard samples.count >= 2 else { return samples }

        let filtered = filterShake(samples)
        let densified = densifyGaps(filtered)
        let smoothed = applySpringSmoothing(densified, clicks: clicks)
        return smoothed
    }

    // MARK: - Stage 1: Shake Filter

    /// Remove jittery micro-movements that would cause distracting camera jitter.
    ///
    /// Within each time window, checks if cursor reversed direction (dot product < 0)
    /// with displacement below threshold. Such samples are shake and get removed.
    func filterShake(_ samples: [CursorSample]) -> [CursorSample] {
        guard samples.count >= 3 else { return samples }

        var result: [CursorSample] = [samples[0]]

        for i in 1 ..< samples.count - 1 {
            let prev = samples[i - 1]
            let curr = samples[i]
            let next = samples[i + 1]

            // Check if within shake window
            let windowDt = next.timestamp - prev.timestamp
            guard windowDt <= config.shakeWindowDuration else {
                result.append(curr)
                continue
            }

            // Vector from prev to curr
            let dx1 = curr.x - prev.x
            let dy1 = curr.y - prev.y

            // Vector from curr to next
            let dx2 = next.x - curr.x
            let dy2 = next.y - curr.y

            // Dot product — negative means direction reversal
            let dot = dx1 * dx2 + dy1 * dy2

            // Displacement magnitude
            let displacement = sqrt(dx1 * dx1 + dy1 * dy1)

            // If direction reversed AND displacement is tiny, it's shake
            if dot < 0 && displacement < config.shakeDisplacementThreshold {
                continue  // Drop this sample
            }

            result.append(curr)
        }

        // Always keep last sample
        result.append(samples[samples.count - 1])
        return result
    }

    // MARK: - Stage 2: Gap Densification

    /// Fill temporal gaps with linearly interpolated samples.
    ///
    /// When cursor stops moving (no events) or events are sparse, this ensures
    /// a consistent sample rate for smooth spring simulation.
    func densifyGaps(_ samples: [CursorSample]) -> [CursorSample] {
        guard samples.count >= 2 else { return samples }

        var result: [CursorSample] = [samples[0]]

        for i in 1 ..< samples.count {
            let prev = samples[i - 1]
            let curr = samples[i]
            let gap = curr.timestamp - prev.timestamp

            if gap > config.maxGapDuration {
                // Calculate number of interpolation points
                let targetPoints = Int(gap * config.densifyTargetRate)
                let pointCount = min(max(targetPoints, config.minDensifyPoints), config.maxDensifyPoints)

                for j in 1 ..< pointCount {
                    let t = Double(j) / Double(pointCount)
                    let interpSample = CursorSample(
                        timestamp: prev.timestamp + gap * t,
                        x: prev.x + (curr.x - prev.x) * t,
                        y: prev.y + (curr.y - prev.y) * t,
                        isDown: curr.isDown,
                        button: curr.button
                    )
                    result.append(interpSample)
                }
            }

            result.append(curr)
        }

        return result
    }

    // MARK: - Stage 3: Spring Smoothing

    /// Apply spring-mass-damper smoothing with context-aware profile switching.
    ///
    /// Profiles switch based on cursor context:
    /// - Near a click (within 200ms): `.snappy` for responsive feel
    /// - Button held down: `.drag` for heavy, controlled feel
    /// - Otherwise: `.default` for smooth general motion
    func applySpringSmoothing(_ samples: [CursorSample], clicks: [ClickSample] = []) -> [CursorSample] {
        guard samples.count >= 2 else { return samples }

        // Sort clicks by timestamp for binary search
        let sortedClicks = clicks.sorted { $0.timestamp < $1.timestamp }

        var spring = SpringMassDamperSimulation(
            position: .init(samples[0].x, samples[0].y),
            target: .init(samples[0].x, samples[0].y),
            profile: .default
        )

        var result: [CursorSample] = []

        for i in 0 ..< samples.count {
            let sample = samples[i]

            // Determine profile based on context
            let profile = selectProfile(for: sample, clicks: sortedClicks)
            spring.profile = profile

            // Calculate dt from previous sample
            let dt: Double
            if i == 0 {
                dt = 0
            } else {
                dt = sample.timestamp - samples[i - 1].timestamp
            }

            // Step spring toward cursor position
            spring.step(toward: .init(sample.x, sample.y), dt: dt)

            let smoothed = CursorSample(
                timestamp: sample.timestamp,
                x: spring.position.x,
                y: spring.position.y,
                isDown: sample.isDown,
                button: sample.button
            )
            result.append(smoothed)
        }

        return result
    }

    // MARK: - Profile Selection

    /// Time window (seconds) around a click where `.snappy` profile is used
    private static let clickProximityWindow: TimeInterval = 0.2

    /// Select spring profile based on cursor context
    private func selectProfile(
        for sample: CursorSample,
        clicks: [ClickSample]
    ) -> SpringMassDamperSimulation.Profile {
        // If button is held, use drag profile
        if sample.isDown {
            return .drag
        }

        // Check proximity to any click
        let isNearClick = clicks.contains { click in
            abs(click.timestamp - sample.timestamp) < Self.clickProximityWindow
        }

        if isNearClick {
            return .snappy
        }

        return .default
    }
}
