// Camera preview mirroring preference: fresh installs show an un-mirrored preview,
// and the user's choice persists under the key the preview reads.

import Foundation
@testable import SaneVideo
import Testing

@Suite("Camera Preview Mirroring")
@MainActor
struct CameraConcurrencyRegressionTests {
    @Test("Mirroring defaults off and persists under the preview's key")
    func mirroringPreferenceDefaultsOffAndPersists() {
        let key = CameraPreviewMirroring.appStorageKey
        let defaults = UserDefaults.standard
        let oldValue = defaults.object(forKey: key)
        defer {
            if let oldValue {
                defaults.set(oldValue, forKey: key)
            } else {
                defaults.removeObject(forKey: key)
            }
        }

        defaults.removeObject(forKey: key)
        let prefs = UserPreferences()

        #expect(!CameraPreviewMirroring.defaultIsMirrored)
        #expect(!prefs.mirrorCameraPreview, "Fresh installs should show a non-mirrored camera")

        prefs.mirrorCameraPreview = true
        #expect(defaults.bool(forKey: key))
    }
}
