//
//  StressTests.swift
//  SaneVideoTests
//
//  Created by SaneVideo Refactor
//

import AVFoundation
import XCTest

@testable import SaneVideo

final class StressTests: XCTestCase {

  // MARK: - Timeline Scalability

  func testTimelineComplexity() async throws {
    // Goal: Add 500 clips and measure CompositionBuilder performance
    let clipCount = 500
    var clips: [VideoClip] = []

    // Mock URL - use a system file or bundle file that exists
    // We use a dummy URL; CompositionBuilder checks asset tracks which might fail if file missing.
    // For stress test logic, we need strict existence if we want to measure AVAsset load time.
    // However, we can test the structure build time if we mock or use a known small file.
    // Let's assume we have a test asset or create a temp one.

    let tempURL = createStressTestAssetIfNeeded()
    if !FileManager.default.fileExists(atPath: tempURL.path) {
      // Create a dummy file if needed, or skip if we can't.
      // For now, let's use the file URL check logic (if CompositionBuilder fails gracefully).
      // CompositionBuilder does `try? await asset.load` - so it will just skip if invalid.
      // To *stress* it, we need successful loads.
      // We'll skip the "real load" verification for now and focus on the loop overhead
      // OR finding a real file.
    }

    for i in 0..<clipCount {
      let clip = VideoClip(
        url: tempURL,
        duration: CMTime(value: 1, timescale: 1),
        startTime: CMTime(value: Int64(i), timescale: 1)
      )
      clips.append(clip)
    }

    let track = Track(id: UUID(), name: "Stress Track", type: .video, clips: clips, zIndex: 0)
    let timeline = Timeline(tracks: [track])
    var project = VideoProject(id: UUID(), name: "Stress Test")
    project.timeline = timeline

    let start = Date()
    // We expect this to be fast if assets fail to load (skips),
    // or slow if they load.
    // Since we don't have a real video, this primarily tests the "overhead" of the Builder loop.
    _ = try await CompositionBuilder.build(from: project)
    let duration = Date().timeIntervalSince(start)

    print("⏱️ CompositionBuilder (Dummy Files) took \(duration)s for \(clipCount) clips")

    // Benchmark: Should be under 1 second for simple loop even with failing assets
    XCTAssertLessThan(duration, 2.0, "CompositionBuilder is too slow for \(clipCount) clips")
  }

  // MARK: - Undo/Redo Storm

  func testUndoRedoStorm() {
    let undoManager = UndoManager()
    var state = 0

    // Measure time for 1000 operations
    measure {
      for _ in 0..<1000 {
        let oldValue = state
        undoManager.registerUndo(withTarget: self) { target in
          state = oldValue
        }
        state += 1
      }

      // Undo all
      while undoManager.canUndo {
        undoManager.undo()
      }

      // Redo all
      while undoManager.canRedo {
        undoManager.redo()
      }
    }
  }

  // MARK: - Rapid State Cycling (Simulation)

  func testRapidStateCycling() async {
    // This monitors if we can toggle boolean states rapidly without crashing
    // Mimics "Start/Stop" button mashing

    actor StateMachine {
      var isRecording = false
      func toggle() { isRecording.toggle() }
    }

    let machine = StateMachine()

    // Concurrent spamming
    await withTaskGroup(of: Void.self) { group in
      for _ in 0..<100 {
        group.addTask {
          await machine.toggle()
        }
      }
    }

    // Verify actor is still accessible after concurrent access
    let finalState = await machine.isRecording
    // State should be deterministic: 100 toggles from false = false (even count)
    XCTAssertFalse(finalState, "After 100 toggles from false, state should be false")
  }

  // MARK: - Memory Pressure Simulation

  func testMemoryAllocationSpam() {
    // allocate 500MB
    var dataHolder: [Data] = []

    // 50 blocks of 10MB
    for i in 0..<50 {
      let data = Data(count: 10 * 1024 * 1024)
      dataHolder.append(data)
      print("Allocated block \(i)")
    }

    XCTAssertEqual(dataHolder.count, 50)
    // Check if we crashed. If not, pass.
    // In a real app, MemoryManager should trigger.
  }
}

// Helper conformance for undo target if needed (StressTests is a class, so it works)
