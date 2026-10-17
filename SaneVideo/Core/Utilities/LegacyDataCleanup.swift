import Foundation
import Security

/// One-time removal of data left by features that no longer exist.
enum LegacyDataCleanup {
    private static let doneKey = "LegacyDataCleanup.v1"

    static func runOnce(defaults: UserDefaults = .standard, fileManager: FileManager = .default) {
        guard !defaults.bool(forKey: doneKey) else { return }

        // YouTube upload credentials (API Keys settings, removed in 1.1).
        let service = (Bundle.main.bundleIdentifier ?? "com.sanevideo.app") + ".apikeys"
        SecItemDelete([kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service] as CFDictionary)

        // WhisperKit models (~1 GB); captions now use Apple's speech engine or Parakeet.
        if let support = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first {
            try? fileManager.removeItem(at: support.appendingPathComponent("SaneVideo/WhisperKitModels", isDirectory: true))
        }

        for key in ["iCloudSyncEnabled", "TranscriptionEngine"] {
            defaults.removeObject(forKey: key)
        }
        defaults.set(true, forKey: doneKey)
    }
}
