#if !APP_STORE
    import Foundation
    import SaneUI

    /// Donate copy for the direct download only. The App Store build never compiles it:
    /// Apple does not allow links to outside payment pages (guideline 3.1.1).
    enum SaneVideoDirectSupport {
        @MainActor
        static func install() {
            SaneDirectSupportCopy.current = SaneDirectSupportCopy(
                buttonTitle: "Donate",
                buttonHelp: "Donate on GitHub Sponsors",
                accessibilityLabel: "Donate",
                destinationURL: URL(string: "https://github.com/sponsors/MrSaneApps")!,
                aboutRowTitle: "Donate",
                freeAppTitle: "SaneVideo is free",
                freeAppDetail: "Every feature stays unlocked. Donate only if you want to support it.",
                welcomeIncludedDetail: "Every feature is included. Donate only if you want to support it.",
                expiredOpenSourceDetail: "Every feature stays unlocked. Donate only if you want to support it.",
                expiredCardTitle: "Donate",
                expiredCardSubtitle: "Optional. The app stays free."
            )
        }

        static let welcomeSupportFeatures: [(icon: String, text: String)] = [
            (icon: "checkmark.seal", text: "Every recording and edit tool is included"),
            (icon: "lock.open", text: "No trial and no paywall"),
            (icon: "heart.fill", text: "Donate only if you want to support it"),
            (icon: "square.stack.3d.up", text: "Local export. No subscription")
        ]
        static let welcomeSupportTitle = "Support SaneVideo"
        static let welcomeSupportPrice = "Donate if it helps you"
    }
#endif
