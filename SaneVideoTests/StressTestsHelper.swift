import Foundation
import XCTest

func createStressTestAssetIfNeeded() -> URL {
  let tempURL = FileManager.default.temporaryDirectory.appendingPathComponent(
    "stress_test_clip.mp4")
  if FileManager.default.fileExists(atPath: tempURL.path) {
    return tempURL
  }

  // Try to find in bundle
  let bundle = Bundle(for: StressTests.self)
  if let path = bundle.path(forResource: "test_video", ofType: "mp4") {
    try? FileManager.default.copyItem(atPath: path, toPath: tempURL.path)
    return tempURL
  }

  // Fallback or error
  print("⚠️ Warning: Could not find test_video.mp4 in bundle")
  return tempURL
}
