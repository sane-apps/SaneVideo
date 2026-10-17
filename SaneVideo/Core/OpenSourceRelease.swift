import Foundation
import SaneUI

enum OpenSourceRelease {
    /// The Donate destination on the direct download; nil in the App Store build.
    @MainActor
    static var donationURL: URL? {
        // App Store screenshots are taken from the direct build; this hides Donate for that capture.
        if ProcessInfo.processInfo.environment["SANEVIDEO_STORE_SCREENSHOTS"] == "1" {
            return nil
        }
        return SaneDirectSupportCopy.current?.destinationURL
    }

    @MainActor
    static func activate() {
        UserDefaults.standard.set(true, forKey: "SANEAPPS_OPEN_SOURCE")
        setenv("SANEAPPS_FORCE_PRO_MODE", "1", 1)
        #if !APP_STORE
            SaneVideoDirectSupport.install()
        #endif
    }

    #if APP_STORE
        static let welcomeSupportFeatures: [(icon: String, text: String)] = [
            (icon: "checkmark.seal", text: "Every recording and edit tool is included"),
            (icon: "lock.open", text: "No trial, no paywall, no in-app purchase"),
            (icon: "square.stack.3d.up", text: "Local export. No subscription")
        ]
        static let welcomeSupportTitle = "Free for everyone"
        static let welcomeSupportPrice = "Nothing to buy"
    #else
        static let welcomeSupportFeatures = SaneVideoDirectSupport.welcomeSupportFeatures
        static let welcomeSupportTitle = SaneVideoDirectSupport.welcomeSupportTitle
        static let welcomeSupportPrice = SaneVideoDirectSupport.welcomeSupportPrice
    #endif
}
