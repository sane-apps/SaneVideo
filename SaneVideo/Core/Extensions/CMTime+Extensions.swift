//
//  CMTime+Extensions.swift
//  SaneVideo
//
//  CMTime convenience extensions

import AVFoundation
import Foundation

extension CMTime {
    /// Create CMTime from seconds with standard timescale (retained for convenience)
    init(seconds: Double) {
        self.init(seconds: seconds, preferredTimescale: 600)
    }

    /// Returns true if two times are equal within a tolerance (seconds).
    func isNearlyEqual(to other: CMTime, toleranceSeconds: Double = 0.02) -> Bool {
        abs(self.seconds - other.seconds) <= toleranceSeconds
    }

    /// Clamps this time between `min` and `max`.
    func clamped(min: CMTime, max: CMTime) -> CMTime {
        Swift.max(min, Swift.min(self, max))
    }
}
