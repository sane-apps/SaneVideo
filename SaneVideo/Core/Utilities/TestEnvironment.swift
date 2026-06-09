import Foundation

/// Centralized utility for detecting execution environment and test states.
enum TestEnvironment {
  private static let sourceFileProjectRoot: String = {
    var url = URL(fileURLWithPath: #filePath)
    for _ in 0..<4 {
      url.deleteLastPathComponent()
    }
    return url.path
  }()

  private static var env: [String: String] {
    ProcessInfo.processInfo.environment
  }

  /// True if running in a UI test (XCUITest)
  static var isUITesting: Bool {
    let args = ProcessInfo.processInfo.arguments
    return args.contains("-uitesting") || args.contains("-ui_testing")
      || UserDefaults.standard.bool(forKey: "ui_testing") || env["UI_TESTING"] != nil
  }
  
  /// True if running in any test (unit or UI test)
  static var isTesting: Bool {
    // Check for XCTest environment
    let args = ProcessInfo.processInfo.arguments
    return isUITesting
      || args.contains("-XCTest") || args.contains("-xctest")
      || env["XCTestConfigurationFilePath"] != nil
      || NSClassFromString("XCTestCase") != nil
  }

  /// True when automation should never trigger camera/mic/screen permission prompts.
  static var suppressPermissionPrompts: Bool {
    isTesting || env["SANEAPPS_PERMISSIONLESS_AUTOMATION"] == "1"
  }

  /// True only for explicit opt-in hardware test runs.
  static var allowsHardwareIntegration: Bool {
    env["SANEVIDEO_ENABLE_HARDWARE_TESTS"] == "1"
  }

  /// True if the app should jump directly into the editor for testing
  static var shouldOpenEditor: Bool {
    shouldOpenEditor(
      arguments: ProcessInfo.processInfo.arguments,
      userDefaults: .standard,
      environment: env
    )
  }

  static func shouldOpenEditor(
    arguments: [String],
    userDefaults: UserDefaults,
    environment: [String: String]
  ) -> Bool {
    arguments.contains("-open_editor")
      || userDefaults.bool(forKey: "open_editor")
      || environment["OPEN_EDITOR"] == "1"
      || environment["SANEVIDEO_OPEN_EDITOR"] == "1"
      || explicitAssetURL(arguments: arguments, environment: environment) != nil
      || bootstrapProjectURL(in: environment) != nil
      || automationExportURL(in: environment) != nil
  }

  static var bootstrapProjectURL: URL? {
    bootstrapProjectURL(in: env)
  }

  static func bootstrapProjectURL(in environment: [String: String]) -> URL? {
    guard let rawPath = environment["TEST_PROJECT_PATH"] ?? environment["OPEN_PROJECT_PATH"] else {
      return nil
    }

    let path = rawPath.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !path.isEmpty, FileManager.default.fileExists(atPath: path) else {
      return nil
    }

    return URL(fileURLWithPath: path)
  }

  static var shouldBuildCommentaryReelAutomatically: Bool {
    env["AUTOMATION_BUILD_COMMENTARY_REEL"] == "1" || automationExportURL != nil
  }

  static var automationTranscriptURL: URL? {
    automationTranscriptURL(
      arguments: ProcessInfo.processInfo.arguments,
      environment: env
    )
  }

  static func automationTranscriptURL(in environment: [String: String]) -> URL? {
    automationTranscriptURL(arguments: [], environment: environment)
  }

  static func automationTranscriptURL(
    arguments: [String],
    environment: [String: String]
  ) -> URL? {
    guard let rawPath = argumentValue(
      for: ["-automation_transcript_path", "--automation-transcript-path"],
      in: arguments
    ) ?? environment["AUTOMATION_TRANSCRIPT_PATH"] else {
      return nil
    }

    let path = rawPath.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !path.isEmpty, FileManager.default.fileExists(atPath: path) else {
      return nil
    }

    return URL(fileURLWithPath: path)
  }

  static var shouldRefineAutomationCaptions: Bool {
    env["AUTOMATION_REFINE_CAPTIONS"] == "1"
  }

  static var shouldQuitAfterAutomation: Bool {
    env["AUTOMATION_QUIT_AFTER_EXPORT"] == "1"
  }

  static var automationExportURL: URL? {
    automationExportURL(in: env)
  }

  static func automationExportURL(in environment: [String: String]) -> URL? {
    guard let rawPath = environment["AUTOMATION_EXPORT_PATH"] else {
      return nil
    }

    let path = rawPath.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !path.isEmpty else {
      return nil
    }

    return URL(fileURLWithPath: path)
  }

  /// Standard path for the mock test video asset.
  /// Prioritizes persistent Tests/Assets over transient /tmp.
  static var mockAssetURL: URL {
    if let explicitURL = explicitAssetURL(
      arguments: ProcessInfo.processInfo.arguments,
      environment: env
    ) {
      return explicitURL
    }

    let filename = ProcessInfo.processInfo.environment["TEST_ASSET_NAME"] ?? "test_video.mp4"

    // 1. Check for explicit environment variable (Best for automated tests)
    if let envPath = ProcessInfo.processInfo.environment["PROJECT_DIR"] {
      let path = envPath + "/Tests/Assets/" + filename
      if FileManager.default.fileExists(atPath: path) {
        return URL(fileURLWithPath: path)
      }
    }

    // 2. Check the source-file-derived repo root (Works under xcodebuild and tests)
    let sourceRootAssetPath = sourceFileProjectRoot + "/Tests/Assets/" + filename
    if FileManager.default.fileExists(atPath: sourceRootAssetPath) {
      return URL(fileURLWithPath: sourceRootAssetPath)
    }

    // 3. Check current directory (Works if run from terminal in project root)
    let localPath = FileManager.default.currentDirectoryPath + "/Tests/Assets/" + filename
    if FileManager.default.fileExists(atPath: localPath) {
      return URL(fileURLWithPath: localPath)
    }

    // 4. Try to find project root by looking for project.yml
    let possibleRoots = [
      FileManager.default.currentDirectoryPath,
      sourceFileProjectRoot,
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

    // 5. Ultimate fallback - create temp directory
    let tmpPath = "/tmp/SaneVideo/" + filename
    return URL(fileURLWithPath: tmpPath)
  }

  static func explicitAssetURL(
    arguments: [String],
    environment: [String: String]
  ) -> URL? {
    guard let rawPath = argumentValue(
      for: ["-test_asset_path", "--test-asset-path"],
      in: arguments
    ) ?? environment["TEST_ASSET_PATH"] else {
      return nil
    }

    let path = rawPath.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !path.isEmpty, FileManager.default.fileExists(atPath: path) else {
      return nil
    }

    return URL(fileURLWithPath: path)
  }

  private static func argumentValue(for names: Set<String>, in arguments: [String]) -> String? {
    for (index, argument) in arguments.enumerated() {
      if names.contains(argument), arguments.indices.contains(index + 1) {
        return arguments[index + 1]
      }

      for name in names {
        let prefix = "\(name)="
        if argument.hasPrefix(prefix) {
          return String(argument.dropFirst(prefix.count))
        }
      }
    }

    return nil
  }

  /// Get a specific test asset by name
  static func testAsset(named name: String) -> URL {
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
    if let projectURL = bootstrapProjectURL {
      NSLog("🧪 [TestEnvironment] Bootstrap project: \(projectURL.path)")
    }
    if let exportURL = automationExportURL {
      NSLog("🧪 [TestEnvironment] Automation export: \(exportURL.path)")
    }
  }
}
