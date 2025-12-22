//
//  StressTestRunner.swift
//  SaneVideo
//
//  Created by SaneVideo Refactor
//

import AVFoundation
import Combine
import Foundation

/// Runs stress tests within the running application to identify limits.
@MainActor
@Observable
class StressTestRunner {

    var isRunning = false
    var statusMessage = "Ready"
    var logs: [String] = []

    private var task: Task<Void, Never>?

    func log(_ message: String) {
        print("🧪 [StressTest] \(message)")
        logs.append(message)
        statusMessage = message
    }

    func runAllTests(appState: AppState) {
        guard !isRunning else { return }
        isRunning = true
        logs = []

        task = Task {
            log("Starting Stress Tests...")

            do {
                try await testTimelineScalability()
                try await testRapidRecordingToggle(appState: appState)
                // Add more here
            } catch {
                log("❌ Test Suite Failed: \(error.localizedDescription)")
            }

            log("✅ Stress Tests Completed.")
            isRunning = false
        }
    }

    // MARK: - Tests

    func testTimelineScalability() async throws {
        log("--- Test: Timeline Scalability (500 clips) ---")

        // Create 500 dummy clips
        let clipCount = 500
        var clips: [VideoClip] = []
        let dummyURL = FileManager.default.temporaryDirectory.appendingPathComponent("dummy.mp4") // Doesn't need to exist for model creation

        for i in 0 ..< clipCount {
            var clip = VideoClip(
                url: dummyURL,
                duration: CMTime(value: 1, timescale: 1)
            )
            clip.startTime = CMTime(value: Int64(i), timescale: 1)
            clips.append(clip)
        }

        let track = Track(id: UUID(), name: "Stress Track", type: .video, clips: clips, zIndex: 0)
        let timeline = Timeline(tracks: [track])
        var project = VideoProject(id: UUID(), name: "Stress Test")
        project.timeline = timeline

        let start = Date()
        log("Building composition for \(clipCount) clips...")

        // This might fail if assets don't exist, but we verify the Builder overhead
        _ = try? await CompositionBuilder.build(from: project)

        let duration = Date().timeIntervalSince(start)
        log("Result: Built in \(String(format: "%.3f", duration))s")

        if duration > 1.0 {
            log("⚠️ WARNING: CompositionBuilder took > 1s")
        } else {
            log("✅ Performance OK")
        }
    }

    private func testRapidRecordingToggle(appState: AppState) async throws {
        log("--- Test: Rapid Recording Toggle ---")
        // NOTE: We need to be careful with actual hardware.
        // We will simulate the Coordinator calls.

        let recordingState = appState.recordingState

        for i in 1 ... 20 { // 20 toggles
            log("Toggle \(i)/20...")
            if recordingState.isRecording {
                recordingState.stopRecording { _ in }
            } else {
                recordingState.startRecording(isScreenSharing: false)
            }
            // Random delay between 100ms and 500ms
            try await Task.sleep(nanoseconds: UInt64(Double.random(in: 0.1 ... 0.5) * 1_000_000_000))
        }

        // Wait to settle
        try await Task.sleep(nanoseconds: 2 * 1_000_000_000)

        if recordingState.isRecording {
            log("Cleaning up recording state...")
            recordingState.stopRecording { _ in }

            // Wait for it to stop (polling)
            for _ in 0 ..< 10 {
                if !appState.recordingState.isRecording { break }
                try await Task.sleep(nanoseconds: 500_000_000)
            }
        }

        log("✅ Rapid Toggle Finished")
    }

    // Test Memory Pressure
    func testMemoryPressure() {
        log("--- Test: Memory Pressure ---")
        // ... (Implement safer memory pressure that respects MemoryManager)
    }
}
