import Foundation
import SaneUI

extension SaneDiagnosticsService {
    static let shared = SaneDiagnosticsService(
        appName: "SaneVideo",
        subsystem: "com.sanevideo.app",
        githubRepo: "SaneVideo",
        settingsCollector: { await collectSaneVideoSettings() }
    )
}

@MainActor
private func collectSaneVideoSettings() -> String {
    let permissions = ServiceContainer.shared.permissionManager
    let prefs = ServiceContainer.shared.userPreferences
    let bundle = Bundle.main

    return """
    bundleIdentifier: \(bundle.bundleIdentifier ?? "unknown")
    appVersion: \(bundle.infoDictionary?["CFBundleShortVersionString"] as? String ?? "unknown")
    buildNumber: \(bundle.infoDictionary?["CFBundleVersion"] as? String ?? "unknown")

    permissions:
      camera: \(String(describing: permissions.cameraStatus))
      microphone: \(String(describing: permissions.microphoneStatus))
      screenRecording: \(String(describing: permissions.screenRecordingStatus))

    preferences:
      theme: \(prefs.appTheme.rawValue)
      defaultResolution: \(prefs.defaultResolution.rawValue)
      defaultCodec: \(prefs.defaultCodec)
      recordingResolution: \(prefs.recordingResolution.rawValue)
      recordingFPS: \(prefs.recordingFPS)
      excludeAppFromRecording: \(prefs.excludeAppFromRecording)
      transcriptionEngine: \(prefs.transcriptionEngine.rawValue)
    """
}
