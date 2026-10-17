// The direct download keeps Donate; the App Store build never compiles the copy (guideline 3.1.1).

import Foundation
@testable import SaneVideo
import SaneUI
import Testing

@Suite("Direct Support")
@MainActor
struct DirectSupportTests {
    @Test("The direct download installs Donate copy that opens GitHub Sponsors")
    func directDownloadKeepsDonate() {
        OpenSourceRelease.activate()

        #expect(SaneDirectSupportCopy.current?.buttonTitle == "Donate")
        #expect(OpenSourceRelease.donationURL?.absoluteString == "https://github.com/sponsors/MrSaneApps")
        #expect(OpenSourceRelease.welcomeSupportFeatures.contains { $0.text.contains("Donate") })
    }

    @Test("App Store screenshot mode hides Donate in the direct build")
    func storeScreenshotModeHidesDonate() {
        OpenSourceRelease.activate()
        setenv("SANEVIDEO_STORE_SCREENSHOTS", "1", 1)
        defer { unsetenv("SANEVIDEO_STORE_SCREENSHOTS") }

        #expect(OpenSourceRelease.donationURL == nil)
    }
}
