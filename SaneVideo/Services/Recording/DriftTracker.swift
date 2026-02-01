//
//  DriftTracker.swift
//  SaneVideo
//
//  Detects and gradually corrects A/V drift between video and audio streams.
//  Inspired by Cap's drift correction (PRs #1478, #1475).
//
//  Strategy:
//  - Tracks wall clock vs presentation time for video and audio
//  - When drift exceeds threshold (50ms), applies gradual correction
//  - Maximum correction per step: 10ms (prevents visible jumps)
//

import CoreMedia
import Foundation
import QuartzCore

/// Tracks and corrects audio/video timing drift during recording
final class DriftTracker: @unchecked Sendable {

    // MARK: - Configuration

    /// Drift threshold above which correction kicks in (seconds)
    static let driftThreshold: TimeInterval = 0.050  // 50ms

    /// Maximum correction applied per step (seconds)
    static let maxCorrectionPerStep: TimeInterval = 0.010  // 10ms

    // MARK: - State

    private let lock = NSLock()

    // Wall clock reference
    private var _wallClockStart: TimeInterval?

    // Latest presentation timestamps from each track
    private var _lastVideoPTS: CMTime = .invalid
    private var _lastAudioPTS: CMTime = .invalid

    // Timestamp of when each track's sample was received (wall clock)
    private var _lastVideoWallTime: TimeInterval = 0
    private var _lastAudioWallTime: TimeInterval = 0

    // Drift history for diagnostics
    private var _driftHistory: [DriftMeasurement] = []

    // Accumulated correction offset
    private var _correctionOffset: TimeInterval = 0

    // MARK: - Types

    /// A single drift measurement for diagnostics
    struct DriftMeasurement: Sendable {
        let timestamp: TimeInterval       // Wall clock time
        let videoPTS: TimeInterval        // Video presentation time
        let audioPTS: TimeInterval        // Audio presentation time
        let drift: TimeInterval           // Measured drift (video - audio)
        let correctionApplied: TimeInterval
    }

    // MARK: - Recording

    /// Record a video frame's presentation timestamp
    func recordVideoTimestamp(_ pts: CMTime) {
        let wallTime = CACurrentMediaTime()
        lock.withLock {
            if _wallClockStart == nil {
                _wallClockStart = wallTime
            }
            _lastVideoPTS = pts
            _lastVideoWallTime = wallTime
        }
    }

    /// Record an audio sample's presentation timestamp
    func recordAudioTimestamp(_ pts: CMTime) {
        let wallTime = CACurrentMediaTime()
        lock.withLock {
            if _wallClockStart == nil {
                _wallClockStart = wallTime
            }
            _lastAudioPTS = pts
            _lastAudioWallTime = wallTime
        }
    }

    // MARK: - Correction

    /// Calculate the correction offset to apply to presentation times.
    ///
    /// Returns 0 if drift is below threshold.
    /// Applies gradual correction (max 10ms per call) to avoid visible jumps.
    func calculateCorrection() -> TimeInterval {
        lock.withLock {
            guard _lastVideoPTS.isValid && _lastAudioPTS.isValid else { return 0 }

            // Measure drift: difference between video and audio stream times
            // relative to wall clock progression
            let videoPTSSeconds = _lastVideoPTS.seconds
            let audioPTSSeconds = _lastAudioPTS.seconds

            // A/V drift = how far apart the two streams are in presentation time
            // adjusted for when we received them (wall clock difference)
            let wallTimeDiff = _lastVideoWallTime - _lastAudioWallTime
            let drift = (videoPTSSeconds - audioPTSSeconds) - wallTimeDiff

            // Record measurement
            let measurement = DriftMeasurement(
                timestamp: _lastVideoWallTime - (_wallClockStart ?? 0),
                videoPTS: videoPTSSeconds,
                audioPTS: audioPTSSeconds,
                drift: drift,
                correctionApplied: _correctionOffset
            )
            _driftHistory.append(measurement)

            // Limit history to last 300 measurements (~10s at 30fps)
            if _driftHistory.count > 300 {
                _driftHistory.removeFirst(_driftHistory.count - 300)
            }

            // Only correct if drift exceeds threshold
            guard abs(drift) > Self.driftThreshold else { return _correctionOffset }

            // Gradual correction: move toward zero drift, max 10ms per step
            let correctionStep: TimeInterval
            if drift > 0 {
                correctionStep = min(drift - Self.driftThreshold, Self.maxCorrectionPerStep)
            } else {
                correctionStep = max(drift + Self.driftThreshold, -Self.maxCorrectionPerStep)
            }

            _correctionOffset += correctionStep
            return _correctionOffset
        }
    }

    /// Get the current drift without applying correction
    func currentDrift() -> TimeInterval {
        lock.withLock {
            guard _lastVideoPTS.isValid && _lastAudioPTS.isValid else { return 0 }
            let wallTimeDiff = _lastVideoWallTime - _lastAudioWallTime
            return (_lastVideoPTS.seconds - _lastAudioPTS.seconds) - wallTimeDiff
        }
    }

    /// Get drift measurement history for diagnostics
    func getDriftHistory() -> [DriftMeasurement] {
        lock.withLock { _driftHistory }
    }

    /// Reset all state
    func reset() {
        lock.withLock {
            _wallClockStart = nil
            _lastVideoPTS = .invalid
            _lastAudioPTS = .invalid
            _lastVideoWallTime = 0
            _lastAudioWallTime = 0
            _driftHistory = []
            _correctionOffset = 0
        }
    }
}
