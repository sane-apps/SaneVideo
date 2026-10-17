//
//  UserExperienceTests.swift
//  SaneVideoTests
//
//  Error copy that carries the underlying cause, and Magic Fix cancellation resetting
//  the processing state the overlay reads.
//

import AVFoundation
import Foundation
@testable import SaneVideo
import Testing

@Suite("User Experience")
struct UserExperienceTests {
    @Test("Recording engine error message includes the underlying cause")
    func recordingErrorMessageIncludesCause() {
        let error = AppError.recordingEngineError("Test error")

        #expect(!error.userFacingTitle.isEmpty)
        #expect(error.userFacingMessage.contains("Test error"))
    }

    @Test("Cancelling Magic Fix clears processing flag, status and progress")
    @MainActor
    func magicFixCancellationResetsState() async {
        let projectState = ProjectState()
        projectState.currentProject = VideoProject()

        let testURL = FileManager.default.temporaryDirectory.appendingPathComponent("magicfix_cancel_\(UUID().uuidString).mp4")
        let testClip = VideoClip(url: testURL, duration: CMTime(seconds: 10, preferredTimescale: 600))

        let magicFixTask = Task { @MainActor in
            await projectState.performMagicFix(for: testClip, options: MagicFixOptions())
        }

        // Let Magic Fix open its transaction before cancelling.
        for _ in 0 ..< 1000 where !projectState.isProcessing {
            await Task.yield()
        }

        await projectState.cancelProcessing()
        magicFixTask.cancel()
        await magicFixTask.value

        #expect(!projectState.isProcessing)
        #expect(projectState.processingStatus == nil)
        #expect(projectState.processingProgress == 0.0)
    }
}
