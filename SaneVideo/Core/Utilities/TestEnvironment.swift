import Foundation

/// Centralized utility for detecting execution environment and test states.
enum TestEnvironment {
    
    /// True if running in a UI test (XCUITest)
    static var isUITesting: Bool {
        let args = ProcessInfo.processInfo.arguments
        let env = ProcessInfo.processInfo.environment
        return args.contains("-uitesting") || 
               args.contains("-ui_testing") ||
               UserDefaults.standard.bool(forKey: "ui_testing") ||
               env["UI_TESTING"] != nil ||
               env["XCTestConfigurationFilePath"] != nil
    }
    
    /// True if the app should jump directly into the editor for testing
    static var shouldOpenEditor: Bool {
        let args = ProcessInfo.processInfo.arguments
        return args.contains("-open_editor") || 
               UserDefaults.standard.bool(forKey: "open_editor")
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
        
        // 3. Fallback to known development path on this machine
        let devPath = "/Users/sj/SaneVideo/Tests/Assets/" + filename
        if FileManager.default.fileExists(atPath: devPath) {
            return URL(fileURLWithPath: devPath)
        }
        
        // 4. Ultimate fallback
        return URL(fileURLWithPath: "/tmp/SaneVideo/" + filename)
    }
    
    /// Shared logger for environment detection
    static func logState() {
        if isUITesting {
            NSLog("🧪 [TestEnvironment] UI Testing Mode ACTIVE (PID: \(ProcessInfo.processInfo.processIdentifier))")
        }
        if shouldOpenEditor {
            NSLog("🧪 [TestEnvironment] Jump-to-Editor Mode ACTIVE")
        }
    }
}
