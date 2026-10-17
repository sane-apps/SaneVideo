import AVFoundation
import Foundation

extension CMTime {
    /// Uses the 600 timescale shared by clip times.
    init(seconds: Double) {
        self.init(seconds: seconds, preferredTimescale: 600)
    }

    /// Returns true if two times are equal within a tolerance (seconds).
    func isNearlyEqual(to other: CMTime, toleranceSeconds: Double = 0.02) -> Bool {
        abs(self.seconds - other.seconds) <= toleranceSeconds
    }

    func clamped(min: CMTime, max: CMTime) -> CMTime {
        Swift.max(min, Swift.min(self, max))
    }
}
