import XCTest

final class ReleaseReadinessRegressionTests: XCTestCase {
    private var sourceRoot: URL {
        URL(fileURLWithPath: #file)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
    }

    func testLibraryDeleteFromDiskHasReachableConfirmation() throws {
        let libraryView = try String(
            contentsOf: sourceRoot.appendingPathComponent("SaneVideo/Views/Components/LibraryView.swift"),
            encoding: .utf8
        )

        XCTAssertTrue(libraryView.contains("LibraryClipContextMenu(clip: clip)"))
        XCTAssertTrue(libraryView.contains("onRequestDeleteFile()"))
        XCTAssertTrue(libraryView.contains("sidebar.delete_disk_confirm"))
    }

    func testExportShareIsDisabledForEmptyTimeline() throws {
        let exportView = try String(
            contentsOf: sourceRoot.appendingPathComponent("SaneVideo/Views/ExportView.swift"),
            encoding: .utf8
        )
        let exportActions = try String(
            contentsOf: sourceRoot.appendingPathComponent("SaneVideo/Views/Export/ExportView+Actions.swift"),
            encoding: .utf8
        )

        XCTAssertTrue(exportView.contains(".disabled(isExporting || youtubeService.isUploading || isTimelineEmpty)"))
        XCTAssertTrue(exportActions.contains("Add at least one clip before sharing an exported file."))
    }

    func testCustomerSettingsAndTextContrastAreReleaseTight() throws {
        let mainContent = try String(
            contentsOf: sourceRoot.appendingPathComponent("SaneVideo/Views/MainContentView.swift"),
            encoding: .utf8
        )
        let settings = try String(
            contentsOf: sourceRoot.appendingPathComponent("SaneVideo/Views/SettingsView.swift"),
            encoding: .utf8
        )
        let privacySettings = try String(
            contentsOf: sourceRoot.appendingPathComponent("SaneVideo/Views/Settings/PrivacySettingsView.swift"),
            encoding: .utf8
        )
        let designSystem = try String(
            contentsOf: sourceRoot.appendingPathComponent("SaneVideo/Core/DesignSystem.swift"),
            encoding: .utf8
        )

        XCTAssertTrue(settings.contains("#if DEBUG"))
        XCTAssertTrue(mainContent.contains("#if DEBUG"))
        XCTAssertTrue(mainContent.contains("BuildTimestampView()"))
        XCTAssertTrue(settings.contains("PrivacySettingsView(selectedTab: $selectedTab)"))
        XCTAssertTrue(privacySettings.contains("selectedTab = \"apikeys\""))
        XCTAssertFalse(privacySettings.contains("NavigationLink"))
        XCTAssertTrue(designSystem.contains("static let stone = Color.white.opacity(0.9)"))
    }

    func testPurchaseAndPermissionCopyAvoidsV1PromiseDrift() throws {
        let appSource = try String(contentsOf: sourceRoot.appendingPathComponent("SaneVideo/SaneVideoApp.swift"), encoding: .utf8)
        let appError = try String(contentsOf: sourceRoot.appendingPathComponent("SaneVideo/Core/AppError.swift"), encoding: .utf8)
        let exportConfiguration = try String(
            contentsOf: sourceRoot.appendingPathComponent("SaneVideo/Views/Export/ExportConfigurationView.swift"),
            encoding: .utf8
        )

        XCTAssertFalse(appSource.contains("Cloud sync for project assets"))
        XCTAssertTrue(appSource.contains("Optional during public testing"))
        XCTAssertTrue(appSource.contains("Keep Pro access as paid features land"))
        XCTAssertTrue(appError.contains("Screen Recording Permission Required"))
        XCTAssertTrue(appError.contains("Screen & System Audio Recording access"))
        XCTAssertTrue(exportConfiguration.contains(".frame(minWidth: 220, maxWidth: 260"))
    }

    func testAppStoreLaneIsSeparateFromDirectSparkleLane() throws {
        let project = try String(contentsOf: sourceRoot.appendingPathComponent("project.yml"), encoding: .utf8)
        let appSource = try String(contentsOf: sourceRoot.appendingPathComponent("SaneVideo/SaneVideoApp.swift"), encoding: .utf8)
        let directPlist = try String(contentsOf: sourceRoot.appendingPathComponent("SaneVideo/Info.plist"), encoding: .utf8)
        let directEntitlements = try String(contentsOf: sourceRoot.appendingPathComponent("SaneVideo/SaneVideo.entitlements"), encoding: .utf8)
        let appStorePlist = try String(contentsOf: sourceRoot.appendingPathComponent("SaneVideo/Info-AppStore.plist"), encoding: .utf8)
        let appStoreEntitlements = try String(contentsOf: sourceRoot.appendingPathComponent("SaneVideo/SaneVideo-AppStore.entitlements"), encoding: .utf8)

        XCTAssertTrue(project.contains("SaneVideoAppStore:"))
        XCTAssertTrue(project.contains("INFOPLIST_FILE: SaneVideo/Info-AppStore.plist"))
        XCTAssertTrue(project.contains("INFOPLIST_KEY_AppStoreProductID: com.sanevideo.app.pro.access.v2"))
        XCTAssertTrue(project.contains("CODE_SIGN_IDENTITY: \"Apple Distribution\""))
        XCTAssertFalse(appSource.contains("https://go.saneapps.com/buy/sanevideo"))
        XCTAssertTrue(appSource.contains("LicenseService.directCheckoutURL(appSlug: \"sanevideo\")"))
        XCTAssertTrue(directPlist.contains("<string>$(MARKETING_VERSION)</string>"))
        XCTAssertTrue(directPlist.contains("<string>$(CURRENT_PROJECT_VERSION)</string>"))
        XCTAssertTrue(appStorePlist.contains("<string>$(MARKETING_VERSION)</string>"))
        XCTAssertTrue(appStorePlist.contains("<string>$(CURRENT_PROJECT_VERSION)</string>"))
        XCTAssertFalse(directPlist.contains("<key>CFBundleShortVersionString</key>\n\t<string>1.0</string>"))
        XCTAssertFalse(appStorePlist.contains("<key>CFBundleShortVersionString</key>\n\t<string>1.0</string>"))
        XCTAssertTrue(directPlist.contains("<key>SUFeedURL</key>"))
        XCTAssertTrue(directPlist.contains("<key>SUPublicEDKey</key>"))
        XCTAssertTrue(directPlist.contains("<key>SUEnableAutomaticChecks</key>"))
        XCTAssertTrue(directPlist.contains("<false/>"))
        XCTAssertTrue(directPlist.contains("<key>SUEnableInstallerLauncherService</key>"))
        XCTAssertTrue(directEntitlements.contains("com.apple.security.temporary-exception.mach-lookup.global-name"))
        XCTAssertTrue(directEntitlements.contains("com.sanevideo.app-spki"))
        XCTAssertTrue(directEntitlements.contains("com.sanevideo.app-spks"))
        XCTAssertTrue(appStorePlist.contains("<key>AppStoreProductID</key>"))
        XCTAssertFalse(appStorePlist.contains("SUFeedURL"))
        XCTAssertFalse(appStorePlist.contains("SUPublicEDKey"))
        XCTAssertFalse(appStorePlist.contains("SUEnableAutomaticChecks"))
        XCTAssertFalse(appStorePlist.contains("SUEnableInstallerLauncherService"))
        XCTAssertFalse(appStoreEntitlements.contains("mach-lookup"))
        XCTAssertFalse(appStoreEntitlements.contains("com.sanevideo.app-spki"))
        XCTAssertFalse(appStoreEntitlements.contains("com.sanevideo.app-spks"))
    }

    func testAppStoreScreenshotStoryboardAndGeneratorCoverLaunchSellingPoints() throws {
        let storyboardURL = sourceRoot.appendingPathComponent("Screenshots/appstore_screenshot_storyboard.yml")
        let generatorURL = sourceRoot.appendingPathComponent("scripts/generate_appstore_screenshots.swift")
        let storyboard = try String(contentsOf: storyboardURL, encoding: .utf8)
        let generator = try String(contentsOf: generatorURL, encoding: .utf8)
        let website = try String(
            contentsOf: sourceRoot.appendingPathComponent("docs/index.html"),
            encoding: .utf8
        )

        XCTAssertTrue(storyboard.contains("Edit locally with Magic Fix tools"))
        XCTAssertTrue(storyboard.contains("Save, edit, or share a recording"))
        XCTAssertTrue(storyboard.contains("Polish clips with Magic Fix"))
        XCTAssertTrue(storyboard.contains("feature claims without matching real captures"))
        XCTAssertTrue(storyboard.contains("must_not_show:"))
        XCTAssertTrue(storyboard.contains("build timestamp"))
        XCTAssertTrue(storyboard.contains("Use actual SaneVideo app screenshots only"))
        XCTAssertTrue(storyboard.contains("Do not create fake UI"))
        XCTAssertTrue(storyboard.contains("Magic Fix button in the inspector"))
        XCTAssertTrue(storyboard.contains("export preset claims"))
        XCTAssertTrue(storyboard.contains("captions or demo-pack claims"))

        XCTAssertTrue(generator.contains("appstore-01-editing-dark-mac.png"))
        XCTAssertTrue(generator.contains("appstore-02-magic-fix-dark-mac.png"))
        XCTAssertTrue(generator.contains("appstore-03-recording-complete-dark-mac.png"))
        XCTAssertTrue(generator.contains("Edit locally with Magic Fix tools"))
        XCTAssertTrue(generator.contains("Polish clips with Magic Fix"))
        XCTAssertTrue(generator.contains("realAppSource"))
        XCTAssertTrue(generator.contains("outputs/visual-audit-20260603/01-editor-real-fixture.png"))
        XCTAssertTrue(generator.contains("outputs/appstore-real-captures/04-inspector-magic-fix.png"))
        XCTAssertTrue(generator.contains("outputs/appstore-real-captures/05-recording-complete.png"))
        XCTAssertTrue(generator.contains("Do not generate synthetic UI"))
        XCTAssertTrue(generator.contains("duplicateRealAppSources"))
        XCTAssertFalse(generator.contains("demo-laptop-main.jpg"))
        XCTAssertFalse(generator.contains("NSBezierPath"))
        XCTAssertFalse(generator.contains("appstore-03-export-dark-mac.png"))
        XCTAssertFalse(generator.contains("appstore-04-captions-demo-pack-dark-mac.png"))
        XCTAssertFalse(generator.contains("appstore-05-magic-fix-dark-mac.png"))
        XCTAssertFalse(generator.contains("appstore-03-inspector-tools-dark-mac.png"))
        XCTAssertFalse(generator.contains("websiteName: \"sanevideo-export.png\""))
        XCTAssertFalse(generator.contains("websiteName: \"sanevideo-captions-demo-pack.png\""))
        XCTAssertFalse(generator.contains("websiteName: \"sanevideo-inspector-tools.png\""))
        XCTAssertTrue(website.contains("Local Mac recording and editing."))
        XCTAssertTrue(website.contains("The workflow you actually use."))
        XCTAssertTrue(website.contains("Magic Fix on device"))
        XCTAssertTrue(website.contains("Timeline editing + Magic Fix"))
        XCTAssertTrue(website.contains("sanevideo-actual-edit-workflow.png"))
        XCTAssertTrue(website.contains("sanevideo-magic-fix.png"))
        XCTAssertTrue(website.contains("sanevideo-recording-complete.png"))
        XCTAssertTrue(website.contains("Local files"))
        XCTAssertFalse(website.contains("Proof rebuild in progress"))
        XCTAssertFalse(website.contains("mockups"))
        XCTAssertFalse(website.contains("synthetic product screenshots"))
        XCTAssertFalse(website.contains("sanevideo-recording.png"))
        XCTAssertFalse(website.contains("sanevideo-export"))
        XCTAssertFalse(website.contains("sanevideo-captions"))
        XCTAssertFalse(website.contains("sanevideo-inspector-tools"))
        XCTAssertFalse(generator.contains("YouTube upload unavailable"))
        XCTAssertFalse(generator.contains("Disabled in v1"))
    }

    func testIdleRecordingControlsAvoidContinuousGradientAnimation() throws {
        let audioVisualizer = try String(
            contentsOf: sourceRoot.appendingPathComponent("SaneVideo/Views/Components/AudioVisualizerView.swift"),
            encoding: .utf8
        )

        XCTAssertFalse(
            audioVisualizer.contains("repeatForever"),
            "Idle mic controls must not continuously redraw conic gradients; update only on audio-level changes."
        )
        XCTAssertFalse(audioVisualizer.contains("@State private var rotation"))
    }
}
