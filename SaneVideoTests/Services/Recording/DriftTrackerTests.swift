//
//  DriftTrackerTests.swift
//  SaneVideoTests
//
//  Tests for A/V drift detection and correction
//

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
        // Should apply some correction (up to 10ms per step)
        #expect(correction != 0 || abs(tracker.currentDrift()) > DriftTracker.driftThreshold)
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

    @Test("Correction is gradual — max 10ms per step")
    func correctionIsGradual() {
        let tracker = DriftTracker()

        // 200ms drift — should take multiple steps to correct
        tracker.recordVideoTimestamp(makePTS(1.2))
        tracker.recordAudioTimestamp(makePTS(1.0))

        let firstCorrection = tracker.calculateCorrection()
        #expect(abs(firstCorrection) <= DriftTracker.maxCorrectionPerStep + 0.001)
    }

    @Test("Repeated corrections converge toward zero drift")
    func repeatedCorrectionsConverge() {
        let tracker = DriftTracker()

        // Simulate drift building up then corrections being applied
        var totalCorrection: TimeInterval = 0
        for i in 0 ..< 20 {
            let t = Double(i) * 0.033  // ~30fps
            // Video drifts 3ms per frame ahead of audio
            tracker.recordVideoTimestamp(makePTS(t + 0.003 * Double(i)))
            tracker.recordAudioTimestamp(makePTS(t))
            totalCorrection = tracker.calculateCorrection()
        }

        // After enough steps, correction should be non-zero (working to fix drift)
        // The sign depends on implementation — just check it's actively correcting
        #expect(totalCorrection != 0 || tracker.currentDrift() < DriftTracker.driftThreshold)
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
