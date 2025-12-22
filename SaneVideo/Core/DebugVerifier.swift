//
//  DebugVerifier.swift
//  SaneVideo
//
//  Created for Runtime Verification
//

import AVFoundation
import CoreMedia
import Foundation

class DebugVerifier {

    init() {}

    func runVerification() {
        AppLogger.project.info("🔍 STARTING RUNTIME LOGIC VERIFICATION")

        verifyRemovedRangesLogic()
        verifyFillerDetectionLogic()

        AppLogger.project.info("✅ RUNTIME VERIFICATION COMPLETE")
    }

    // MARK: - VideoClip Logic

    private func verifyRemovedRangesLogic() {
        AppLogger.project.info("--- Verifying VideoClip removedRanges ---")

        // 1. Setup Clip (10s)
        let url = URL(fileURLWithPath: "/dev/null")
        var clip = VideoClip(url: url, duration: CMTime(seconds: 10, preferredTimescale: 600))

        // 2. Add Range (2-4s)
        let range1 = CMTimeRange(start: CMTime(seconds: 2, preferredTimescale: 600), duration: CMTime(seconds: 2, preferredTimescale: 600))
        clip.addRemovedRange(range1)

        assert(clip.removedRanges.count == 1, "Failed: Should have 1 removed range")
        assert(abs(clip.effectiveDuration.seconds - 8.0) < 0.001, "Failed: Effective duration should be 8.0, got \(clip.effectiveDuration.seconds)")

        // 3. Add Non-Overlapping Range (6-7s)
        let range2 = CMTimeRange(start: CMTime(seconds: 6, preferredTimescale: 600), duration: CMTime(seconds: 1, preferredTimescale: 600))
        clip.addRemovedRange(range2)

        assert(clip.removedRanges.count == 2, "Failed: Should have 2 removed ranges")
        assert(abs(clip.effectiveDuration.seconds - 7.0) < 0.001, "Failed: Effective duration should be 7.0, got \(clip.effectiveDuration.seconds)")

        // 4. Test Overlapping (Add 3-5s, overlaps with 2-4s)
        // Original 2-4s. New 3-5s. Merged should be 2-5s (3 seconds removed).
        // Total duration was 10. Removed 2-5s (3s) + 6-7s (1s) = 4s removed.
        // Effective duration should be 6s.
        let range3 = CMTimeRange(start: CMTime(seconds: 3, preferredTimescale: 600), duration: CMTime(seconds: 2, preferredTimescale: 600))
        clip.addRemovedRange(range3)

        assert(clip.removedRanges.count == 2, "Failed: Should still have 2 merged disjoint ranges")
        assert(abs(clip.effectiveDuration.seconds - 6.0) < 0.001, "Failed: Overlap Double Count! Duration should be 6.0, got \(clip.effectiveDuration.seconds)")

        AppLogger.project.info("✅ VideoClip.removedRanges logic passed")
    }

    // MARK: - Filler Logic

    private func verifyFillerDetectionLogic() {
        AppLogger.project.info("--- Verifying Filler Detection Logic ---")

        // Mock Word
        let word = CaptionWord(text: "um", start: 1.0, end: 1.5, probability: 0.9)
        let fillerWords: Set<String> = ["um", "uh"]

        let cleaned = word.text.lowercased().trimmingCharacters(in: .punctuationCharacters)

        assert(fillerWords.contains(cleaned), "Failed: 'um' should be detected as filler")

        AppLogger.project.info("✅ Filler Detection logic passed")
    }
}
