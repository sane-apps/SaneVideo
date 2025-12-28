import Foundation

/// Centralized utility for detecting execution environment and test states.
enum TestEnvironment {

  /// True if running in a UI test (XCUITest)
  static var isUITesting: Bool {
    let args = ProcessInfo.processInfo.arguments
    let env = ProcessInfo.processInfo.environment
    return args.contains("-uitesting") || args.contains("-ui_testing")
      || UserDefaults.standard.bool(forKey: "ui_testing") || env["UI_TESTING"] != nil
  }
  
  /// True if running in any test (unit or UI test)
  static var isTesting: Bool {
    // Check for XCTest environment
    let args = ProcessInfo.processInfo.arguments
    let env = ProcessInfo.processInfo.environment
    return isUITesting
      || args.contains("-XCTest") || args.contains("-xctest")
      || env["XCTestConfigurationFilePath"] != nil
      || NSClassFromString("XCTestCase") != nil
  }

  /// True if the app should jump directly into the editor for testing
  static var shouldOpenEditor: Bool {
    let args = ProcessInfo.processInfo.arguments
    return args.contains("-open_editor") || UserDefaults.standard.bool(forKey: "open_editor")
  }

  /// Standard path for the mock test video asset.
  /// Prioritizes persistent Tests/Assets over transient /tmp.
  static var mockAssetURL: URL {
    let filename = ProcessInfo.processInfo.environment["TEST_ASSET_NAME"] ?? "test_video.mp4"

    // 1. Check for explicit environment variable (Best for automated tests)
    if let envPath = ProcessInfo.processInfo.environment["PROJECT_DIR"] {
      let path = envPath + "/Tests/Assets/" + filename
      if FileManager.default.fileExists(atPath: path) {
        return URL(fileURLWithPath: path)
      }
    }

    // 2. Check current directory (Works if run from terminal in project root)
    let localPath = FileManager.default.currentDirectoryPath + "/Tests/Assets/" + filename
    if FileManager.default.fileExists(atPath: localPath) {
      return URL(fileURLWithPath: localPath)
    }

    // 3. Try to find project root by looking for project.yml
    let possibleRoots = [
      FileManager.default.currentDirectoryPath,
      FileManager.default.homeDirectoryForCurrentUser.path + "/SaneVideo",
      Bundle.main.bundlePath + "/../../../.."  // From .app bundle
    ]

    for root in possibleRoots {
      let projectYml = root + "/project.yml"
      if FileManager.default.fileExists(atPath: projectYml) {
        let assetPath = root + "/Tests/Assets/" + filename
        if FileManager.default.fileExists(atPath: assetPath) {
          return URL(fileURLWithPath: assetPath)
        }
      }
    }

    // 4. Ultimate fallback - create temp directory
    let tmpPath = "/tmp/SaneVideo/" + filename
    return URL(fileURLWithPath: tmpPath)
  }

  /// Get a specific test asset by name
  static func testAsset(named name: String) -> URL {
    let originalEnv = ProcessInfo.processInfo.environment["TEST_ASSET_NAME"]
    // Temporarily override to get the specific asset
    let url = mockAssetURL
    let directory = url.deletingLastPathComponent()
    return directory.appendingPathComponent(name)
  }

  /// Shared logger for environment detection
  static func logState() {
    if isUITesting {
      NSLog(
        "🧪 [TestEnvironment] UI Testing Mode ACTIVE (PID: \(ProcessInfo.processInfo.processIdentifier))"
      )
    }
    if shouldOpenEditor {
      NSLog("🧪 [TestEnvironment] Jump-to-Editor Mode ACTIVE")
    }
  }
}
