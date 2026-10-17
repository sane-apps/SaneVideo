// Tests for A/V drift detection and correction

import CoreMedia
import Testing

@testable import SaneVideo

struct DriftTrackerTests {

    // MARK: - Helpers

    private func makePTS(_ seconds: Double) -> CMTime {
        CMTime(seconds: seconds, preferredTimescale: 600)
    }

    // MARK: - Basic Drift Detection

    @Test("No drift when video and audio are in sync")
    func noDriftWhenInSync() {
        let tracker = DriftTracker()

        tracker.recordVideoTimestamp(makePTS(1.0))
        tracker.recordAudioTimestamp(makePTS(1.0))

        let correction = tracker.calculateCorrection()
        #expect(abs(correction) < 0.001)
    }

    @Test("Drift detected when video leads audio beyond threshold")
    func driftDetectedVideoLeads() {
        let tracker = DriftTracker()

        // Video is 100ms ahead of audio (above 50ms threshold)
        tracker.recordVideoTimestamp(makePTS(1.1))
        tracker.recordAudioTimestamp(makePTS(1.0))

        let correction = tracker.calculateCorrection()
        // 100 ms drift is 50 ms over the threshold, so one full 10 ms step applies.
        #expect(abs(correction - DriftTracker.maxCorrectionPerStep) < 0.0005)
    }

    @Test("No correction when drift is below threshold")
    func noCorrectionBelowThreshold() {
        let tracker = DriftTracker()

        // 20ms drift — below 50ms threshold
        tracker.recordVideoTimestamp(makePTS(1.02))
        tracker.recordAudioTimestamp(makePTS(1.0))

        let correction = tracker.calculateCorrection()
        #expect(abs(correction) < 0.001)
    }

    // MARK: - Gradual Correction

    @Test("A large drift is corrected 10 ms per call, accumulating")
    func correctionIsGradual() {
        let tracker = DriftTracker()

        // 200ms drift — should take multiple steps to correct
        tracker.recordVideoTimestamp(makePTS(1.2))
        tracker.recordAudioTimestamp(makePTS(1.0))

        let firstCorrection = tracker.calculateCorrection()
        let secondCorrection = tracker.calculateCorrection()
        // 150 ms over threshold, yet each call adds only one 10 ms step.
        #expect(abs(firstCorrection - DriftTracker.maxCorrectionPerStep) < 0.0005)
        #expect(abs(secondCorrection - 2 * DriftTracker.maxCorrectionPerStep) < 0.0005)
    }

    @Test("Growing video lead is corrected only past the threshold, 10 ms per step at most")
    func repeatedCorrectionsConverge() {
        let tracker = DriftTracker()

        // Video drifts 3 ms per frame ahead of audio at ~30 fps.
        var totalCorrection: TimeInterval = 0
        var stepsAboveThreshold = 0
        for i in 0 ..< 20 {
            let t = Double(i) * 0.033
            tracker.recordVideoTimestamp(makePTS(t + 0.003 * Double(i)))
            tracker.recordAudioTimestamp(makePTS(t))
            if tracker.currentDrift() > DriftTracker.driftThreshold {
                stepsAboveThreshold += 1
            }
            totalCorrection = tracker.calculateCorrection()
        }

        // Correction only starts once drift passes 50 ms, counters the video lead,
        // and never exceeds 10 ms per correcting step.
        #expect(stepsAboveThreshold > 0)
        #expect(totalCorrection > 0)
        #expect(totalCorrection <= Double(stepsAboveThreshold) * DriftTracker.maxCorrectionPerStep + 1e-9)
    }

    // MARK: - History

    @Test("Drift history is recorded")
    func driftHistoryRecorded() {
        let tracker = DriftTracker()

        tracker.recordVideoTimestamp(makePTS(1.0))
        tracker.recordAudioTimestamp(makePTS(1.0))
        _ = tracker.calculateCorrection()

        let history = tracker.getDriftHistory()
        #expect(!history.isEmpty)
    }

    // MARK: - Reset

    @Test("Reset clears all state")
    func resetClearsState() {
        let tracker = DriftTracker()

        tracker.recordVideoTimestamp(makePTS(1.0))
        tracker.recordAudioTimestamp(makePTS(1.0))
        _ = tracker.calculateCorrection()

        tracker.reset()

        #expect(tracker.getDriftHistory().isEmpty)
        #expect(abs(tracker.currentDrift()) < 0.001)
        #expect(abs(tracker.calculateCorrection()) < 0.001)
    }
}
